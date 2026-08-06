--!nonstrict

local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local AdminConfig = require(Shared.Config.AdminConfig)
local ServerConfig = require(script.Parent.Parent.Config.ServerConfig)
local EggConfig = require(Shared.Config.EggConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local GameConfig = require(Shared.Config.GameConfig)
local GooseStats = require(Shared.Util.GooseStats)
local NetServer = require(Shared.Net.NetServer)

local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local InventoryService = require(script.Parent.InventoryService)
local EggService = require(script.Parent.EggService)
local IncomeService = require(script.Parent.IncomeService)
local MonetizationService = require(script.Parent.MonetizationService)
local BanService = require(script.Parent.BanService)
local AntiCheatService = require(script.Parent.AntiCheatService)
local BallEventService = require(script.Parent.BallEventService)

--[[
	연출과 2층은 나중에 붙인 기능이다.

	모듈을 안 넣은 place 에서도 관리자 패널 자체는 열려야 하므로,
	있으면 쓰고 없으면 그 명령만 "미구현" 으로 답한다.
]]
local function optional(name: string)
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn(("[AdminService] %s 로드 실패: %s"):format(name, tostring(result)))
		return nil
	end
	return result
end

local ShowService = optional("ShowService")
local FloorService = optional("FloorService")

local AdminService = {}

local TOPIC = "RAD_AdminCommand"
local auditStore = DataStoreService:GetDataStore("RAD_AdminAudit_v1")

local SERVER_CODE = AdminConfig.serverCode()
local frozen: { [Player]: boolean } = {}

local adminCache: { [number]: boolean } = {}

function AdminService.isAdmin(player: Player): boolean
	if not player or not player.Parent then
		return false
	end

	local cached = adminCache[player.UserId]
	if cached ~= nil then
		return cached
	end

	local result = false

	if ServerConfig.Admin.Admins[player.UserId] then
		result = true
	elseif ServerConfig.Admin.AllowInStudio and RunService:IsStudio() then
		result = true
	elseif ServerConfig.Admin.Group.GroupId ~= 0 then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(ServerConfig.Admin.Group.GroupId)
		end)
		if ok and rank and rank >= ServerConfig.Admin.Group.MinRank then
			result = true
		end
	end

	adminCache[player.UserId] = result
	return result
end

local function audit(actor: Player, commandId: string, payload, outcome: string)
	task.spawn(function()
		local entry = {
			actorId = actor and actor.UserId or 0,
			actorName = actor and actor.Name or "server",
			command = commandId,
			payload = payload,
			outcome = outcome,
			jobId = game.JobId,
			serverCode = SERVER_CODE,
			at = os.time(),
		}
		local key = ("admin_%d_%s"):format(os.time(), HttpService:GenerateGUID(false):sub(1, 8))
		local ok, err = pcall(function()
			auditStore:SetAsync(key, entry)
		end)
		if not ok then
			warn("[AdminService] 감사 로그 저장 실패: " .. tostring(err))
		end
	end)
end

local function normalizeParams(command, raw)
	local out = {}
	if not command.params then
		return out
	end
	raw = type(raw) == "table" and raw or {}

	for _, spec in ipairs(command.params) do
		local value = raw[spec.id]

		if spec.type == "number" then
			value = tonumber(value)
			if value == nil or value ~= value then
				value = spec.default or 0
			end
			value = math.clamp(value, spec.min or -math.huge, spec.max or math.huge)
			value = math.floor(value)

		elseif spec.type == "string" then
			if type(value) ~= "string" then
				value = spec.default or ""
			end
			if spec.max and #value > spec.max then
				value = string.sub(value, 1, spec.max)
			end

		elseif spec.type == "boolean" then
			if type(value) ~= "boolean" then
				value = spec.default == true
			end
		end

		out[spec.id] = value
	end
	return out
end

local function summarizeData(data)
	if not data then
		return nil
	end

	local inventory = data.inventory or {}
	local eggs, geese, totalValue, totalIncome = 0, 0, 0, 0
	local best = nil

	for _, item in ipairs(inventory) do
		local value = GooseStats.value(item)
		totalValue += value
		if item.kind == "Egg" then
			eggs += 1
		else
			geese += 1
			totalIncome += GooseStats.income(item)
		end
		if not best or value > (best.value or 0) then
			best = {
				name = item.gooseId or item.eggId,
				kind = item.kind,
				rarity = item.rarity,
				variant = item.variant,
				value = value,
			}
		end
	end

	local entitlements = {}
	for key in pairs(data.entitlements or {}) do
		table.insert(entitlements, key)
	end
	table.sort(entitlements)

	local placed = 0
	for _ in pairs(data.baseSlots or {}) do
		placed += 1
	end

	return {
		cash = data.cash or 0,
		gems = data.gems or 0,
		cashMultiplier = data.cashMultiplier or 1,
		luck = data.luck or 1,
		incomeRate = totalIncome,
		lastIncomeRate = data.lastIncomeRate or 0,

		inventoryCount = #inventory,
		eggs = eggs,
		geese = geese,
		placedSlots = placed,
		totalValue = totalValue,
		best = best,

		entitlements = entitlements,
		stats = data.stats or {},
		settings = { locale = (data.settings or {}).locale },

		created = data.created,
		lastLeave = data.lastLeave,
		offlinePending = data.offlinePending and data.offlinePending.amount or 0,
	}
end

local function lookupUser(admin: Player, query: string)
	query = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if #query < 3 then
		return { ok = false, reason = "too_short" }
	end

	local userId = nil
	local userName = nil
	local displayName = nil

	local lowered = string.lower(query)
	for _, p in ipairs(Players:GetPlayers()) do
		if string.lower(p.Name) == lowered or string.lower(p.DisplayName) == lowered then
			userId, userName, displayName = p.UserId, p.Name, p.DisplayName
			break
		end
	end

	if not userId then
		local ok, id = pcall(function()
			return Players:GetUserIdFromNameAsync(query)
		end)
		if ok and id then
			userId = id
			userName = query
			pcall(function()
				userName = Players:GetNameFromUserIdAsync(id)
			end)
			displayName = userName
		end
	end

	if not userId then
		return { ok = false, reason = "user_not_found" }
	end

	local online = Players:GetPlayerByUserId(userId)
	local data, isLive = DataService.peek(userId)

	local baseName = nil
	if online then
		local base = BaseService.getBase(online)
		baseName = base and base.Name or nil
		displayName = online.DisplayName
	end

	return {
		ok = true,
		profile = {
			userId = userId,
			name = userName,
			displayName = displayName or userName,
			online = online ~= nil,
			inThisServer = online ~= nil,
			baseName = baseName,
			isAdmin = online and AdminService.isAdmin(online) or false,
		},
		data = summarizeData(data),
		hasData = data ~= nil,
		live = isLive,
	}
end

local handlers = {}

handlers.give_cash = function(_actor, target: Player, params)
	IncomeService.addCash(target, params.amount, "admin")
	DataService.saveSoon(target, 1)
	return true
end

handlers.set_cash = function(_actor, target: Player, params)
	local profile = DataService.get(target)
	if not profile then
		return false, "not_loaded"
	end
	profile.data.cash = params.amount
	profile.dirty = true
	NetServer.fire(target, "CurrencyUpdate", { cash = profile.data.cash, gems = profile.data.gems })
	DataService.saveSoon(target, 1)
	return true
end

handlers.give_gems = function(_actor, target: Player, params)
	local profile = DataService.get(target)
	if not profile then
		return false, "not_loaded"
	end
	profile.data.gems = math.max(0, (profile.data.gems or 0) + params.amount)
	profile.dirty = true
	NetServer.fire(target, "CurrencyUpdate", { cash = profile.data.cash, gems = profile.data.gems })
	DataService.saveSoon(target, 1)
	return true
end

handlers.give_egg = function(_actor, target: Player, params)
	if not EggConfig.get(params.eggId) then
		return false, "unknown_egg"
	end
	local given = 0
	for _ = 1, params.count do
		local item = EggService.createEgg(params.eggId)
		if item and InventoryService.add(target, item) then
			given += 1
		end
	end
	if given == 0 then
		return false, "inventory_full"
	end
	DataService.saveSoon(target, 1)
	return true
end

handlers.grant_pass = function(_actor, target: Player, params)
	if not MonetizationConfig.getGamepass(params.key) then
		return false, "unknown_pass"
	end
	MonetizationService.grant(target, params.key, "admin")
	return true
end

handlers.clear_inventory = function(_actor, target: Player)
	local profile = DataService.get(target)
	if not profile then
		return false, "not_loaded"
	end

	local base = BaseService.getBase(target)
	if base then
		for i = 1, GameConfig.Base.SlotCount do
			EggService.despawnModel(base, i)
		end
	end

	profile.data.inventory = {}
	profile.data.baseSlots = {}
	profile.data.hotbar = table.create(GameConfig.Inventory.HotbarSlots, false)
	profile.dirty = true

	InventoryService.sync(target)
	DataService.flush(target)
	return true
end

handlers.reset_data = function(_actor, target: Player)
	local profile = DataService.get(target)
	if not profile then
		return false, "not_loaded"
	end

	local base = BaseService.getBase(target)
	if base then
		for i = 1, GameConfig.Base.SlotCount do
			EggService.despawnModel(base, i)
		end
	end

	profile.data.inventory = {}
	profile.data.baseSlots = {}
	profile.data.hotbar = table.create(GameConfig.Inventory.HotbarSlots, false)
	profile.data.cash = 500
	profile.data.gems = 0
	profile.data.entitlements = {}
	profile.data.stats = { hatched = 0, stolenFrom = 0, stolenBy = 0, defended = 0, sold = 0 }
	profile.data.offlinePending = nil
	profile.data.lastIncomeRate = 0
	profile.dirty = true

	DataService.flush(target)
	task.delay(0.5, function()
		if target.Parent then
			target:Kick("Your data was reset by an admin. Please rejoin. / 데이터가 초기화되었습니다. 다시 접속해 주세요.")
		end
	end)
	return true
end

handlers.unlock_base = function(_actor, target: Player, params)
	local base = BaseService.getBase(target)
	if not base then
		return false, "no_base"
	end
	BaseService.setDoorLocked(base, params.locked == true)
	return true
end

handlers.bring = function(actor: Player, target: Player)
	local actorRoot = actor.Character and actor.Character:FindFirstChild("HumanoidRootPart")
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not actorRoot or not targetRoot then
		return false, "no_character"
	end
	AntiCheatService.grantImmunity(target, 3, "어드민 소환")
	targetRoot.CFrame = actorRoot.CFrame * CFrame.new(0, 0, -4)
	return true
end

handlers.goto = function(actor: Player, target: Player)
	local actorRoot = actor.Character and actor.Character:FindFirstChild("HumanoidRootPart")
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not actorRoot or not targetRoot then
		return false, "no_character"
	end
	AntiCheatService.grantImmunity(actor, 3, "어드민 이동")
	actorRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, -4)
	return true
end

handlers.freeze = function(_actor, target: Player, params)
	local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "no_character"
	end
	if params.frozen then
		frozen[target] = true
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.UseJumpPower = true
		AntiCheatService.setExpectedSpeed(target, 0, 0)
	else
		frozen[target] = nil
		humanoid.WalkSpeed = GameConfig.Player.WalkSpeed
		humanoid.JumpPower = GameConfig.Player.JumpPower
		AntiCheatService.setExpectedSpeed(target, humanoid.WalkSpeed, humanoid.JumpPower)
	end
	return true
end

handlers.kick = function(_actor, target: Player, params)
	local reason = params.reason ~= "" and params.reason or "Kicked by an admin."
	target:Kick(reason)
	return true
end

handlers.ban = function(_actor, target: Player, params)
	return BanService.ban(target, {
		reason = params.reason ~= "" and params.reason or "admin",
		score = 0,
	})
end

handlers.unban = function(_actor, _target, _params, targetUserId: number?)
	if not targetUserId then
		return false, "no_target"
	end
	return BanService.unban(targetUserId)
end

handlers.announce = function(_actor, _target, params)
	if params.message == "" then
		return false, "empty_message"
	end
	NetServer.fireAll("Notify", {
		kind = "rare",
		icon = "icon_sound",
		text = params.message,
		duration = 8,
	})
	return true
end

handlers.anticheat_dryrun = function(_actor, _target, params)
	ServerConfig.AntiCheat.DryRun = params.dryRun == true
	return true
end

handlers.ball_event = function(_actor, _target, _params)
	local ok, reason = BallEventService.trigger()
	if not ok then
		return false, reason
	end
	return true
end

handlers.show = function(_actor, _target, params)
	if not ShowService then
		return false, "not_implemented"
	end
	local ok, reason = ShowService.trigger(params.showId, params.seconds)
	if not ok then
		return false, reason
	end
	return true
end

handlers.show_stop = function(_actor, _target, _params)
	if not ShowService then
		return false, "not_implemented"
	end
	if not ShowService.stop() then
		return false, "no_show"
	end
	return true
end

handlers.floor_two = function(_actor, target, params)
	if not FloorService then
		return false, "not_implemented"
	end
	if not target then
		return false, "not_in_this_server"
	end
	if not FloorService.setUnlocked(target, params.unlocked == true) then
		return false, "not_loaded"
	end
	return true
end

handlers.shutdown = function(_actor, _target, params)
	local seconds = params.seconds
	NetServer.fireAll("Notify", {
		kind = "error",
		icon = "icon_warning",
		text = ("Server restarting in %ds"):format(seconds),
		duration = math.min(seconds, 10),
	})
	task.delay(seconds, function()
		for _, p in ipairs(Players:GetPlayers()) do
			pcall(function()
				p:Kick("Server is restarting. Please rejoin. / 서버가 재시작됩니다. 다시 접속해 주세요.")
			end)
		end
	end)
	return true
end

function AdminService.executeLocal(commandId: string, params, targetUserId: number?, actor: Player?)
	local command = AdminConfig.get(commandId)
	if not command then
		return false, "unknown_command"
	end

	local handler = handlers[commandId]
	if not handler then
		return false, "not_implemented"
	end

	local target = nil
	if command.scope == "user" then
		if not targetUserId then
			return false, "no_target"
		end
		target = Players:GetPlayerByUserId(targetUserId)

		--[[
			밴 해제처럼 대상이 접속해 있을 수 없는 명령도 있다.
			그런 명령은 유저 ID 만으로 처리한다.
		]]
		if not target and not command.allowOffline then
			return false, "not_in_this_server"
		end
	end

	if not actor and (commandId == "bring" or commandId == "goto") then
		return false, "needs_actor"
	end

	local ok, err = handler(actor, target, params, targetUserId)
	return ok, err
end

local function publish(payload)
	local ok, err = pcall(function()
		MessagingService:PublishAsync(TOPIC, HttpService:JSONEncode(payload))
	end)
	if not ok then
		warn("[AdminService] 명령 전파 실패: " .. tostring(err))
	end
	return ok
end

local function subscribe()
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(message)
			local decoded
			local decodeOk = pcall(function()
				decoded = HttpService:JSONDecode(message.Data)
			end)
			if not decodeOk or type(decoded) ~= "table" then
				return
			end
			if decoded.fromJob == game.JobId then
				return
			end
			if decoded.serverCode and decoded.serverCode ~= "all" and decoded.serverCode ~= SERVER_CODE then
				return
			end

			local command = AdminConfig.get(decoded.commandId)
			if not command then
				return
			end

			local params = normalizeParams(command, decoded.params)
			local success, err2 = AdminService.executeLocal(decoded.commandId, params, decoded.targetUserId, nil)
			if success then
				audit(nil, decoded.commandId, {
					relayedFrom = decoded.actorName,
					targetUserId = decoded.targetUserId,
				}, "relayed_ok")
			elseif err2 ~= "not_in_this_server" then
				warn(("[AdminService] 전파 명령 실패: %s (%s)"):format(decoded.commandId, tostring(err2)))
			end
		end)
	end)
	if not ok then
		warn("[AdminService] 어드민 채널 구독 실패: " .. tostring(err))
	end
end

local function onCommand(admin: Player, commandId: string, payload)
	if not AdminService.isAdmin(admin) then
		audit(admin, commandId, { denied = true }, "permission_denied")
		return { ok = false, reason = "no_permission" }
	end

	local command = AdminConfig.get(commandId)
	if not command then
		return { ok = false, reason = "unknown_command" }
	end

	payload = type(payload) == "table" and payload or {}
	local params = normalizeParams(command, payload.params)

	if command.scope == "user" then
		local targetUserId = tonumber(payload.targetUserId)
		if not targetUserId then
			return { ok = false, reason = "no_target" }
		end

		if commandId == "inspect" then
			local result = lookupUser(admin, tostring(payload.targetName or ""))
			audit(admin, commandId, { targetUserId = targetUserId }, "ok")
			return result
		end

		if commandId == "ban" then
			local target = Players:GetPlayerByUserId(targetUserId)
			if target then
				BanService.ban(target, {
					reason = params.reason ~= "" and params.reason or "admin_ban",
					score = 0,
					evidence = { by = admin.Name, manual = true },
				})
			else
				local banConfig = {
					UserIds = { targetUserId },
					Duration = params.days and params.days > 0 and (params.days * 86400) or -1,
					DisplayReason = params.reason ~= "" and params.reason or ServerConfig.Ban.DisplayReason,
					PrivateReason = ("Admin ban by %s"):format(admin.Name),
					ExcludeAltAccounts = not params.alts,
					ApplyToUniverse = true,
				}
				local ok, err = pcall(function()
					Players:BanAsync(banConfig)
				end)
				if not ok then
					audit(admin, commandId, { targetUserId = targetUserId }, "ban_failed")
					return { ok = false, reason = "ban_failed", detail = tostring(err) }
				end
			end

			if params.shame then
				local name = payload.targetName or tostring(targetUserId)
				BanService.broadcastShame(name)
			end

			audit(admin, commandId, { targetUserId = targetUserId, params = params }, "ok")
			return { ok = true, dispatched = false }
		end

		local localOk, localErr = AdminService.executeLocal(commandId, params, targetUserId, admin)
		if localOk then
			audit(admin, commandId, { targetUserId = targetUserId, params = params }, "ok")
			return { ok = true, dispatched = false }
		end

		if localErr == "not_in_this_server" then
			if command.sameServerOnly then
				return { ok = false, reason = "not_in_this_server" }
			end
			publish({
				commandId = commandId,
				params = params,
				targetUserId = targetUserId,
				serverCode = "all",
				actorName = admin.Name,
				fromJob = game.JobId,
			})
			audit(admin, commandId, { targetUserId = targetUserId, params = params }, "dispatched")
			return { ok = true, dispatched = true }
		end

		audit(admin, commandId, { targetUserId = targetUserId, params = params }, "failed:" .. tostring(localErr))
		return { ok = false, reason = localErr }
	end

	local scope = payload.serverScope
	local code = nil
	if scope == "code" then
		code = AdminConfig.normalizeCode(tostring(payload.serverCode or ""))
		if not code then
			return { ok = false, reason = "bad_server_code" }
		end
	end

	local ranHere = false
	if scope == "all" or code == SERVER_CODE then
		local ok = AdminService.executeLocal(commandId, params, nil, admin)
		ranHere = ok == true
	end

	local dispatched = false
	if scope == "all" or (code and code ~= SERVER_CODE) then
		dispatched = publish({
			commandId = commandId,
			params = params,
			serverCode = scope == "all" and "all" or code,
			actorName = admin.Name,
			fromJob = game.JobId,
		})
	end

	audit(admin, commandId, { scope = scope, code = code, params = params }, "ok")
	return { ok = ranHere or dispatched, ranHere = ranHere, dispatched = dispatched }
end

local function onLookup(admin: Player, query: string)
	if not AdminService.isAdmin(admin) then
		return { ok = false, reason = "no_permission" }
	end
	return lookupUser(admin, query)
end

local function onServerInfo(admin: Player)
	if not AdminService.isAdmin(admin) then
		return { ok = false, reason = "no_permission" }
	end

	local players = {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(players, {
			userId = p.UserId,
			name = p.Name,
			displayName = p.DisplayName,
		})
	end

	return {
		ok = true,
		serverCode = SERVER_CODE,
		jobId = game.JobId,
		placeId = game.PlaceId,
		playerCount = #players,
		maxPlayers = Players.MaxPlayers,
		uptime = math.floor(workspace.DistributedGameTime),
		players = players,
		anticheatDryRun = ServerConfig.AntiCheat.DryRun,
	}
end

function AdminService.start()
	NetServer.onFunction("AdminCommand", onCommand)
	NetServer.onFunction("AdminLookup", onLookup)
	NetServer.onFunction("AdminServerInfo", onServerInfo)

	if not RunService:IsStudio() then
		subscribe()
	end

	local function notify(player: Player)
		task.spawn(function()
			if AdminService.isAdmin(player) then
				NetServer.fire(player, "AdminState", {
					isAdmin = true,
					serverCode = SERVER_CODE,
				})
			end
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		task.wait(2)
		if player.Parent then
			notify(player)
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		notify(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		adminCache[player.UserId] = nil
		frozen[player] = nil
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			if not frozen[player] then
				return
			end
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid then
				humanoid.WalkSpeed = 0
				humanoid.JumpPower = 0
				AntiCheatService.setExpectedSpeed(player, 0, 0)
			end
		end)
	end)

end

AdminService.SERVER_CODE = SERVER_CODE

return AdminService

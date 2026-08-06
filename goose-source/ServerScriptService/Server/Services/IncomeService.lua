--!nonstrict

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local GooseStats = require(Shared.Util.GooseStats)
local NetServer = require(Shared.Net.NetServer)

local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local BallEventService = require(script.Parent.BallEventService)
local BaseService = require(script.Parent.BaseService)
local InventoryService = require(script.Parent.InventoryService)
local TutorialService = require(script.Parent.TutorialService)

local IncomeService = {}

--[[
	둥지 온기는 나중에 붙인 부가 기능이다.

	넣지 않은 place 에서도 수입 계산이 그대로 돌아야 하므로
	모듈이 있을 때만 가져오고, 없으면 배율 1로 둔다.
]]
local WarmthService = nil
do
	local module = script.Parent:FindFirstChild("WarmthService")
	if module then
		local ok, result = pcall(require, module)
		if ok then
			WarmthService = result
		else
			warn("[IncomeService] WarmthService 로드 실패: " .. tostring(result))
		end
	end
end

local CFG = GameConfig.Income
local B = GameConfig.Base

local fractional: { [Player]: { [string]: number } } = {}
local collectorsByBase = setmetatable({}, { __mode = "k" })
local touchDebounce = setmetatable({}, { __mode = "k" })

local function earningsFor(profile)
	if type(profile.data.unitEarnings) ~= "table" then
		profile.data.unitEarnings = {}
		profile.dirty = true
	end
	return profile.data.unitEarnings
end

local function findInData(data, uid: string)
	for _, item in ipairs(data.inventory or {}) do
		if item.uid == uid then
			return item
		end
	end
	return nil
end

local function incomeMultiplier(player: Player, data): number
	local cashMultiplier = tonumber(data.cashMultiplier) or 1
	local rebirths = tonumber(data.rebirths) or 0
	local rebirthBonus = 1 + rebirths * GameConfig.Rebirth.IncomePerRebirth
	local warmthBonus = WarmthService and WarmthService.multiplier(player) or 1
	return cashMultiplier
		* rebirthBonus
		* warmthBonus
		* WorldService.multiplier("Income")
		* BallEventService.multiplier(player)
end

local function eachPlacedGoose(player: Player, callback)
	local base = BaseService.getBase(player)
	if not base then
		return
	end

	for slotIndex = 1, B.SlotCount do
		local model = BaseService.getSlotModel(base, slotIndex)
		if model and model:GetAttribute("Kind") == "Goose" then
			local uid = model:GetAttribute("ItemUid")
			local item = type(uid) == "string" and InventoryService.find(player, uid) or nil
			if item then
				callback(slotIndex, model, uid, item)
			end
		end
	end
end

function IncomeService.getRate(player: Player): number
	local profile = DataService.get(player)
	if not profile then
		return 0
	end

	local multiplier = incomeMultiplier(player, profile.data)
	local total = 0
	eachPlacedGoose(player, function(_, _, _, item)
		total += GooseStats.income(item) * multiplier
	end)
	return total
end

local function getRateFromData(player: Player, data): number
	local total = 0
	local seen = {}
	for _, uid in pairs(data.baseSlots or {}) do
		if type(uid) == "string" and not seen[uid] then
			seen[uid] = true
			local item = findInData(data, uid)
			if item and item.kind == "Goose" then
				total += GooseStats.income(item)
			end
		end
	end
	return total * incomeMultiplier(player, data)
end

function IncomeService.getMultiplier(player: Player): number
	local profile = DataService.get(player)
	return profile and (profile.data.cashMultiplier or 1) or 1
end

function IncomeService.addCash(player: Player, amount: number, reason: string?)
	local profile = DataService.get(player)
	if not profile or amount == 0 then
		return false
	end
	profile.data.cash = math.max(0, (profile.data.cash or 0) + amount)
	profile.dirty = true
	DataService.syncLeaderstats(player)

	NetServer.fire(player, "CurrencyUpdate", {
		cash = profile.data.cash,
		gems = profile.data.gems,
		delta = amount,
		reason = reason,
	})
	if reason == "collect" then
		TutorialService.record(player, "collect_cash")
	end
	return true
end

function IncomeService.spendCash(player: Player, amount: number): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	if (profile.data.cash or 0) < amount then
		return false
	end
	profile.data.cash -= amount
	profile.dirty = true
	DataService.syncLeaderstats(player)

	NetServer.fire(player, "CurrencyUpdate", {
		cash = profile.data.cash,
		gems = profile.data.gems,
		delta = -amount,
	})
	return true
end

function IncomeService.getStored(player: Player, uid: string): number
	local profile = DataService.get(player)
	if not profile then
		return 0
	end
	return math.max(0, math.floor(tonumber(earningsFor(profile)[uid]) or 0))
end

local function setStored(model: Model?, amount: number)
	if model and model.Parent then
		model:SetAttribute("StoredCash", math.max(0, math.floor(amount)))
	end
end

local function syncStoredModels(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local earnings = earningsFor(profile)
	eachPlacedGoose(player, function(_, model, uid)
		setStored(model, earnings[uid] or 0)
	end)
end

local function addStored(profile, uid: string, amount: number): number
	amount = math.max(0, math.floor(amount))
	if amount <= 0 then
		return tonumber(earningsFor(profile)[uid]) or 0
	end
	local earnings = earningsFor(profile)
	earnings[uid] = math.max(0, math.floor(tonumber(earnings[uid]) or 0)) + amount
	profile.dirty = true
	return earnings[uid]
end

local function drainRemovedUnits(player: Player, profile): number
	local payout = 0
	local earnings = earningsFor(profile)
	for uid, amount in pairs(earnings) do
		if type(uid) ~= "string" or not InventoryService.find(player, uid) then
			payout += math.max(0, math.floor(tonumber(amount) or 0))
			earnings[uid] = nil
			profile.dirty = true
		end
	end
	return payout
end

local function drainAllStored(profile): number
	local payout = 0
	local earnings = earningsFor(profile)
	for uid, amount in pairs(earnings) do
		payout += math.max(0, math.floor(tonumber(amount) or 0))
		earnings[uid] = nil
	end
	if payout > 0 then
		profile.dirty = true
	end
	return payout
end

local function distributeStored(player: Player, amount: number): number
	local profile = DataService.get(player)
	if not profile then
		return 0
	end
	amount = math.max(0, math.floor(amount))
	if amount <= 0 then
		return 0
	end

	local units = {}
	local totalWeight = 0
	local seen = {}
	eachPlacedGoose(player, function(_, model, uid, item)
		if not seen[uid] then
			seen[uid] = true
			local weight = math.max(GooseStats.income(item), 0)
			table.insert(units, { model = model, uid = uid, weight = weight })
			totalWeight += weight
		end
	end)

	if #units == 0 or totalWeight <= 0 then
		return 0
	end

	local remaining = amount
	for index, unit in ipairs(units) do
		local share = index == #units
			and remaining
			or math.min(remaining, math.floor(amount * unit.weight / totalWeight))
		remaining -= share
		if share > 0 then
			setStored(unit.model, addStored(profile, unit.uid, share))
		end
	end
	return amount - remaining
end

function IncomeService.settleOffline(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local data = profile.data

	local lastLeave = data.lastLeave or os.time()
	local elapsed = os.time() - lastLeave
	if elapsed < CFG.MinOfflineSeconds then
		return nil
	end

	local rate = data.lastIncomeRate or 0
	if rate <= 0 then
		return nil
	end

	local exceeded = elapsed > CFG.OfflineMaxSeconds
	if exceeded and CFG.OfflineHardCutoff then
		NetServer.fire(player, "OfflineEarnings", {
			amount = 0,
			seconds = elapsed,
			expired = true,
			ratio = CFG.OfflineRatio,
		})
		return nil
	end

	local billable = math.min(elapsed, CFG.OfflineMaxSeconds)
	local amount = math.floor(rate * billable * CFG.OfflineRatio)
	if amount <= 0 then
		return nil
	end

	data.offlinePending = {
		amount = amount,
		seconds = billable,
		realSeconds = elapsed,
		exceeded = exceeded,
	}
	profile.dirty = true

	NetServer.fire(player, "OfflineEarnings", {
		amount = amount,
		seconds = billable,
		realSeconds = elapsed,
		exceeded = exceeded,
		expired = false,
		ratio = CFG.OfflineRatio,
	})
	return data.offlinePending
end

local function claimOffline(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local pending = profile.data.offlinePending
	if not pending or (pending.amount or 0) <= 0 then
		return
	end

	profile.data.offlinePending = nil
	local amount = math.max(0, math.floor(pending.amount or 0))
	if profile.data.autoCollect == true then
		IncomeService.addCash(player, amount, "offline")
	elseif distributeStored(player, amount) <= 0 then
		IncomeService.addCash(player, amount, "offline")
	end
	DataService.saveSoon(player, 1)
end

local function resolveSlot(instance: Instance): (Model?, number?)
	local node = instance
	for _ = 1, 6 do
		if not node then
			break
		end
		local index = tonumber(node.Name)
		local slotFolder = node.Parent
		if index and index >= 1 and index <= B.SlotCount
			and slotFolder and slotFolder.Name == B.SlotFolderName then
			local base = slotFolder.Parent
			if base and base:IsA("Model") and base:IsDescendantOf(BaseService.getFolder()) then
				return base, index
			end
		end
		node = node.Parent
	end
	return nil, nil
end

local function ensureTone(reward: BasePart, name: string, playbackSpeed: number, volume: number): Sound
	local sound = reward:FindFirstChild(name)
	if sound and not sound:IsA("Sound") then
		sound:Destroy()
		sound = nil
	end
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = name
		sound.Parent = reward
	end
	sound.SoundId = CFG.CollectSoundId
	sound.Volume = volume
	sound.PlaybackSpeed = playbackSpeed
	sound.RollOffMinDistance = 3
	sound.RollOffMaxDistance = 35
	return sound
end

local function playCollectSound(player: Player, reward: BasePart)
	local profile = DataService.get(player)
	if profile and profile.data.settings and profile.data.settings.sfx == false then
		return
	end
	local first = ensureTone(reward, "MoneyTone1", 1.12, CFG.CollectSoundVolume)
	local second = ensureTone(reward, "MoneyTone2", 1.48, CFG.CollectSoundVolume * 0.75)
	first.TimePosition = 0
	first:Play()
	task.delay(0.07, function()
		if second.Parent then
			second.TimePosition = 0
			second:Play()
		end
	end)
end

local function collectReward(player: Player, collector: BasePart, base: Model, slotIndex: number)
	if not BaseService.isOwner(player, base) then
		return
	end
	local model = BaseService.getSlotModel(base, slotIndex)
	if not model or model:GetAttribute("Kind") ~= "Goose" then
		return
	end
	local uid = model:GetAttribute("ItemUid")
	if type(uid) ~= "string" then
		return
	end

	local profile = DataService.get(player)
	if not profile then
		return
	end
	local earnings = earningsFor(profile)
	local amount = math.max(0, math.floor(tonumber(earnings[uid]) or 0))
	if amount <= 0 then
		return
	end

	earnings[uid] = nil
	profile.dirty = true
	setStored(model, 0)
	if not IncomeService.addCash(player, amount, "collect") then
		earnings[uid] = amount
		setStored(model, amount)
		return
	end

	playCollectSound(player, collector)
	DataService.saveSoon(player, 1)
end

local function setupSlotCollector(base: Model, slotIndex: number)
	local handle = BaseService.getHandle(base, slotIndex)
	if not handle then
		return
	end

	local reward = handle.Parent:FindFirstChild(CFG.RewardPartName, true)
	local collector = reward and reward:IsA("BasePart") and reward or handle
	local bySlot = collectorsByBase[base]
	if not bySlot then
		bySlot = {}
		collectorsByBase[base] = bySlot
	end

	local current = bySlot[slotIndex]
	if current and current.part == collector and current.connection.Connected then
		return
	end
	if current and current.connection then
		current.connection:Disconnect()
	end

	collector.CanTouch = true
	ensureTone(collector, "MoneyTone1", 1.12, CFG.CollectSoundVolume)
	ensureTone(collector, "MoneyTone2", 1.48, CFG.CollectSoundVolume * 0.75)
	local connection = collector.Touched:Connect(function(hit)
		local character = hit and hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end

		local perPart = touchDebounce[collector]
		if not perPart then
			perPart = {}
			touchDebounce[collector] = perPart
		end
		local now = os.clock()
		if now - (perPart[player] or 0) < CFG.CollectDebounce then
			return
		end
		perPart[player] = now
		collectReward(player, collector, base, slotIndex)
	end)
	bySlot[slotIndex] = { part = collector, connection = connection }

	collector.Destroying:Once(function()
		local latest = collectorsByBase[base] and collectorsByBase[base][slotIndex]
		if latest and latest.part == collector then
			latest.connection:Disconnect()
			collectorsByBase[base][slotIndex] = nil
			task.defer(setupSlotCollector, base, slotIndex)
		end
	end)
end

local function setupRewards()
	local folder = BaseService.getFolder()
	for _, base in ipairs(BaseService.allBases()) do
		for slotIndex = 1, B.SlotCount do
			setupSlotCollector(base, slotIndex)
		end
	end
	folder.DescendantAdded:Connect(function(descendant)
		local base, slotIndex = resolveSlot(descendant)
		if base and slotIndex then
			task.defer(setupSlotCollector, base, slotIndex)
		end
	end)
	folder.DescendantRemoving:Connect(function(descendant)
		local base, slotIndex = resolveSlot(descendant)
		if base and slotIndex then
			task.defer(setupSlotCollector, base, slotIndex)
		end
	end)
end

local function tickPlayer(player: Player, profile)
	local data = profile.data
	local earnings = earningsFor(profile)
	local fractions = fractional[player]
	if not fractions then
		fractions = {}
		fractional[player] = fractions
	end

	local autoCollect = data.autoCollect == true
	local payout = drainRemovedUnits(player, profile)
	if autoCollect then
		payout += drainAllStored(profile)
	end

	local multiplier = incomeMultiplier(player, data)
	local active = {}
	local totalRate = 0
	eachPlacedGoose(player, function(_, model, uid, item)
		active[uid] = true
		local rate = math.max(0, GooseStats.income(item) * multiplier)
		totalRate += rate
		model:SetAttribute("Income", rate)

		local carry = (fractions[uid] or 0) + rate * CFG.TickInterval
		local whole = math.floor(carry)
		fractions[uid] = carry - whole

		if whole > 0 then
			if autoCollect then
				payout += whole
			else
				addStored(profile, uid, whole)
			end
		end
		setStored(model, autoCollect and 0 or (earnings[uid] or 0))
	end)

	for uid in pairs(fractions) do
		if not active[uid] then
			fractions[uid] = nil
		end
	end
	data.lastIncomeRate = totalRate

	if payout > 0 then
		IncomeService.addCash(player, payout, autoCollect and "income" or "unit_removed")
	end
end

local function tick()
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = DataService.get(player)
		if profile then
			tickPlayer(player, profile)
		end
	end
end

function IncomeService.start()
	NetServer.onEvent("OfflineClaim", claimOffline)
	setupRewards()

	BaseService.BaseAssigned:Connect(function(player)
		task.defer(syncStoredModels, player)
	end)

	DataService.ProfileLoaded:Connect(function(player)
		task.delay(2, function()
			if player.Parent then
				IncomeService.settleOffline(player)
				syncStoredModels(player)
			end
		end)
	end)

	DataService.ProfileReleasing:Connect(function(player, data)
		data.lastIncomeRate = getRateFromData(player, data)
		fractional[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(CFG.TickInterval)
			local ok, err = pcall(tick)
			if not ok then
				warn("[IncomeService] 정산 오류: " .. tostring(err))
			end
		end
	end)
end

return IncomeService

--!nonstrict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local WarmthConfig = require(Shared.Config.WarmthConfig)
local ParticleAssets = require(Shared.UI.ParticleAssets)
local Rng = require(Shared.Util.Rng)
local NetServer = require(Shared.Net.NetServer)

local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)

local WarmthService = {}

--[[
	IncomeService 는 배율을 물으려고 이 모듈을 require 한다.
	여기서 맞require 하면 순환이 된다. 실제로 쓸 때 가져온다.
	그 시점에는 이미 모든 모듈이 올라와 있다.
]]
local function income()
	return require(script.Parent.IncomeService)
end

local function shop()
	return require(script.Parent.ShopService)
end

--[[
	룰렛은 나중에 붙인 부가 기능이라 없는 place 도 있다.
	없으면 그냥 안 준다. 여기서 에러가 나면 황금알 자체를 못 받는다.
]]
local function roulette()
	local module = script.Parent:FindFirstChild("RouletteService")
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return ok and result or nil
end

local TICK = 1
local SYNC_INTERVAL = 5
local RUNTIME_NAME = "RadGoldenEgg"
local RUNTIME_TAG = "RadGoldenEgg"

local rng = Random.new(os.clock() * 1e6)
local started = false

--[[
	runtime 은 이번 판에만 쓰는 값이다. 저장하지 않는다.

	황금알 시계를 저장하지 않는 게 핵심이다. 나가면 처음부터 다시 3분이므로
	"조금 있으면 떨어지는데" 를 두고 나가는 게 손해가 된다.
]]
local runtime: { [Player]: any } = {}

local function ensure(data)
	if type(data.warmth) ~= "table" then
		data.warmth = {}
	end
	local w = data.warmth
	w.value = math.clamp(tonumber(w.value) or 0, 0, WarmthConfig.Max)
	w.seenAt = math.max(math.floor(tonumber(w.seenAt) or 0), 0)
	w.eggsClaimed = math.max(math.floor(tonumber(w.eggsClaimed) or 0), 0)
	w.totalSeconds = math.max(math.floor(tonumber(w.totalSeconds) or 0), 0)
	w.bestValue = math.clamp(tonumber(w.bestValue) or w.value, 0, WarmthConfig.Max)
	return w
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

--------------------------------------------------------------------------------
-- 상태 전달
--------------------------------------------------------------------------------

local function statePayload(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "not_loaded" }
	end

	local w = ensure(profile.data)
	local index = WarmthConfig.tierIndexFor(w.value)
	local tier = WarmthConfig.tier(index)
	local nextTier = WarmthConfig.nextTier(index)
	local rt = runtime[player]
	local egg = rt and rt.egg
	local eggAlive = egg ~= nil and egg.Parent ~= nil

	return {
		ok = true,
		serverNow = Workspace:GetServerTimeNow(),

		value = w.value,
		max = WarmthConfig.Max,
		fillPerMinute = WarmthConfig.FillPerMinute,
		idle = rt ~= nil and rt.idle == true,

		tierIndex = index,
		tierCount = #WarmthConfig.Tiers,
		tierKey = tier.LocaleKey,
		palette = tier.Palette,
		icon = tier.Icon,
		multiplier = tier.Multiplier,

		nextKey = nextTier and nextTier.LocaleKey or nil,
		nextMultiplier = nextTier and nextTier.Multiplier or nil,
		nextThreshold = nextTier and nextTier.Threshold or nil,
		secondsToNextTier = WarmthConfig.secondsToNextTier(w.value),

		nextDropAt = rt and rt.nextDropAt or nil,
		dropExpiresAt = eggAlive and rt.eggExpiresAt or nil,
		dropWaiting = eggAlive,

		graceSeconds = WarmthConfig.GraceSeconds,
		decayPerMinute = WarmthConfig.DecayPerMinute,
		eggsClaimed = w.eggsClaimed,
	}
end

local function sync(player: Player)
	if not player.Parent then
		return
	end
	local rt = runtime[player]
	if rt then
		rt.syncAt = os.clock()
	end
	NetServer.fire(player, "WarmthSync", statePayload(player))
end

--------------------------------------------------------------------------------
-- 황금알
--------------------------------------------------------------------------------

local function anchorPosition(player: Player): Vector3?
	local base = BaseService.getBase(player)
	if not base then
		return nil
	end

	local spawnPart = base:FindFirstChild(GameConfig.Base.SpawnPartName)
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart.Position + Vector3.new(0, WarmthConfig.Drop.HoverHeight, 0)
	end

	local ok, pivot = pcall(function()
		return base:GetPivot().Position
	end)
	if not ok or typeof(pivot) ~= "Vector3" then
		return nil
	end
	return pivot + Vector3.new(0, WarmthConfig.Drop.HoverHeight, 0)
end

--[[
	알은 서버가 놓고 그 자리에 그대로 둔다.

	위아래로 까딱이거나 도는 건 클라이언트가 한다. 서버가 매 프레임 CFrame 을
	바꾸면 사람 수만큼 복제 트래픽이 늘어나는데, 보이는 것 말고는 얻는 게 없다.
	줍는 판정은 서버가 거리로 다시 재므로 흔들려 보여도 결과는 같다.
]]
local function buildEgg(player: Player, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = RUNTIME_NAME
	model:SetAttribute(RUNTIME_TAG, true)
	model:SetAttribute("OwnerUserId", player.UserId)

	local egg = Instance.new("Part")
	egg.Name = "Egg"
	egg.Size = Vector3.new(3.1, 3.1, 3.1)
	egg.Anchored = true
	egg.CanCollide = false
	egg.CanQuery = false
	egg.CanTouch = false
	egg.CastShadow = false
	egg.Material = Enum.Material.Neon
	egg.Color = Color3.fromRGB(255, 205, 66)
	egg.Position = position
	egg:SetAttribute(RUNTIME_TAG, true)
	egg.Parent = model

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.34, 1)
	mesh.Parent = egg

	local light = Instance.new("PointLight")
	light.Brightness = 3
	light.Range = 26
	light.Color = Color3.fromRGB(255, 214, 110)
	light.Parent = egg

	local attachment = Instance.new("Attachment")
	attachment.Name = "Sparkles"
	attachment.Parent = egg

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = ParticleAssets.get("Spark")
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 232, 150), Color3.fromRGB(255, 176, 40))
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 1.1),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new(0.15)
	sparkles.Rate = 22
	sparkles.Lifetime = NumberRange.new(0.7, 1.3)
	sparkles.Speed = NumberRange.new(2, 5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = attachment

	--[[
		빛기둥. 알 자체는 3스터드라 조금만 멀어져도 안 보인다.
		기지 위로 솟은 기둥이 있어야 "저기 떨어졌다" 가 한눈에 들어온다.
	]]
	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(60, 5.5, 5.5)
	beam.CFrame = CFrame.new(position + Vector3.new(0, 22, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 214, 110)
	beam.Transparency = 0.86
	beam.Parent = model

	model.PrimaryPart = egg
	model.Parent = Workspace
	return model
end

local function destroyEgg(player: Player)
	local rt = runtime[player]
	if not rt then
		return
	end
	if rt.egg then
		rt.egg:Destroy()
		rt.egg = nil
	end
	rt.eggExpiresAt = nil
end

local function scheduleNextDrop(player: Player, tierIndex: number?, firstOfSession: boolean?)
	local rt = runtime[player]
	if not rt then
		return
	end
	local D = WarmthConfig.Drop
	local wait = firstOfSession and D.FirstSeconds or WarmthConfig.dropInterval(tierIndex or 1)
	rt.nextDropAt = Workspace:GetServerTimeNow() + wait
	rt.warned = false
end

local function spawnDrop(player: Player, tierIndex: number)
	local rt = runtime[player]
	if not rt then
		return
	end

	local position = anchorPosition(player)
	if not position then
		--[[
			기지를 아직 못 받았다. 이건 플레이어 잘못이 아니므로
			보상을 날리지 않고 조금 뒤에 다시 시도한다.
		]]
		rt.nextDropAt = Workspace:GetServerTimeNow() + 20
		rt.warned = true
		return
	end

	destroyEgg(player)

	local ok, model = pcall(buildEgg, player, position)
	if not ok or not model then
		warn("[WarmthService] 황금알 생성 실패: " .. tostring(model))
		scheduleNextDrop(player, tierIndex)
		return
	end

	rt.egg = model
	rt.eggExpiresAt = Workspace:GetServerTimeNow() + WarmthConfig.Drop.LifetimeSeconds
	rt.nextDropAt = nil

	NetServer.fire(player, "WarmthDrop", {
		state = "landed",
		expiresAt = rt.eggExpiresAt,
		tierIndex = tierIndex,
		position = position,
	})

	if tierIndex >= WarmthConfig.Drop.AnnounceFromTier then
		NetServer.fireExcept(player, "Notify", {
			key = "warmth_announce",
			args = { player.DisplayName },
			kind = "rare",
			icon = "icon_egg",
			duration = 5,
		})
	end

	sync(player)
end

local function rollEggId(): string?
	return Rng.weightedPick(WarmthConfig.Drop.EggPool, rng)
end

local function claimDrop(player: Player)
	local rt = runtime[player]
	if not rt or not rt.egg then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local w = ensure(profile.data)
	local tierIndex = WarmthConfig.tierIndexFor(w.value)

	local rate = 0
	local okRate, result = pcall(function()
		return income().getRate(player)
	end)
	if okRate then
		rate = tonumber(result) or 0
	end

	local cash = WarmthConfig.dropCash(tierIndex, rate)
	local extras = {}

	-- 알을 먼저 시도한다. 가방이 가득 차면 현금으로 바꿔 얹어 준다.
	if rng:NextNumber() < WarmthConfig.dropChance(WarmthConfig.Drop.EggChance, tierIndex) then
		local eggId = rollEggId()
		if eggId then
			local called, granted = pcall(function()
				return shop().grantEgg(player, eggId, 1, "warmth") == true
			end)
			if called and granted then
				table.insert(extras, { kind = "egg", eggId = eggId, amount = 1 })
			else
				cash += math.floor(cash * WarmthConfig.Drop.EggFallbackRatio)
				table.insert(extras, { kind = "egg_failed", eggId = eggId })
			end
		end
	end

	if rng:NextNumber() < WarmthConfig.dropChance(WarmthConfig.Drop.SpinChance, tierIndex) then
		local service = roulette()
		if service and service.addPaidSpins then
			local okSpin = pcall(service.addPaidSpins, player, 1)
			if okSpin then
				table.insert(extras, { kind = "spin", amount = 1 })
			end
		end
	end

	if cash > 0 then
		income().addCash(player, cash, "warmth_egg")
	end

	w.eggsClaimed += 1
	profile.dirty = true
	DataService.saveSoon(player, 1)

	destroyEgg(player)
	scheduleNextDrop(player, tierIndex)

	NetServer.fire(player, "WarmthDrop", {
		state = "claimed",
		cash = cash,
		extras = extras,
		tierIndex = tierIndex,
		nextDropAt = rt.nextDropAt,
	})
	sync(player)
end

local function expireDrop(player: Player)
	local rt = runtime[player]
	if not rt then
		return
	end
	local tierIndex = 1
	local profile = DataService.get(player)
	if profile then
		tierIndex = WarmthConfig.tierIndexFor(ensure(profile.data).value)
	end

	destroyEgg(player)
	scheduleNextDrop(player, tierIndex)

	NetServer.fire(player, "WarmthDrop", {
		state = "expired",
		nextDropAt = rt.nextDropAt,
	})
	sync(player)
end

--------------------------------------------------------------------------------
-- 매 초 계산
--------------------------------------------------------------------------------

local function updateIdle(player: Player, rt): boolean
	local position = rootPosition(player)
	local now = os.clock()

	if not position then
		-- 캐릭터가 아직 없다. 죽거나 로딩 중인 걸 방치로 볼 수는 없다.
		rt.movedAt = now
		return false
	end

	if not rt.lastPos or (position - rt.lastPos).Magnitude >= WarmthConfig.IdleMoveStuds then
		rt.lastPos = position
		rt.movedAt = now
	end

	return (now - (rt.movedAt or now)) >= WarmthConfig.IdleSeconds
end

local function tickPlayer(player: Player, profile, rt)
	local w = ensure(profile.data)
	local wasIdle = rt.idle
	rt.idle = updateIdle(player, rt)
	if rt.idle ~= wasIdle then
		sync(player)
	end

	local now = Workspace:GetServerTimeNow()

	if not rt.idle then
		if w.value < WarmthConfig.Max then
			w.value = math.clamp(w.value + WarmthConfig.FillPerMinute / 60 * TICK, 0, WarmthConfig.Max)
			if w.value > w.bestValue then
				w.bestValue = w.value
			end
			profile.dirty = true
		end
		w.totalSeconds += TICK
	end
	w.seenAt = os.time()

	local tierIndex = WarmthConfig.tierIndexFor(w.value)
	if tierIndex > (rt.tierIndex or tierIndex) then
		local tier = WarmthConfig.tier(tierIndex)
		NetServer.fire(player, "Notify", {
			key = "warmth_tier_up",
			args = { { key = tier.LocaleKey }, string.format("%.2f", tier.Multiplier) },
			kind = "rare",
			icon = tier.Icon,
			duration = 5,
		})
		DataService.saveSoon(player, 2)
		sync(player)
	end
	rt.tierIndex = tierIndex

	--[[
		떨어져 있는 알은 방치 중이어도 계속 흐른다.

		주우러 오지 않으면 사라지는 게 이 알의 규칙이다.
		방치한 사람 앞에 알이 영원히 떠 있으면 방치가 이득이 된다.
	]]
	if rt.egg then
		local part = rt.egg.Parent and rt.egg.PrimaryPart
		if not part then
			rt.egg = nil
			scheduleNextDrop(player, tierIndex)
		elseif NetServer.isNear(player, part.Position, WarmthConfig.Drop.CollectRadius) then
			claimDrop(player)
		elseif now >= (rt.eggExpiresAt or 0) then
			expireDrop(player)
		end
	elseif rt.nextDropAt then
		if rt.idle then
			-- 방치 중에는 다음 알 시계를 멈춘다. 안 그러면 자리를 비운 사이에 떨어져 버린다.
			rt.nextDropAt += TICK
		else
			local remaining = rt.nextDropAt - now
			if remaining <= 0 then
				spawnDrop(player, tierIndex)
			elseif not rt.warned and remaining <= WarmthConfig.Drop.WarnSeconds then
				rt.warned = true
				NetServer.fire(player, "WarmthDrop", { state = "incoming", at = rt.nextDropAt })
			end
		end
	end

	if os.clock() - (rt.syncAt or 0) >= SYNC_INTERVAL then
		sync(player)
	end
end

local function tick()
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = DataService.get(player)
		local rt = runtime[player]
		if profile and rt then
			tickPlayer(player, profile, rt)
		end
	end
end

--------------------------------------------------------------------------------
-- 접속 / 종료
--------------------------------------------------------------------------------

--[[
	나가 있던 동안 얼마나 식었는지 계산한다.

	반환값은 (자리를 비운 초, 그대로 지켜졌는가).
	처음 오는 사람은 seenAt 이 0 이므로 아무것도 하지 않는다.

	seenAt 은 나갈 때만이 아니라 매 초 갱신한다.
	나갈 때만 적으면 서버가 그냥 꺼진 판에서는 아예 안 적히고,
	그 사람은 며칠 뒤에 들어와도 온기가 그대로 남는다.
]]
local function applyCooling(w): (number, boolean)
	if w.seenAt <= 0 then
		return 0, true
	end

	local away = math.max(os.time() - w.seenAt, 0)
	if away <= WarmthConfig.GraceSeconds then
		return away, true
	end

	local lost = (away - WarmthConfig.GraceSeconds) / 60 * WarmthConfig.DecayPerMinute
	w.value = math.max(0, w.value - lost)
	return away, false
end

local function onLoaded(player: Player, data)
	local w = ensure(data)
	local before = w.value
	local away, kept = applyCooling(w)
	w.seenAt = os.time()

	local profile = DataService.get(player)
	if profile then
		profile.dirty = true
	end

	runtime[player] = {
		nextDropAt = nil,
		warned = false,
		egg = nil,
		eggExpiresAt = nil,
		idle = false,
		lastPos = nil,
		movedAt = os.clock(),
		tierIndex = WarmthConfig.tierIndexFor(w.value),
		syncAt = 0,
	}
	scheduleNextDrop(player, runtime[player].tierIndex, true)

	task.delay(3, function()
		if not player.Parent or not DataService.get(player) then
			return
		end

		if before > 0 and away > 0 then
			local tier = WarmthConfig.tierFor(w.value)
			if kept then
				NetServer.fire(player, "Notify", {
					key = "warmth_welcome_kept",
					args = { { key = tier.LocaleKey }, string.format("%.2f", tier.Multiplier) },
					kind = "success",
					icon = "icon_fire",
					duration = 5,
				})
			elseif w.value > 0 then
				NetServer.fire(player, "Notify", {
					key = "warmth_welcome_cooled",
					args = { string.format("%.2f", tier.Multiplier) },
					kind = "info",
					icon = "icon_clock",
					duration = 5,
				})
			else
				NetServer.fire(player, "Notify", {
					key = "warmth_welcome_cold",
					kind = "info",
					icon = "icon_clock",
					duration = 5,
				})
			end
		end

		sync(player)
	end)
end

local function onReleasing(player: Player, data)
	local w = ensure(data)
	w.seenAt = os.time()
	destroyEgg(player)
	runtime[player] = nil
end

--------------------------------------------------------------------------------
-- 바깥에서 쓰는 것
--------------------------------------------------------------------------------

--- IncomeService 가 매 초 부른다. 프로필만 읽고 쓰지 않는다.
function WarmthService.multiplier(player: Player): number
	local profile = DataService.get(player)
	if not profile then
		return 1
	end
	local w = profile.data.warmth
	if type(w) ~= "table" then
		return 1
	end
	return WarmthConfig.multiplierFor(tonumber(w.value) or 0)
end

function WarmthService.getState(player: Player)
	return statePayload(player)
end

--- 관리자 도구나 다른 서비스에서 온기를 직접 건드릴 때 쓴다.
function WarmthService.setValue(player: Player, value: number): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	local w = ensure(profile.data)
	w.value = math.clamp(tonumber(value) or 0, 0, WarmthConfig.Max)
	profile.dirty = true

	local rt = runtime[player]
	if rt then
		rt.tierIndex = WarmthConfig.tierIndexFor(w.value)
	end
	DataService.saveSoon(player, 1)
	sync(player)
	return true
end

local function clearStrays()
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:GetAttribute(RUNTIME_TAG) == true then
			child:Destroy()
		end
	end
end

function WarmthService.start()
	if started then
		return
	end
	started = true

	clearStrays()

	NetServer.onFunction("WarmthGetState", function(player)
		return statePayload(player)
	end)

	DataService.ProfileLoaded:Connect(onLoaded)
	DataService.ProfileReleasing:Connect(onReleasing)

	Players.PlayerRemoving:Connect(function(player)
		destroyEgg(player)
		runtime[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		local profile = DataService.get(player)
		if profile and not runtime[player] then
			onLoaded(player, profile.data)
		end
	end

	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(tick)
			if not ok then
				warn("[WarmthService] 정산 오류: " .. tostring(err))
			end
		end
	end)
end

return WarmthService

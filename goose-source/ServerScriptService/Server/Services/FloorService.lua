--!nonstrict

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local FloorConfig = require(Shared.Config.FloorConfig)
local GameConfig = require(Shared.Config.GameConfig)
local NetServer = require(Shared.Net.NetServer)

local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local IndexService = require(script.Parent.IndexService)

local FloorService = {}

local B = GameConfig.Base
local ORIGINAL_ATTRIBUTE = "RadFloorOriginal"

local started = false

local function ensure(data)
	if type(data.floors) ~= "table" then
		data.floors = {}
	end
	local floors = data.floors
	floors.two = floors.two == true
	floors.welcomed = floors.welcomed == true
	floors.unlockedAt = math.max(math.floor(tonumber(floors.unlockedAt) or 0), 0)
	return floors
end

--------------------------------------------------------------------------------
-- 막고 있는 파트
--------------------------------------------------------------------------------

--[[
	기지에서 2층을 막고 있는 파트들.

	파트 하나면 그것만, 모델이면 그 안의 파트를 전부 다룬다.
	계단 입구를 여러 조각으로 만들어 둔 경우가 흔해서 모델도 받는다.
]]
local function blockers(base: Model): { BasePart }
	local node = base:FindFirstChild(FloorConfig.PartName, true)
	if not node then
		return {}
	end
	if node:IsA("BasePart") then
		return { node }
	end

	local parts = {}
	for _, descendant in ipairs(node:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

--[[
	원래 모습을 한 번만 적어 둔다.

	적어 두지 않으면 잠글 때 무엇으로 되돌려야 할지 알 수 없다.
	기지는 사람이 나가면 다음 사람에게 넘어가므로 되돌릴 일이 반드시 생긴다.
]]
local function remember(part: BasePart)
	if part:GetAttribute(ORIGINAL_ATTRIBUTE) ~= nil then
		return
	end
	part:SetAttribute(ORIGINAL_ATTRIBUTE, true)
	part:SetAttribute("RadFloorTransparency", part.Transparency)
	part:SetAttribute("RadFloorCanCollide", part.CanCollide)
	part:SetAttribute("RadFloorCanQuery", part.CanQuery)
	part:SetAttribute("RadFloorCanTouch", part.CanTouch)
end

local function setOpen(base: Model, open: boolean)
	if not base or not base.Parent then
		return nil
	end

	local parts = blockers(base)
	for _, part in ipairs(parts) do
		remember(part)
		if open then
			part.Transparency = FloorConfig.Open.Transparency
			part.CanCollide = FloorConfig.Open.CanCollide
			part.CanQuery = FloorConfig.Open.CanQuery
			part.CanTouch = FloorConfig.Open.CanTouch
		else
			part.Transparency = tonumber(part:GetAttribute("RadFloorTransparency")) or 0
			part.CanCollide = part:GetAttribute("RadFloorCanCollide") ~= false
			part.CanQuery = part:GetAttribute("RadFloorCanQuery") ~= false
			part.CanTouch = part:GetAttribute("RadFloorCanTouch") ~= false
		end
	end

	--[[
		슬롯 잠금은 BaseService 가 이 속성 하나만 보고 판단한다.
		서비스끼리 서로를 require 하지 않아도 되므로 순환이 생기지 않는다.
	]]
	base:SetAttribute(B.FloorTwoAttribute, open)
	return parts[1]
end

--------------------------------------------------------------------------------
-- 상태
--------------------------------------------------------------------------------

local function guidePart(player: Player): BasePart?
	local base = BaseService.getBase(player)
	if not base then
		return nil
	end
	return blockers(base)[1]
end

local function statePayload(player: Player, extra)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "not_loaded" }
	end

	local floors = ensure(profile.data)
	local payload = {
		ok = true,
		unlocked = floors.two,
		welcomed = floors.welcomed,
		count = IndexService.discoveredCount(player),
		required = FloorConfig.Required,
		extraSlots = FloorConfig.ExtraSlots,
		totalSlots = B.SlotCount,
		groundSlots = B.GroundSlotCount,
		part = floors.two and guidePart(player) or nil,
	}

	for key, value in pairs(extra or {}) do
		payload[key] = value
	end
	return payload
end

local function sync(player: Player, extra)
	if player.Parent then
		NetServer.fire(player, "FloorSync", statePayload(player, extra))
	end
end

function FloorService.getState(player: Player)
	return statePayload(player)
end

function FloorService.hasFloorTwo(player: Player): boolean
	local profile = DataService.get(player)
	if not profile or type(profile.data.floors) ~= "table" then
		return false
	end
	return profile.data.floors.two == true
end

--------------------------------------------------------------------------------
-- 열기
--------------------------------------------------------------------------------

local function applyToBase(player: Player)
	local base = BaseService.getBase(player)
	if not base then
		return
	end
	setOpen(base, FloorService.hasFloorTwo(player))
end

--- 조건을 만족했으면 연다. 이미 열려 있으면 아무것도 하지 않는다.
function FloorService.evaluate(player: Player): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end

	local floors = ensure(profile.data)
	if floors.two then
		return false
	end

	local count = IndexService.discoveredCount(player)
	if count < FloorConfig.Required then
		return false
	end

	floors.two = true
	floors.unlockedAt = os.time()
	profile.dirty = true
	DataService.saveSoon(player, 0.5)

	applyToBase(player)
	sync(player, { justUnlocked = true })

	NetServer.fire(player, "Notify", {
		key = "floor_unlocked_toast",
		args = { FloorConfig.ExtraSlots },
		kind = "rare",
		icon = "icon_home",
		duration = 8,
	})
	return true
end

--- 관리자 도구용. 조건과 상관없이 열거나 닫는다.
function FloorService.setUnlocked(player: Player, unlocked: boolean): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end

	local floors = ensure(profile.data)
	floors.two = unlocked == true
	if not floors.two then
		floors.welcomed = false
	end
	profile.dirty = true
	DataService.saveSoon(player, 0.5)

	applyToBase(player)
	sync(player, { justUnlocked = floors.two })
	return true
end

--------------------------------------------------------------------------------
-- 올라왔는지 보기
--------------------------------------------------------------------------------

--[[
	2층에 발을 디디면 한 번만 환영한다.

	클라이언트가 알려 주는 방식은 쓰지 않는다. 안 올라가고도 보낼 수 있고,
	그러면 "2층 열림" 연출이 아무 데서나 뜬다. 서버가 직접 높이를 잰다.
]]
local function checkArrival(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local floors = ensure(profile.data)
	if not floors.two or floors.welcomed then
		return
	end

	local part = guidePart(player)
	if not part then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local threshold = part.Position.Y + part.Size.Y / 2 + FloorConfig.WelcomeHeight
	if root.Position.Y < threshold then
		return
	end

	-- 옆 건물 지붕이 아니라 내 기지 위인지 확인한다
	local flat = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(part.Position.X, 0, part.Position.Z)).Magnitude
	if flat > 90 then
		return
	end

	floors.welcomed = true
	profile.dirty = true
	DataService.saveSoon(player, 1)
	sync(player, { welcome = true })
end

--------------------------------------------------------------------------------
-- 시작
--------------------------------------------------------------------------------

local function onLoaded(player: Player, data)
	ensure(data)
	task.delay(2, function()
		if not player.Parent or not DataService.get(player) then
			return
		end
		applyToBase(player)
		FloorService.evaluate(player)
		sync(player)
	end)
end

local function onReleasing(player: Player)
	-- 다음 사람에게 넘어가기 전에 원래대로 막아 둔다
	local base = BaseService.getBase(player)
	if base then
		setOpen(base, false)
	end
end

function FloorService.start()
	if started then
		return
	end
	started = true

	NetServer.onFunction("FloorGetState", function(player)
		return statePayload(player)
	end)

	DataService.ProfileLoaded:Connect(onLoaded)
	DataService.ProfileReleasing:Connect(onReleasing)

	--[[
		여기서 기다리면 안 된다.

		기지를 받은 직후 EggService 가 저장된 슬롯을 다시 세운다.
		그때까지 2층 속성이 안 붙어 있으면 9~16번 슬롯이 잠긴 것으로 보여
		2층에 놓아 둔 거위가 사라진 것처럼 된다. 속성부터 붙이고 알림은 나중에 보낸다.
	]]
	BaseService.BaseAssigned:Connect(function(player)
		applyToBase(player)
		task.defer(sync, player)
	end)

	IndexService.Discovered:Connect(function(player)
		FloorService.evaluate(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		local profile = DataService.get(player)
		if profile then
			onLoaded(player, profile.data)
		end
	end

	task.spawn(function()
		while true do
			task.wait(FloorConfig.CheckInterval)
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(checkArrival, player)
				if not ok then
					warn("[FloorService] 2층 확인 오류: " .. tostring(err))
				end
			end
		end
	end)
end

return FloorService

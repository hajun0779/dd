--!nonstrict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local NetServer = require(Shared.Net.NetServer)
local Signal = require(Shared.Util.Signal)

local AntiCheatService = require(script.Parent.AntiCheatService)
local DataService = require(script.Parent.DataService)

local BaseService = {}

local B = GameConfig.Base

local basesFolder: Folder
local ownerToBase: { [number]: Model } = {}

BaseService.BaseAssigned = Signal.new()
BaseService.BaseReleased = Signal.new()
BaseService.DoorLockChanged = Signal.new()

function BaseService.getFolder(): Folder
	if not basesFolder or not basesFolder.Parent then
		basesFolder = Workspace:FindFirstChild(B.BasesFolderName)
		if not basesFolder then
			basesFolder = Instance.new("Folder")
			basesFolder.Name = B.BasesFolderName
			basesFolder.Parent = Workspace
		end
	end
	return basesFolder
end

function BaseService.allBases(): { Model }
	local out = {}
	for _, child in ipairs(BaseService.getFolder():GetChildren()) do
		if child:IsA("Model") and child:FindFirstChild(B.SlotFolderName) then
			table.insert(out, child)
		end
	end
	return out
end

function BaseService.getBase(player: Player): Model?
	local base = ownerToBase[player.UserId]
	if base and base.Parent then
		return base
	end
	ownerToBase[player.UserId] = nil
	return nil
end

function BaseService.getOwnerId(base: Model): number
	return tonumber(base:GetAttribute(B.OwnerAttribute)) or 0
end

function BaseService.getOwner(base: Model): Player?
	local id = BaseService.getOwnerId(base)
	if id == 0 then
		return nil
	end
	return Players:GetPlayerByUserId(id)
end

function BaseService.isOwner(player: Player, base: Model): boolean
	return BaseService.getOwnerId(base) == player.UserId
end

--[[
	이 기지에서 지금 쓸 수 있는 슬롯 수.

	2층이 열리기 전에는 1층 몫만 쓴다. 판단은 기지 모델에 붙은 속성 하나로 한다.
	FloorService 가 그 속성을 쓰고, 여기서는 읽기만 한다 — 서로 require 하지 않으므로
	순환이 생기지 않고, FloorService 를 넣지 않아도 1층은 그대로 돌아간다.
]]
function BaseService.slotLimit(base: Model): number
	if base and base:GetAttribute(B.FloorTwoAttribute) == true then
		return B.SlotCount
	end
	return B.GroundSlotCount or B.SlotCount
end

function BaseService.getHandle(base: Model, index: number): BasePart?
	if index > BaseService.slotLimit(base) then
		return nil
	end
	local slotFolder = base:FindFirstChild(B.SlotFolderName)
	if not slotFolder then
		return nil
	end
	local sub = slotFolder:FindFirstChild(tostring(index))
	if not sub then
		return nil
	end
	local handle = sub:FindFirstChild(B.HandleName)
	return (handle and handle:IsA("BasePart")) and handle or nil
end

function BaseService.resolveHandle(handle: Instance): (Model?, number?)
	if not handle or not handle:IsA("BasePart") or handle.Name ~= B.HandleName then
		return nil, nil
	end
	local slotFolder = handle.Parent
	if not slotFolder then
		return nil, nil
	end
	local index = tonumber(slotFolder.Name)
	if not index or index < 1 or index > B.SlotCount then
		return nil, nil
	end
	local container = slotFolder.Parent
	if not container or container.Name ~= B.SlotFolderName then
		return nil, nil
	end
	local base = container.Parent
	if not base or not base:IsA("Model") or not base:IsDescendantOf(BaseService.getFolder()) then
		return nil, nil
	end
	return base, index
end

function BaseService.getSlotModel(base: Model, index: number): Model?
	local handle = BaseService.getHandle(base, index)
	if not handle then
		return nil
	end
	for _, child in ipairs(handle.Parent:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("ItemUid") then
			return child
		end
	end
	return nil
end

function BaseService.getFreeSlot(base: Model): number?
	for i = 1, B.SlotCount do
		if BaseService.getHandle(base, i) and not BaseService.getSlotModel(base, i) then
			return i
		end
	end
	return nil
end

local FACE_INFO = {
	{ id = Enum.NormalId.Front, normal = Vector3.new(0, 0, -1), axes = { "X", "Y" } },
	{ id = Enum.NormalId.Back, normal = Vector3.new(0, 0, 1), axes = { "X", "Y" } },
	{ id = Enum.NormalId.Right, normal = Vector3.new(1, 0, 0), axes = { "Z", "Y" } },
	{ id = Enum.NormalId.Left, normal = Vector3.new(-1, 0, 0), axes = { "Z", "Y" } },
	{ id = Enum.NormalId.Top, normal = Vector3.new(0, 1, 0), axes = { "X", "Z" } },
	{ id = Enum.NormalId.Bottom, normal = Vector3.new(0, -1, 0), axes = { "X", "Z" } },
}

local function pickSignFace(sign: BasePart, base: Model): Enum.NormalId
	local override = sign:GetAttribute("Face")
	if type(override) == "string" then
		local ok, face = pcall(function()
			return Enum.NormalId[override]
		end)
		if ok and face then
			return face
		end
	end

	local outward = sign.Position - base:GetPivot().Position
	outward = Vector3.new(outward.X, 0, outward.Z)
	if outward.Magnitude < 0.1 then
		outward = sign.CFrame.LookVector
	end
	outward = outward.Unit

	local bestFace, bestScore = B.SignFace, -math.huge
	for _, info in ipairs(FACE_INFO) do
		local area = sign.Size[info.axes[1]] * sign.Size[info.axes[2]]
		local worldNormal = sign.CFrame:VectorToWorldSpace(info.normal)
		local alignment = worldNormal:Dot(outward)
		local penalty = (info.id == Enum.NormalId.Top or info.id == Enum.NormalId.Bottom) and 0.35 or 1
		local score = area * (0.35 + 0.65 * alignment) * penalty
		if score > bestScore then
			bestFace, bestScore = info.id, score
		end
	end
	return bestFace
end

local function ensureSign(base: Model)
	local sign = base:FindFirstChild(B.SignPartName)
	if not sign or not sign:IsA("BasePart") then
		return nil
	end

	local gui = sign:FindFirstChild(B.NameGuiName)
	if not gui then
		gui = Instance.new("SurfaceGui")
		gui.Name = B.NameGuiName
		gui.Face = pickSignFace(sign, base)
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.MaxDistance = 250
		gui.Parent = sign

		local label = Instance.new("TextLabel")
		label.Name = "OwnerLabel"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.Text = ""
		label.Parent = gui

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(40, 28, 14)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label
	end

	return gui
end

local function applyOwnerToSign(base: Model, ownerName: string?)
	local gui = ensureSign(base)
	if not gui then
		return
	end
	local label = gui:FindFirstChild("OwnerLabel")
	if label then
		label.Text = ownerName and (ownerName .. "'s Base") or ""
	end
end

local groupsReady = false
local nextGroupIndex = 0

local function ensureCollisionGroups()
	if groupsReady then
		return
	end
	groupsReady = true

	for i = 1, B.MaxDoorGroups do
		local name = B.DoorCollisionGroupPrefix .. i
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(name, name, false)
		end)
	end
end

local function groupNameFor(base: Model): string?
	local existing = base:GetAttribute("DoorGroup")
	if type(existing) == "string" and existing ~= "" then
		return existing
	end

	nextGroupIndex += 1
	if nextGroupIndex > B.MaxDoorGroups then
		warn(("[BaseService] 기지가 %d개를 넘어 문 통과 그룹이 부족합니다. "
			.. "GameConfig.Base.MaxDoorGroups 를 확인하세요."):format(B.MaxDoorGroups))
		return nil
	end

	local name = B.DoorCollisionGroupPrefix .. nextGroupIndex
	base:SetAttribute("DoorGroup", name)
	return name
end

local function applyGroupToCharacter(player: Player, groupName: string?)
	local char = player.Character
	if not char then
		return
	end
	local target = groupName or "Default"
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				part.CollisionGroup = target
			end)
		end
	end
end

function BaseService.applyDoorAccess(player: Player)
	local base = BaseService.getBase(player)
	if not base then
		applyGroupToCharacter(player, nil)
		return
	end
	applyGroupToCharacter(player, base:GetAttribute("DoorGroup"))
end

local function getDoorParts(base: Model): { BasePart }
	local door = base:FindFirstChild(B.DoorName)
	if not door then
		return {}
	end
	if door:IsA("BasePart") then
		return { door }
	end
	local parts = {}
	for _, d in ipairs(door:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

function BaseService.isDoorLocked(base: Model): boolean
	return base:GetAttribute(B.LockedAttribute) == true
end

function BaseService.setDoorLocked(base: Model, locked: boolean, force: boolean?)
	if not force and BaseService.isDoorLocked(base) == locked then
		return
	end
	base:SetAttribute(B.LockedAttribute, locked)

	base:SetAttribute("LockedAt", locked and os.clock() or nil)
	base:SetAttribute("UnlockAt", locked and (Workspace:GetServerTimeNow() + BaseService.getDoorInterval(base)) or nil)

	local groupName = base:GetAttribute("DoorGroup")

		for _, part in ipairs(getDoorParts(base)) do
		if groupName then
			pcall(function()
				part.CollisionGroup = groupName
			end)
		end

		local original = part:GetAttribute("OriginalTransparency")
		if original == nil then
			original = part.Transparency
			part:SetAttribute("OriginalTransparency", original)
		end

		part.CanCollide = locked
		-- 열린 문은 광선도 통과시킨다.
		-- (안 그러면 문이 열려 있는데도 "막혀 있다"고 판정된다)
		part.CanQuery = locked

		if locked then
			part.Transparency = original
		else
			part.Transparency = 1
		end
	end

	--[[
		문이 닫히는 순간 그 안에 서 있던 사람은 물리엔진이 밀어낸다.

		본인이 한 게 아닌데 위치가 확 튀므로 안티치트가 순간이동으로 본다.
		문 근처 사람에게 잠깐 이동 검사 면제를 준다.
	]]
	local doorParts = getDoorParts(base)
	if #doorParts > 0 then
		local center = doorParts[1].Position
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - center).Magnitude <= 24 then
				AntiCheatService.grantMotionGrace(player, 2)
			end
		end
	end

	BaseService.DoorLockChanged:Fire(base, locked)

	local owner = BaseService.getOwner(base)
	if owner then
		NetServer.fire(owner, "LockState", {
			locked = locked,
			baseName = base.Name,
		})
	end
end

function BaseService.getDoorInterval(base: Model): number
	local ownerId = BaseService.getOwnerId(base)
	local rebirths = 0
	if ownerId ~= 0 then
		local owner = Players:GetPlayerByUserId(ownerId)
		if owner then
			local profile = DataService.get(owner)
			rebirths = profile and (profile.data.rebirths or 0) or 0
		end
	end
	return B.DoorOpenInterval + rebirths * B.DoorIntervalPerRebirth
end

--[[
	친구 여부는 웹 요청이라 매번 물어보면 느리다.
	잠깐 캐시해 두고 쓴다.
]]
local friendCache = {}

local function isFriendCached(player: Player, ownerId: number): boolean
	local key = player.UserId .. "_" .. ownerId
	local hit = friendCache[key]
	if hit and os.clock() - hit.at < 60 then
		return hit.value
	end

	local ok, isFriend = pcall(function()
		return player:IsFriendsWith(ownerId)
	end)
	local value = ok and isFriend or false
	friendCache[key] = { value = value, at = os.clock() }
	return value
end

function BaseService.canEnter(player: Player, base: Model): boolean
	local ownerId = BaseService.getOwnerId(base)
	if ownerId == 0 then
		return true
	end
	if ownerId == player.UserId then
		return true
	end
	if base:GetAttribute(B.FriendAllowAttribute) == true then
		return isFriendCached(player, ownerId)
	end
	return false
end

function BaseService.getInterior(base: Model): (CFrame?, Vector3?)
	local explicit = base:FindFirstChild("Interior")
	if explicit and explicit:IsA("BasePart") then
		return explicit.CFrame, explicit.Size
	end

	local minV, maxV
	for i = 1, B.SlotCount do
		local handle = BaseService.getHandle(base, i)
		if handle then
			local p = handle.Position
			minV = minV and Vector3.new(math.min(minV.X, p.X), math.min(minV.Y, p.Y), math.min(minV.Z, p.Z)) or p
			maxV = maxV and Vector3.new(math.max(maxV.X, p.X), math.max(maxV.Y, p.Y), math.max(maxV.Z, p.Z)) or p
		end
	end
	if not minV then
		return nil, nil
	end

	local center = (minV + maxV) / 2
	local size = (maxV - minV) + Vector3.new(10, 16, 10)
	return CFrame.new(center + Vector3.new(0, 3, 0)), size
end

function BaseService.isInsideInterior(base: Model, position: Vector3): boolean
	local cf, size = BaseService.getInterior(base)
	if not cf then
		return false
	end
	local local_ = cf:PointToObjectSpace(position)
	local half = size / 2
	return math.abs(local_.X) <= half.X
		and math.abs(local_.Y) <= half.Y
		and math.abs(local_.Z) <= half.Z
end

function BaseService.getEjectPosition(base: Model): Vector3
	local cf, size = BaseService.getInterior(base)
	if not cf then
		return base:GetPivot().Position + Vector3.new(0, 5, 20)
	end
	return cf.Position + cf.LookVector * (size.Z / 2 + 12) + Vector3.new(0, 3, 0)
end

local function resolveLockParts(base: Model): (BasePart?, { BasePart })
	local node = base:FindFirstChild(B.LockPartName)
	if not node then
		return nil, {}
	end

	if node:IsA("BasePart") then
		return node, { node }
	end

	if node:IsA("Model") then
		local parts, best, bestVolume = {}, nil, -1
		for _, part in ipairs(node:GetDescendants()) do
			if part:IsA("BasePart") then
				table.insert(parts, part)
				local volume = part.Size.X * part.Size.Y * part.Size.Z
				if volume > bestVolume then
					best, bestVolume = part, volume
				end
			end
		end
		return (node.PrimaryPart or best), parts
	end

	return nil, {}
end

local function setupLockPart(base: Model)
	local lockPart, touchParts = resolveLockParts(base)
	if not lockPart then
		return
	end

		local gui = lockPart:FindFirstChild("LockGui")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "LockGui"
		gui.Parent = lockPart
	end

		gui.Size = UDim2.fromOffset(150, 54)
	gui.SizeOffset = Vector2.new(0, 2)
	gui.StudsOffset = Vector3.zero
	gui.StudsOffsetWorldSpace = Vector3.zero
	gui.AlwaysOnTop = false
	gui.MaxDistance = 55
	gui.LightInfluence = 0

	local function ensureLabel(name: string, sizeScale: number, posScale: number, color: Color3, font: Enum.Font)
		local label = gui:FindFirstChild(name)
		if not label or not label:IsA("TextLabel") then
			label = Instance.new("TextLabel")
			label.Name = name
			label.Text = ""
			label.Parent = gui

			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2.5
			stroke.Color = Color3.fromRGB(30, 34, 46)
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			stroke.Parent = label
		end
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, sizeScale, 0)
		label.Position = UDim2.fromScale(0, posScale)
		label.Font = font
		label.TextScaled = true
		label.TextColor3 = color
		return label
	end

	ensureLabel("Label", 0.58, 0, Color3.fromRGB(245, 240, 90), Enum.Font.GothamBlack)
	ensureLabel("SubLabel", 0.40, 0.60, Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold)

	for _, part in ipairs(touchParts) do
		if not part.CanTouch then
			warn(("[BaseService] '%s' 의 LockPart(%s) 가 CanTouch = false 라 밟아도 반응하지 않습니다.")
				:format(base.Name, part.Name))
		end
	end

		local debounce = {}
	local function onStepped(hit: BasePart)
		local char = hit and hit.Parent
		local player = char and Players:GetPlayerFromCharacter(char)
		if not player then
			return
		end
		if debounce[player] and os.clock() - debounce[player] < 1 then
			return
		end
		debounce[player] = os.clock()

		if not BaseService.isOwner(player, base) then
			return
		end
		if BaseService.isDoorLocked(base) then
			return
		end

		BaseService.setDoorLocked(base, true)
		NetServer.fire(player, "Notify", {
			key = "lock_restored",
			kind = "success",
			icon = "icon_lock",
		})
	end

	for _, part in ipairs(touchParts) do
		part.Touched:Connect(onStepped)
	end
end

local function setupFriendPart(base: Model)
	local part = base:FindFirstChild(B.FriendPartName)
	if not part or not part:IsA("BasePart") then
		return
	end

	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "FriendPrompt"
		prompt.ActionText = "Toggle"
		prompt.ObjectText = "Allow Friends"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.Parent = part
	end

	prompt.Triggered:Connect(function(player)
		if not BaseService.isOwner(player, base) then
			return
		end
		if not NetServer.isNear(player, part.Position, prompt.MaxActivationDistance + 4) then
			return
		end

		local newValue = not (base:GetAttribute(B.FriendAllowAttribute) == true)
		base:SetAttribute(B.FriendAllowAttribute, newValue)

		-- 프롬프트가 색을 바꿔 달 수 있도록 다시 띄운다
		prompt.Enabled = false
		task.defer(function()
			if prompt.Parent then
				prompt.Enabled = true
			end
		end)

		NetServer.fire(player, "Notify", {
			key = newValue and "friend_allowed_on" or "friend_allowed_off",
			kind = "info",
		})
	end)
end

local function clearBase(base: Model)
	base:SetAttribute(B.OwnerAttribute, 0)
	base:SetAttribute(B.OwnerNameAttribute, "")
	base:SetAttribute(B.FriendAllowAttribute, false)
	applyOwnerToSign(base, nil)
	BaseService.setDoorLocked(base, false, true)

	for i = 1, B.SlotCount do
		local model = BaseService.getSlotModel(base, i)
		if model then
			model:Destroy()
		end
	end
end

function BaseService.assign(player: Player): Model?
	local existing = BaseService.getBase(player)
	if existing then
		return existing
	end

	local free = {}
	for _, base in ipairs(BaseService.allBases()) do
		if BaseService.getOwnerId(base) == 0 then
			table.insert(free, base)
		end
	end

	if #free == 0 then
		local total = #BaseService.allBases()
		if total == 0 then
			warn(("[BaseService] %s 에게 배정할 기지가 없습니다 — 인식된 기지가 0개입니다.")
				:format(player.Name))
			warn("[BaseService] 아래 validate 결과를 확인하세요:")
			BaseService.validate()
		else
			warn(("[BaseService] %s 에게 배정할 빈 기지가 없습니다 (전체 %d개 모두 사용 중).")
				:format(player.Name, total))
		end
		NetServer.fire(player, "Notify", { key = "base_full", kind = "error" })
		return nil
	end

	local base = free[Random.new():NextInteger(1, #free)]
	base:SetAttribute(B.OwnerAttribute, player.UserId)
	base:SetAttribute(B.OwnerNameAttribute, player.DisplayName ~= "" and player.DisplayName or player.Name)
	base:SetAttribute(B.FriendAllowAttribute, false)
	ownerToBase[player.UserId] = base

	applyOwnerToSign(base, base:GetAttribute(B.OwnerNameAttribute))

	groupNameFor(base)
	BaseService.applyDoorAccess(player)

		BaseService.setDoorLocked(base, true, true)

	NetServer.fire(player, "BaseAssigned", { baseName = base.Name })
	BaseService.BaseAssigned:Fire(player, base)
	return base
end

function BaseService.release(player: Player)
	local base = ownerToBase[player.UserId]
	ownerToBase[player.UserId] = nil

	applyGroupToCharacter(player, nil)

	if not base or not base.Parent then
		return
	end
	BaseService.BaseReleased:Fire(player, base)
	clearBase(base)
end

local function doorCycleLoop()
	while true do
		task.wait(1)

		for _, base in ipairs(BaseService.allBases()) do
			if BaseService.isDoorLocked(base) and BaseService.getOwnerId(base) ~= 0 then
				local lockedAt = base:GetAttribute("LockedAt")
				if type(lockedAt) == "number" then
					local interval = BaseService.getDoorInterval(base)
					if os.clock() - lockedAt >= interval then
						-- 알림은 띄우지 않는다. 문이 보이게 되고 LockPart 표지가
						-- "기지 잠금" 으로 바뀌므로 그것으로 충분하다.
						BaseService.setDoorLocked(base, false)
					end
				end
			end
		end
	end
end

--[[
	지금 이 사람이 통과할 수 있어야 하는 문은 어디인가.

	캐릭터는 콜리전 그룹을 하나만 가질 수 있으므로, 자기 기지와
	"친구 허용" 기지를 동시에 통과할 수는 없다.
	그래서 허용된 남의 기지 문 가까이에 있으면 그쪽 그룹으로 잠시 바꾸고,
	멀어지면 자기 기지 그룹으로 돌아온다.
]]
local function resolveActiveBase(player: Player): Model?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local ownBase = BaseService.getBase(player)

	if not root then
		return ownBase
	end

	local best, bestDistance = nil, 18
	for _, base in ipairs(BaseService.allBases()) do
		if base ~= ownBase and BaseService.getOwnerId(base) ~= 0 then
			local door = base:FindFirstChild(B.DoorName)
			local doorPos
			if door and door:IsA("BasePart") then
				doorPos = door.Position
			elseif door and door:IsA("Model") then
				doorPos = door:GetPivot().Position
			end

			if doorPos then
				local distance = (root.Position - doorPos).Magnitude
				if distance < bestDistance and BaseService.canEnter(player, base) then
					best, bestDistance = base, distance
				end
			end
		end
	end

	return best or ownBase
end

local function enforceDoorAccessLoop()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local base = resolveActiveBase(player)
			local expected = base and base:GetAttribute("DoorGroup") or "Default"
			local char = player.Character
			if char then
				for _, part in ipairs(char:GetDescendants()) do
					if part:IsA("BasePart") and part.CollisionGroup ~= expected then
						pcall(function()
							part.CollisionGroup = expected
						end)
					end
				end
			end
		end
	end
end

function BaseService.spawnAtBase(player: Player): boolean
	local target: BasePart? = nil

	local base = BaseService.getBase(player)
	if base then
		local part = base:FindFirstChild(B.SpawnPartName)
		if part and part:IsA("BasePart") then
			target = part
		end
	end

	if not target then
		local shared = Workspace:FindFirstChild(B.SpawnPartName)
		if shared and shared:IsA("BasePart") then
			target = shared
		end
	end

	if not target then
		return false
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	AntiCheatService.grantImmunity(player, 3, "SpawnPart 스폰")
	root.CFrame = target.CFrame * CFrame.new(0, target.Size.Y / 2 + 3.5, 0)
	return true
end

function BaseService.validate(): number
	local folder = BaseService.getFolder()

	local models = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			table.insert(models, child)
		end
	end

	if #models == 0 then
		warn("[BaseService] Workspace." .. B.BasesFolderName .. " 안에 Model 이 하나도 없습니다.")
		warn("[BaseService] 기지 Model 을 이 폴더 안에 넣어 주세요.")
		return 0
	end

	local valid = 0

	for _, model in ipairs(models) do
		local problems = {}
		local notes = {}

		local slotFolder = model:FindFirstChild(B.SlotFolderName)
		if not slotFolder then
			local guess = nil
			for _, child in ipairs(model:GetChildren()) do
				if child:IsA("Folder") then
					guess = child.Name
					break
				end
			end
			table.insert(problems, ("'%s' 폴더가 없습니다%s")
				:format(B.SlotFolderName, guess and (" (지금 있는 폴더: '" .. guess .. "')") or ""))
		else
			--[[
				1층 슬롯은 반드시 있어야 하고, 2층 슬롯은 있으면 좋다.
				2층을 아직 안 만든 맵에서 9~16번이 "없음" 으로 잔뜩 뜨면
				진짜 문제가 묻힌다.
			]]
			local required = B.GroundSlotCount or B.SlotCount
			local upstairs = 0
			for i = required + 1, B.SlotCount do
				local sub = slotFolder:FindFirstChild(tostring(i))
				local handle = sub and sub:FindFirstChild(B.HandleName)
				if handle and handle:IsA("BasePart") then
					upstairs += 1
				end
			end
			if upstairs > 0 and upstairs < B.SlotCount - required then
				table.insert(notes, ("2층 슬롯 %d/%d개만 준비되어 있습니다")
					:format(upstairs, B.SlotCount - required))
			end

			local ok, missing = 0, {}
			for i = 1, required do
				local sub = slotFolder:FindFirstChild(tostring(i))
				if not sub then
					table.insert(missing, tostring(i))
				else
					local handle = sub:FindFirstChild(B.HandleName)
					if not handle then
						table.insert(missing, i .. "(Handle 없음)")
					elseif not handle:IsA("BasePart") then
						table.insert(missing, i .. "(Handle 이 파트가 아님)")
					else
						ok += 1
					end
				end
			end

			if ok == 0 then
				table.insert(problems, ("'%s' 안에 쓸 수 있는 슬롯이 없습니다. "):format(B.SlotFolderName)
					.. ("%s > 1 > %s (파트) 구조가 필요합니다."):format(B.SlotFolderName, B.HandleName))
			elseif #missing > 0 then
				table.insert(notes, ("1층 슬롯 %d/%d개 사용 가능 (없음: %s)")
					:format(ok, required, table.concat(missing, ", ")))
			end
		end

		local optional = {
			{ B.SignPartName, "소유자 간판(SurfaceGui)이 만들어지지 않습니다" },
			{ B.LockPartName, "기지 잠금 표지와 잠금 기능을 쓸 수 없습니다" },
			{ B.FriendPartName, "친구 허용 토글을 쓸 수 없습니다" },
			{ B.DoorName, "문 잠금/노클립 감지가 동작하지 않습니다" },
			{ B.SpawnPartName, "이 기지에서 스폰하지 않습니다 (기본 스폰 사용)" },
		}
		for _, entry in ipairs(optional) do
			if not model:FindFirstChild(entry[1]) then
				table.insert(notes, ("'%s' 없음 → %s"):format(entry[1], entry[2]))
			end
		end

		if #problems == 0 then
			valid += 1
			if #notes > 0 then
				warn(("[BaseService] '%s' — 아래 파트가 없어 해당 기능이 빠집니다:"):format(model.Name))
				for _, note in ipairs(notes) do
					warn(("    · %s"):format(note))
				end
			end
		else
			warn(("[BaseService] ✗ '%s' 는 기지로 인식되지 않습니다:"):format(model.Name))
			for _, problem in ipairs(problems) do
				warn(("    · %s"):format(problem))
			end
			for _, note in ipairs(notes) do
				warn(("    · %s"):format(note))
			end
			warn("    필요한 구조:")
			warn(("      %s (Model)"):format(model.Name))
			warn(("       └ %s (Folder)"):format(B.SlotFolderName))
			warn(("          └ 1 (Folder)  └ %s (Part)"):format(B.HandleName))
			warn("          └ 2 ~ 8 도 동일")
		end
	end

	return valid
end

function BaseService.start()
	ensureCollisionGroups()
	local folder = BaseService.getFolder()

	local function setupBase(base: Model)
		if not base:IsA("Model") or not base:FindFirstChild(B.SlotFolderName) then
			return
		end
		if base:GetAttribute(B.OwnerAttribute) == nil then
			base:SetAttribute(B.OwnerAttribute, 0)
		end
		if base:GetAttribute(B.OwnerNameAttribute) == nil then
			base:SetAttribute(B.OwnerNameAttribute, "")
		end
		if base:GetAttribute(B.FriendAllowAttribute) == nil then
			base:SetAttribute(B.FriendAllowAttribute, false)
		end
		ensureSign(base)
		setupLockPart(base)
		setupFriendPart(base)
	end

	for _, base in ipairs(folder:GetChildren()) do
		setupBase(base)
	end
	folder.ChildAdded:Connect(function(child)
		task.defer(setupBase, child)
	end)

	Players.PlayerRemoving:Connect(function(player)
		BaseService.release(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			BaseService.applyDoorAccess(player)
		end)
	end)

	task.spawn(doorCycleLoop)
	task.spawn(enforceDoorAccessLoop)

	BaseService.validate()
end

return BaseService

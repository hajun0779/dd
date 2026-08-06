--!nonstrict

--[[
	새 LocalScript로 StarterPlayerScripts에 넣는다.

	2층이 열리면 길을 그려 준다.

	  · 막고 있던 파트 위에 "여기로 올라가세요" 표지
	  · 내 캐릭터에서 그 파트까지 이어지는 빛줄기
	  · 실제로 올라가면 환영 카드

	빛줄기는 잠깐만 띄운다. 계속 붙어 있으면 길잡이가 아니라 방해가 된다.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(Shared.UI.UIBuilder)
local Theme = require(Shared.UI.Theme)
local Atlas = require(Shared.UI.Atlas)
local FloorConfig = require(Shared.Config.FloorConfig)
local Localization = require(Shared.Locale.Localization)
local NetClient = require(Shared.Net.NetClient)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local clientRoot = script.Parent:WaitForChild("Client")
local NotifyController = require(clientRoot.Controllers.NotifyController)

local G = FloorConfig.Guide

local screen: ScreenGui
local welcomeCard: Frame
local welcomeTitle: TextLabel
local welcomeBody: TextLabel

local guide = nil
local guideToken = 0

--------------------------------------------------------------------------------
-- 길잡이
--------------------------------------------------------------------------------

local function clearGuide()
	guideToken += 1
	if not guide then
		return
	end
	for _, instance in ipairs(guide.instances) do
		if instance and instance.Parent then
			instance:Destroy()
		end
	end
	if guide.connection then
		guide.connection:Disconnect()
	end
	guide = nil
end

local function makeBillboard(part: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RadFloorGuide"
	billboard.Size = UDim2.fromOffset(280, 92)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, G.BillboardHeight, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 400
	billboard.Parent = part

	local panel = Atlas.new("ImageLabel", "panel_yellow", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		Parent = billboard,
	})

	Atlas.icon("icon_arrow_u", {
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.fromOffset(14, 12),
		color = Theme.Color.Dark,
		ZIndex = panel.ZIndex + 1,
		Parent = panel,
	})

	UI.text({
		Name = "Title",
		Size = UDim2.new(1, -60, 0, 34),
		Position = UDim2.fromOffset(54, 10),
		localeKey = "floor_guide_title",
		font = Theme.Font.Heading,
		textColor = Theme.Color.Dark,
		stroke = false,
		maxTextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = panel.ZIndex + 1,
		Parent = panel,
	})

	UI.text({
		Name = "Body",
		Size = UDim2.new(1, -30, 0, 32),
		Position = UDim2.fromOffset(16, 46),
		localeKey = "floor_guide_body",
		font = Theme.Font.Body,
		textColor = Theme.Color.Dark,
		stroke = false,
		maxTextSize = 19,
		ZIndex = panel.ZIndex + 1,
		Parent = panel,
	})

	--[[
		위아래로 천천히 까딱인다.
		가만히 있는 표지는 맵에 원래 있던 간판처럼 보여서 눈에 안 들어온다.
	]]
	local up = TweenService:Create(
		billboard,
		TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ StudsOffsetWorldSpace = Vector3.new(0, G.BillboardHeight + 1.2, 0) }
	)
	up:Play()

	return billboard
end

--[[
	나와 목적지를 잇는 빛줄기.

	캐릭터 쪽 부착점은 캐릭터가 죽으면 같이 사라진다.
	그래서 새 캐릭터가 생길 때마다 다시 만든다.
]]
local function makeBeam(part: BasePart)
	local target = Instance.new("Attachment")
	target.Name = "RadFloorTarget"
	target.Position = Vector3.new(0, part.Size.Y / 2 + 1, 0)
	target.Parent = part

	local beam = Instance.new("Beam")
	beam.Name = "RadFloorBeam"
	beam.Attachment1 = target
	beam.Width0 = G.BeamWidth
	beam.Width1 = G.BeamWidth * 0.5
	beam.Color = ColorSequence.new(G.Color)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Texture = G.BeamTexture
	beam.TextureLength = 6
	beam.TextureSpeed = 2.2
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.75),
		NumberSequenceKeypoint.new(0.5, 0.25),
		NumberSequenceKeypoint.new(1, 0.75),
	})
	beam.FaceCamera = true
	beam.Parent = part

	local function attachToCharacter(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root or not beam.Parent then
			return
		end
		local existing = root:FindFirstChild("RadFloorSource")
		if existing then
			existing:Destroy()
		end
		local source = Instance.new("Attachment")
		source.Name = "RadFloorSource"
		source.Position = Vector3.new(0, 1.5, 0)
		source.Parent = root
		beam.Attachment0 = source
	end

	if player.Character then
		task.spawn(attachToCharacter, player.Character)
	end
	local connection = player.CharacterAdded:Connect(function(character)
		task.spawn(attachToCharacter, character)
	end)

	return beam, target, connection
end

local function showGuide(part: BasePart)
	clearGuide()
	if not part or not part.Parent then
		return
	end

	guideToken += 1
	local generation = guideToken

	local billboard = makeBillboard(part)
	local beam, target, connection = makeBeam(part)

	guide = {
		instances = { billboard, beam, target },
		connection = connection,
	}

	task.delay(G.Seconds, function()
		if guideToken == generation then
			clearGuide()
		end
	end)
end

--------------------------------------------------------------------------------
-- 환영
--------------------------------------------------------------------------------

local function welcome(extraSlots: number, totalSlots: number)
	if not welcomeCard then
		return
	end

	Localization.bind(welcomeTitle, "Text", "floor_welcome_title")
	Localization.bind(welcomeBody, "Text", "floor_welcome_body", { extraSlots, totalSlots })

	welcomeCard.Visible = true
	welcomeTitle.TextTransparency = 0
	welcomeBody.TextTransparency = 0

	local scale = welcomeCard:FindFirstChildOfClass("UIScale") or UI.scale(1, welcomeCard)
	scale.Scale = 0.6
	TweenService:Create(scale, Theme.Tween.Bounce, { Scale = 1 }):Play()
	UI.playSound(Theme.Sound.Success, 0.6)

	task.delay(5, function()
		if not welcomeCard or not welcomeCard.Visible then
			return
		end
		local out = TweenService:Create(welcomeTitle, Theme.Tween.Slow, { TextTransparency = 1 })
		TweenService:Create(welcomeBody, Theme.Tween.Slow, { TextTransparency = 1 }):Play()
		out.Completed:Once(function()
			if welcomeCard then
				welcomeCard.Visible = false
			end
		end)
		out:Play()
	end)

	clearGuide()
end

--------------------------------------------------------------------------------
-- 시작
--------------------------------------------------------------------------------

local function buildWelcome(parent: Frame)
	welcomeCard = Atlas.new("ImageLabel", "panel_yellow", {
		Name = "FloorWelcome",
		Size = UDim2.fromOffset(620, 150),
		Position = UDim2.fromScale(0.5, 0.32),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 30,
		Parent = parent,
	})

	Atlas.icon("icon_home", {
		Size = UDim2.fromOffset(58, 58),
		Position = UDim2.fromOffset(30, 46),
		color = Theme.Color.Dark,
		ZIndex = welcomeCard.ZIndex + 1,
		Parent = welcomeCard,
	})

	welcomeTitle = UI.text({
		Name = "Title",
		Size = UDim2.new(1, -120, 0, 54),
		Position = UDim2.fromOffset(104, 24),
		text = "",
		font = Theme.Font.Title,
		textColor = Theme.Color.Dark,
		stroke = false,
		maxTextSize = 42,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = welcomeCard.ZIndex + 1,
		Parent = welcomeCard,
	})

	welcomeBody = UI.text({
		Name = "Body",
		Size = UDim2.new(1, -130, 0, 44),
		Position = UDim2.fromOffset(104, 78),
		text = "",
		font = Theme.Font.Body,
		textColor = Theme.Color.Dark,
		stroke = false,
		maxTextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		ZIndex = welcomeCard.ZIndex + 1,
		Parent = welcomeCard,
	})
end

local function onSync(data)
	if type(data) ~= "table" or not data.ok then
		return
	end

	if data.welcome then
		welcome(data.extraSlots or 8, data.totalSlots or 16)
		return
	end

	if not data.unlocked then
		clearGuide()
		return
	end

	--[[
		막 열렸거나, 열렸는데 아직 한 번도 안 올라가 본 사람에게만 그린다.
		이미 올라가 본 사람에게 매번 띄우면 접속할 때마다 화살표가 뜬다.
	]]
	if data.part and (data.justUnlocked or not data.welcomed) then
		showGuide(data.part)
	end

	if data.justUnlocked then
		NotifyController.toast({
			key = "floor_unlocked_toast",
			args = { data.extraSlots or 8 },
			kind = "rare",
			icon = "icon_home",
			duration = 8,
		})
	end
end

local function start()
	screen = UI.create("ScreenGui", {
		Name = "RadFloor",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = Theme.Z.Alert,
		Parent = playerGui,
	})

	local root = UI.create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = screen,
	})
	local scaleObj = UI.responsiveScale(screen)
	scaleObj.Parent = root

	buildWelcome(root)

	NetClient.on("FloorSync", onSync)

	task.spawn(function()
		for _ = 1, 5 do
			local result = NetClient.invoke("FloorGetState", 8)
			if type(result) == "table" and result.ok then
				onSync(result)
				return
			end
			task.wait(3)
		end
	end)
end

local ok, err = pcall(start)
if not ok then
	warn("[FloorClient] 2층 화면 시작 실패: " .. tostring(err))
end

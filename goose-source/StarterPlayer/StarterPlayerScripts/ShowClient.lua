--!nonstrict

--[[
	새 LocalScript로 StarterPlayerScripts에 넣는다.

	연출 중 "내 주변" 을 맡는다. 맵 한가운데에 놓이는 것(운석·균열·조명·오로라
	커튼)은 서버가 만들고, 여기서는 카메라를 따라다니는 것만 만든다.

	전부 3D 다. 화면에 사각형을 덧그리지 않는다.

	처음에는 꽃잎과 금화를 화면 위 GUI 로 그렸는데, 그러면 원근도 없고 건물 뒤로
	가려지지도 않는다. 고개를 돌려도 같은 자리에 붙어 있어서 월드에서 일어나는
	일이 아니라 화면에 씌운 필터로 보인다.

	그래서 진짜 파티클을 쓴다. 카메라 위/아래에 보이지 않는 방출판을 하나 두고
	그게 카메라를 따라다닌다. 이 방식이면

	  · 가까운 꽃잎은 크고 빠르게, 먼 꽃잎은 작고 느리게 지나간다 (원근)
	  · 건물과 거위 뒤로 가려진다 (깊이)
	  · 고개를 돌리면 다른 각도에서 보인다

	방출판은 Workspace.CurrentCamera 밑에 둔다. 카메라 밑에 있는 것은
	이 화면에만 존재하고 서버로 복제되지 않는다. 사람이 몇이든 비용이 같다.
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(Shared.UI.UIBuilder)
local Theme = require(Shared.UI.Theme)
local ShowConfig = require(Shared.Config.ShowConfig)
local ParticleAssets = require(Shared.UI.ParticleAssets)
local Localization = require(Shared.Locale.Localization)
local NetClient = require(Shared.Net.NetClient)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local clientRoot = script.Parent:WaitForChild("Client")
local ClientState = require(clientRoot.ClientState)

local CAMERA_BIND = "RadShowCamera"
local RIG_NAME = "RadShowRig"

local titleCard: Frame
local titleLabel: TextLabel

local rng = Random.new()
local running = nil

local rig = nil
local rigConnection: RBXScriptConnection? = nil
local boltThread = 0
local cameraBound = false

local bloom: BloomEffect? = nil
local grade: ColorCorrectionEffect? = nil
local cycleThread = 0

--------------------------------------------------------------------------------
-- 잔손질
--------------------------------------------------------------------------------

local function colorsOf(spec): { Color3 }
	if type(spec.Colors) == "table" and #spec.Colors > 0 then
		return spec.Colors
	end
	return { Color3.new(1, 1, 1) }
end

--------------------------------------------------------------------------------
-- 내 주변 3D 방출기
--------------------------------------------------------------------------------

local function clearRig()
	boltThread += 1

	if rigConnection then
		rigConnection:Disconnect()
		rigConnection = nil
	end
	if rig and rig.plate then
		rig.plate:Destroy()
	end
	rig = nil

	-- 번개처럼 따로 만들어 둔 것도 치운다
	local camera = Workspace.CurrentCamera
	if camera then
		for _, child in ipairs(camera:GetChildren()) do
			if child.Name == RIG_NAME or child.Name == "RadShowBolt" then
				child:Destroy()
			end
		end
	end
end

--[[
	방출판.

	넓적한 판 하나에 방출기를 붙인다. 판 전체에서 뿌려지므로 시야가 고르게 찬다.
	점 하나에서 뿌리면 머리 위 한 곳에서 쏟아지는 분수처럼 보인다.
]]
local function buildEmitter(plate: BasePart, spec, color: Color3, share: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = ParticleAssets.get(spec.Texture)
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = spec.LightEmission
	emitter.LightInfluence = 1 - spec.LightEmission
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spec.Size * 0.6),
		NumberSequenceKeypoint.new(0.2, spec.Size),
		NumberSequenceKeypoint.new(1, spec.Size * 0.8),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, spec.Transparency),
		NumberSequenceKeypoint.new(0.85, spec.Transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rate = math.max(spec.Rate * share, 1)
	emitter.Lifetime = NumberRange.new(spec.Lifetime * 0.75, spec.Lifetime * 1.25)
	emitter.Speed = NumberRange.new(spec.Speed * 0.8, spec.Speed * 1.2)
	emitter.SpreadAngle = Vector2.new(spec.SpreadAngle, spec.SpreadAngle)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-spec.Spin, spec.Spin)
	emitter.Drag = spec.Drag
	emitter.EmissionDirection = spec.Kind == "fall" and Enum.NormalId.Bottom or Enum.NormalId.Top

	--[[
		빗줄기와 유성은 늘려서 속도 방향으로 눕혀야 한다.
		안 그러면 아무리 빨라도 동그란 점이 떨어질 뿐이다.
	]]
	if spec.Squash and spec.Squash > 0 then
		emitter.Squash = NumberSequence.new(spec.Squash)
		emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	end

	emitter.Parent = plate
	return emitter
end

local function buildRig(spec)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local plate = Instance.new("Part")
	plate.Name = RIG_NAME
	plate.Size = Vector3.new(spec.Spread, 1, spec.Spread)
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.CastShadow = false
	plate.Transparency = 1
	plate.Locked = true
	plate.Parent = camera

	local palette = colorsOf(spec)
	local emitters = {}
	for _, color in ipairs(palette) do
		table.insert(emitters, buildEmitter(plate, spec, color, 1 / #palette))
	end

	rig = { plate = plate, emitters = emitters, spec = spec }

	local tilt = math.rad(tonumber(spec.Tilt) or 0)
	local wind = tonumber(spec.Wind) or 0

	rigConnection = RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		if not cam or not plate.Parent then
			return
		end
		-- 카메라가 통째로 바뀌는 경우가 있다 (사망, 시네마틱 등)
		if plate.Parent ~= cam then
			plate.Parent = cam
		end

		local now = Workspace:GetServerTimeNow()
		local base = cam.CFrame.Position + Vector3.new(0, spec.Height, 0)
		plate.CFrame = CFrame.new(base) * CFrame.Angles(tilt, now * 0.05, 0)

		--[[
			바람.

			방향이 아주 느리게 돌아야 눈보라가 살아 있는 것처럼 보인다.
			고정 방향이면 벽지 무늬가 흐르는 것처럼 보인다.
		]]
		if wind > 0 then
			local drift = Vector3.new(math.cos(now * 0.13) * wind, 0, math.sin(now * 0.11) * wind)
			for _, emitter in ipairs(emitters) do
				emitter.Acceleration = drift
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- 3D 번개
--------------------------------------------------------------------------------

--[[
	하늘에 실제 파트로 갈래를 세운다.

	화면을 하얗게 덮는 것과는 다르다. 갈래는 원근을 타고, 끝에 달린 빛이
	주변 지형을 실제로 밝힌다. 어느 쪽에서 쳤는지가 눈에 보인다.
]]
local function strike(spec)
	local camera = Workspace.CurrentCamera
	if not camera or ClientState.settings.lowGraphics then
		return
	end

	local origin = camera.CFrame.Position
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = tonumber(spec.Distance) or 240
	local ground = origin + Vector3.new(math.cos(angle) * distance, -30, math.sin(angle) * distance)
	local top = ground + Vector3.new(rng:NextNumber(-70, 70), tonumber(spec.Height) or 340, rng:NextNumber(-70, 70))

	local forks = math.clamp(math.floor(tonumber(spec.Forks) or 6), 2, 12)
	local thickness = tonumber(spec.Thickness) or 3
	local color = spec.Color or Color3.fromRGB(226, 238, 255)

	local segments = {}
	local previous = top

	for i = 1, forks do
		local t = i / forks
		local target = top:Lerp(ground, t)
			+ Vector3.new(rng:NextNumber(-34, 34), 0, rng:NextNumber(-34, 34)) * (1 - t)
		local delta = target - previous
		local length = delta.Magnitude

		if length > 0.5 then
			local segment = Instance.new("Part")
			segment.Name = "RadShowBolt"
			segment.Size = Vector3.new(thickness, thickness, length)
			segment.CFrame = CFrame.lookAt(previous + delta * 0.5, target)
			segment.Anchored = true
			segment.CanCollide = false
			segment.CanQuery = false
			segment.CanTouch = false
			segment.CastShadow = false
			segment.Locked = true
			segment.Material = Enum.Material.Neon
			segment.Color = color
			segment.Parent = camera
			table.insert(segments, segment)
		end
		previous = target
	end

	if #segments == 0 then
		return
	end

	local light = Instance.new("PointLight")
	light.Brightness = tonumber(spec.Brightness) or 8
	light.Range = 60
	light.Color = color
	light.Shadows = false
	light.Parent = segments[#segments]

	--[[
		여기서만 화면 밝기를 잠깐 올린다.

		이건 화면에 흰 판을 덮는 게 아니라, 렌더된 3D 장면의 노출을 올리는 것이다.
		번개가 세상을 밝히는 걸 흉내 내려면 이게 있어야 한다.
	]]
	local flashSeconds = tonumber(spec.FlashSeconds) or 0.28
	if grade and grade.Parent then
		grade.Brightness = 0.16
		TweenService:Create(grade, TweenInfo.new(flashSeconds, Enum.EasingStyle.Quint), { Brightness = 0 }):Play()
	end

	task.delay(flashSeconds * 0.4, function()
		for _, segment in ipairs(segments) do
			if segment.Parent then
				TweenService:Create(segment, TweenInfo.new(flashSeconds), { Transparency = 1 }):Play()
			end
		end
		if light.Parent then
			TweenService:Create(light, TweenInfo.new(flashSeconds), { Brightness = 0 }):Play()
		end
	end)

	task.delay(flashSeconds * 2 + 0.2, function()
		for _, segment in ipairs(segments) do
			segment:Destroy()
		end
	end)
end

local function lightningLoop(spec)
	boltThread += 1
	local generation = boltThread

	task.spawn(function()
		while boltThread == generation do
			task.wait(rng:NextNumber(tonumber(spec.MinGap) or 1.6, tonumber(spec.MaxGap) or 5.4))
			if boltThread ~= generation then
				return
			end
			local ok, err = pcall(strike, spec)
			if not ok then
				warn("[ShowClient] 번개 실패: " .. tostring(err))
				return
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- 화면 보정과 카메라
--------------------------------------------------------------------------------

local function ensureGrade()
	if not bloom or not bloom.Parent then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "RadShowBloom"
		bloom.Intensity = ShowConfig.BaseGrade.Bloom
		bloom.Size = ShowConfig.BaseGrade.BloomSize
		bloom.Threshold = ShowConfig.BaseGrade.BloomThreshold
		bloom.Parent = Lighting
	end
	if not grade or not grade.Parent then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "RadShowGrade"
		grade.Parent = Lighting
	end
end

local function applyGrade(spec, seconds: number)
	if ClientState.settings.lowGraphics then
		spec = ShowConfig.BaseGrade
	end
	ensureGrade()

	cycleThread += 1
	local generation = cycleThread

	TweenService:Create(bloom, TweenInfo.new(seconds), {
		Intensity = tonumber(spec.Bloom) or ShowConfig.BaseGrade.Bloom,
		Size = tonumber(spec.BloomSize) or ShowConfig.BaseGrade.BloomSize,
		Threshold = tonumber(spec.BloomThreshold) or ShowConfig.BaseGrade.BloomThreshold,
	}):Play()
	TweenService:Create(grade, TweenInfo.new(seconds), {
		Contrast = tonumber(spec.Contrast) or 0,
		Saturation = tonumber(spec.Saturation) or 0,
		Brightness = tonumber(spec.Brightness) or 0,
		TintColor = spec.Tint or Color3.new(1, 1, 1),
	}):Play()

	--[[
		디스코와 타코만 틴트가 계속 바뀐다.
		다른 연출까지 색을 돌리면 열 개가 다시 다 비슷해진다.
	]]
	if type(spec.Cycle) == "table" and #spec.Cycle > 0 then
		local step = 0
		local cycleSeconds = math.max(tonumber(spec.CycleSeconds) or 1.2, 0.2)
		task.spawn(function()
			while cycleThread == generation do
				step += 1
				local color = spec.Cycle[(step - 1) % #spec.Cycle + 1]
				if grade and grade.Parent then
					TweenService:Create(grade, TweenInfo.new(cycleSeconds, Enum.EasingStyle.Sine), {
						TintColor = color,
					}):Play()
				end
				task.wait(cycleSeconds)
			end
		end)
	end
end

--[[
	카메라.

	  Sway   연출 내내 아주 느리게 도는 기울기
	  Shake  낮게 계속 우는 진동 (대균열 전용)

	둘을 한 바인딩에서 같이 건다. 따로 걸면 서로의 CFrame 을 덮어쓴다.
]]
local function setCamera(sway: number, shake: number)
	if cameraBound then
		RunService:UnbindFromRenderStep(CAMERA_BIND)
		cameraBound = false
	end
	if ClientState.settings.lowGraphics or (sway <= 0 and shake <= 0) then
		return
	end

	cameraBound = true
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 2, function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local t = Workspace:GetServerTimeNow()
		local cf = camera.CFrame

		if shake > 0 then
			cf = cf * CFrame.new(
				rng:NextNumber(-shake, shake),
				rng:NextNumber(-shake, shake),
				rng:NextNumber(-shake, shake) * 0.4
			)
		end
		if sway > 0 then
			cf = cf * CFrame.Angles(
				math.rad(math.sin(t * 0.35) * sway * 0.5),
				math.rad(math.sin(t * 0.21) * sway * 0.4),
				math.rad(math.sin(t * 0.27) * sway)
			)
		end

		camera.CFrame = cf
	end)
end

--------------------------------------------------------------------------------
-- 알림 카드
--------------------------------------------------------------------------------

local function announce(show)
	if not titleCard then
		return
	end
	titleLabel.Text = Localization.t(show.LocaleKey)
	titleCard.Visible = true

	local scale = titleCard:FindFirstChildOfClass("UIScale") or UI.scale(1, titleCard)
	scale.Scale = 0.7
	titleLabel.TextTransparency = 1
	TweenService:Create(scale, Theme.Tween.Bounce, { Scale = 1 }):Play()
	TweenService:Create(titleLabel, Theme.Tween.Normal, { TextTransparency = 0 }):Play()

	task.delay(3.4, function()
		if not titleCard or titleLabel.Text ~= Localization.t(show.LocaleKey) then
			return
		end
		local out = TweenService:Create(titleLabel, Theme.Tween.Slow, { TextTransparency = 1 })
		out.Completed:Once(function()
			if titleCard then
				titleCard.Visible = false
			end
		end)
		out:Play()
	end)
end

--------------------------------------------------------------------------------
-- 켜고 끄기
--------------------------------------------------------------------------------

local function stopShow()
	running = nil
	clearRig()
	setCamera(0, 0)
	applyGrade(ShowConfig.BaseGrade, ShowConfig.FadeSeconds)
end

local function startShow(show)
	clearRig()
	running = show.Id

	applyGrade(show.Grade or ShowConfig.BaseGrade, ShowConfig.FadeSeconds)

	local camera = show.Camera or {}
	setCamera(tonumber(camera.Sway) or 0, tonumber(camera.Shake) or 0)

	if not ClientState.settings.lowGraphics then
		local spec = ShowConfig.localSpec(show)
		if spec then
			local ok, err = pcall(buildRig, spec)
			if not ok then
				warn("[ShowClient] 주변 연출 실패(" .. show.Id .. "): " .. tostring(err))
			end
			if type(spec.Lightning) == "table" then
				lightningLoop(spec.Lightning)
			end
		end
	end

	announce(show)
end

local function onSync(data)
	if type(data) ~= "table" then
		return
	end

	local show = ShowConfig.get(data.id)
	if not show then
		if running then
			stopShow()
		end
		return
	end
	if running == show.Id then
		return
	end
	startShow(show)
end

local function start()
	local screen = UI.create("ScreenGui", {
		Name = "RadShow",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = Theme.Z.Panel,
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

	--[[
		화면에 남는 유일한 2D 요소.

		연출 이름을 알리는 표지지 연출 자체가 아니다.
		3초 뒤 사라지고, 그 뒤로는 화면에 아무것도 없다.
	]]
	titleCard = UI.create("Frame", {
		Name = "TitleCard",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(720, 90),
		Position = UDim2.fromScale(0.5, 0.22),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	titleLabel = UI.text({
		Name = "Title",
		Size = UDim2.fromScale(1, 1),
		text = "",
		font = Theme.Font.Title,
		textColor = Theme.Color.TextInverse,
		strokeColor = Theme.Color.Dark,
		stroke = 4,
		maxTextSize = 52,
		ZIndex = 21,
		Parent = titleCard,
	})

	NetClient.on("ShowSync", onSync)

	--[[
		카메라가 갈리면 방출판도 같이 사라진다.
		죽었다 살아나면 다시 만들어 준다.
	]]
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if not running then
			return
		end
		local show = ShowConfig.get(running)
		if show then
			local current = running
			running = nil
			startShow(show)
			running = current
		end
	end)

	-- 저사양으로 바꾸면 주변 연출만 걷어낸다. 하늘은 서버가 정한 그대로 둔다.
	ClientState.SettingsChanged:Connect(function(settings)
		if settings.lowGraphics and running then
			clearRig()
			setCamera(0, 0)
			applyGrade(ShowConfig.BaseGrade, 1)
		end
	end)
end

local ok, err = pcall(start)
if not ok then
	warn("[ShowClient] 연출 화면 시작 실패: " .. tostring(err))
end

--!nonstrict

--[[
	새 LocalScript로 StarterPlayerScripts에 넣는다.

	연출의 "화면에 보이는 부분" 을 그린다. 맵에 놓이는 것(운석·균열·조명)은
	서버가 만들고, 여기서는 눈앞을 지나가는 것만 만든다.

	그리는 방법이 열 가지 다 다르다. 이게 이 파일의 전부다 —
	전부 같은 방식으로 그리면 색만 바뀐 같은 연출이 열 개 생긴다.

	  curtain    위에서 늘어진 띠가 좌우로 흐른다        (오로라)
	  lightning  불규칙한 간격으로 꺾인 선이 번쩍인다     (폭풍우)
	  streaks    대각선 빛줄기가 화면을 가로지른다        (유성우)
	  petals     꽃잎이 회전하며 흩날린다                 (벚꽃)
	  disco      화면 색이 순환하고 광선이 돈다           (디스코)
	  frost      가장자리부터 성에가 자란다               (혹한)
	  pulse      붉은 테두리가 심장처럼 뛴다              (균열)
	  coins      금화가 뒤집히며 떨어진다                 (황금비)
	  stars      별이 화면 중심을 기준으로 돈다           (성운)
	  confetti   색종이가 쏟아진다                        (타코)
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
local Localization = require(Shared.Locale.Localization)
local NetClient = require(Shared.Net.NetClient)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local clientRoot = script.Parent:WaitForChild("Client")
local ClientState = require(clientRoot.ClientState)

local SWAY_BIND = "RadShowSway"

local screen: ScreenGui
local canvas: Frame
local titleCard: Frame
local titleLabel: TextLabel

local rng = Random.new()
local running = nil
local stopRenderer = nil
local connections: { RBXScriptConnection } = {}
local threads = 0
local swayBound = false

local bloom: BloomEffect? = nil
local grade: ColorCorrectionEffect? = nil
local cycleThread = 0

--------------------------------------------------------------------------------
-- 잔손질
--------------------------------------------------------------------------------

local function frame(parent: Instance, props): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	for key, value in pairs(props or {}) do
		f[key] = value
	end
	f.Parent = parent
	return f
end

local function gradient(parent: Instance, transparency: NumberSequence, rotation: number?)
	local g = Instance.new("UIGradient")
	g.Transparency = transparency
	g.Rotation = rotation or 0
	g.Parent = parent
	return g
end

local function track(connection: RBXScriptConnection)
	table.insert(connections, connection)
	return connection
end

local function pick(list, fallback)
	if type(list) ~= "table" or #list == 0 then
		return fallback
	end
	return list[rng:NextInteger(1, #list)]
end

--[[
	일정 간격으로 무언가를 하나씩 만들어 내는 반복.

	쏟아지는 연출(꽃잎·금화·색종이·유성)이 전부 이걸 쓴다.
	연출이 바뀌면 generation 이 달라져서 이전 반복은 스스로 멈춘다.
]]
local function spawner(perSecond: number, make)
	threads += 1
	local generation = threads
	local interval = 1 / math.max(perSecond, 0.05)

	task.spawn(function()
		while threads == generation and canvas do
			local ok, err = pcall(make)
			if not ok then
				warn("[ShowClient] 연출 요소 생성 실패: " .. tostring(err))
				return
			end
			task.wait(interval)
		end
	end)

	return function()
		if threads == generation then
			threads += 1
		end
	end
end

local function viewport(): Vector2
	local camera = Workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

--------------------------------------------------------------------------------
-- 화면 연출
--------------------------------------------------------------------------------

local renderers = {}

--- 오로라. 위에서 늘어진 색 띠가 서로 다른 속도로 흐른다.
function renderers.curtain(spec)
	local bands = math.clamp(math.floor(tonumber(spec.Bands) or 6), 2, 14)
	local height = tonumber(spec.Height) or 0.6
	local alpha = tonumber(spec.Alpha) or 0.7
	local made = {}

	for i = 1, bands do
		local band = frame(canvas, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale((i - 0.5) / bands, -0.05),
			Size = UDim2.fromScale(1.6 / bands, height),
			BackgroundColor3 = pick(spec.Colors, Color3.fromRGB(120, 255, 200)),
			BackgroundTransparency = alpha,
			Rotation = rng:NextNumber(-6, 6),
			ZIndex = 2,
		})
		gradient(band, NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.55, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}), 90)
		table.insert(made, {
			gui = band,
			base = (i - 0.5) / bands,
			phase = rng:NextNumber(0, math.pi * 2),
			rate = rng:NextNumber(0.6, 1.5),
			width = rng:NextNumber(0.8, 1.6) / bands,
		})
	end

	local speed = tonumber(spec.Speed) or 0.12
	track(RunService.RenderStepped:Connect(function()
		local t = Workspace:GetServerTimeNow() * speed
		for _, entry in ipairs(made) do
			local wave = math.sin(t * entry.rate + entry.phase)
			entry.gui.Position = UDim2.fromScale(entry.base + wave * 0.08, -0.05 + wave * 0.02)
			entry.gui.Size = UDim2.fromScale(entry.width * (1 + wave * 0.25), height)
			entry.gui.BackgroundTransparency = alpha + wave * 0.12
		end
	end))
end

--- 폭풍우. 간격이 불규칙해야 놀란다.
function renderers.lightning(spec)
	local color = spec.Color or Color3.fromRGB(226, 238, 255)
	local forks = math.clamp(math.floor(tonumber(spec.Forks) or 4), 1, 8)

	threads += 1
	local generation = threads
	task.spawn(function()
		while threads == generation and canvas do
			task.wait(rng:NextNumber(tonumber(spec.MinGap) or 1.4, tonumber(spec.MaxGap) or 5.2))
			if threads ~= generation or not canvas then
				return
			end

			local flash = frame(canvas, {
				AnchorPoint = Vector2.new(0, 0),
				Position = UDim2.fromScale(0, 0),
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = color,
				BackgroundTransparency = 0.6,
				ZIndex = 3,
			})
			TweenService:Create(flash, TweenInfo.new(0.32, Enum.EasingStyle.Quint), {
				BackgroundTransparency = 1,
			}):Play()

			-- 꺾인 선을 위에서 아래로 이어 붙인다
			local size = viewport()
			local x = rng:NextNumber(0.15, 0.85) * size.X
			local y = 0
			local bolt = {}
			for _ = 1, forks do
				local nextX = x + rng:NextNumber(-90, 90)
				local nextY = y + size.Y / forks * rng:NextNumber(0.7, 1.3)
				local dx, dy = nextX - x, nextY - y
				local length = math.sqrt(dx * dx + dy * dy)

				local segment = frame(canvas, {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromOffset(x, y),
					Size = UDim2.fromOffset(length, rng:NextInteger(2, 5)),
					Rotation = math.deg(math.atan2(dy, dx)),
					BackgroundColor3 = color,
					BackgroundTransparency = 0.05,
					ZIndex = 4,
				})
				table.insert(bolt, segment)
				x, y = nextX, nextY
			end

			task.delay(0.09, function()
				for _, segment in ipairs(bolt) do
					if segment.Parent then
						TweenService:Create(segment, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
					end
				end
			end)
			task.delay(0.45, function()
				flash:Destroy()
				for _, segment in ipairs(bolt) do
					segment:Destroy()
				end
			end)
		end
	end)

	return function()
		if threads == generation then
			threads += 1
		end
	end
end

--- 유성우. 대각선으로 길게 지나간다.
function renderers.streaks(spec)
	local color = spec.Color or Color3.fromRGB(255, 208, 140)
	local angle = tonumber(spec.Angle) or 28

	return spawner(tonumber(spec.Rate) or 2, function()
		local size = viewport()
		local streak = frame(canvas, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(rng:NextNumber(-0.1, 0.9) * size.X, rng:NextNumber(-0.1, 0.5) * size.Y),
			Size = UDim2.fromOffset(0, rng:NextInteger(2, 4)),
			Rotation = angle + rng:NextNumber(-6, 6),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.1,
			ZIndex = 3,
		})
		gradient(streak, NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.85, 0.05),
			NumberSequenceKeypoint.new(1, 0),
		}))

		local reach = size.X * rng:NextNumber(0.5, 1.1)
		local travel = TweenService:Create(streak, TweenInfo.new(rng:NextNumber(0.5, 0.9), Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.fromOffset(reach, streak.Size.Y.Offset),
			Position = streak.Position + UDim2.fromOffset(reach * 0.6, reach * 0.35),
			BackgroundTransparency = 1,
		})
		travel.Completed:Once(function()
			streak:Destroy()
		end)
		travel:Play()
	end)
end

--- 벚꽃. 좌우로 흔들리며 돈다.
function renderers.petals(spec)
	local drift = tonumber(spec.Drift) or 120

	return spawner(tonumber(spec.Rate) or 8, function()
		local size = viewport()
		local petal = frame(canvas, {
			Position = UDim2.fromOffset(rng:NextNumber(-0.05, 1.05) * size.X, -30),
			Size = UDim2.fromOffset(rng:NextInteger(10, 20), rng:NextInteger(7, 13)),
			BackgroundColor3 = pick(spec.Colors, Color3.fromRGB(255, 196, 216)),
			BackgroundTransparency = 0.12,
			Rotation = rng:NextNumber(0, 360),
			ZIndex = 3,
		})
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = petal

		local seconds = rng:NextNumber(4.5, 8)
		local sway = rng:NextNumber(-drift, drift)
		local travel = TweenService:Create(petal, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
			Position = petal.Position + UDim2.fromOffset(sway, size.Y + 80),
			Rotation = petal.Rotation + rng:NextNumber(-540, 540),
		})
		travel.Completed:Once(function()
			petal:Destroy()
		end)
		travel:Play()
	end)
end

--- 디스코. 광선이 계속 돌고 화면 전체 색이 순환한다.
function renderers.disco(spec)
	local rays = math.clamp(math.floor(tonumber(spec.Rays) or 10), 4, 20)
	local holder = frame(canvas, {
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(2.4, 2.4),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})

	local palette = {
		Color3.fromRGB(255, 96, 170),
		Color3.fromRGB(110, 170, 255),
		Color3.fromRGB(120, 255, 180),
		Color3.fromRGB(255, 226, 110),
	}
	for i = 1, rays do
		local ray = frame(holder, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.5, 0.03 + rng:NextNumber(0, 0.02)),
			Rotation = (i - 1) / rays * 360,
			BackgroundColor3 = palette[(i - 1) % #palette + 1],
			BackgroundTransparency = tonumber(spec.Alpha) or 0.86,
			ZIndex = 2,
		})
		gradient(ray, NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}))
	end

	local speed = tonumber(spec.Speed) or 0.5
	track(RunService.RenderStepped:Connect(function()
		holder.Rotation = (Workspace:GetServerTimeNow() * speed * 60) % 360
	end))
end

--- 혹한. 가장자리에서 안쪽으로 성에가 자란다. 가운데는 비워 둔다.
function renderers.frost(spec)
	local color = spec.Color or Color3.fromRGB(214, 240, 255)
	local count = math.clamp(math.floor(tonumber(spec.Crystals) or 24), 4, 48)
	local maxAlpha = tonumber(spec.MaxAlpha) or 0.55
	local grow = tonumber(spec.GrowSeconds) or 12

	for i = 1, count do
		--[[
			가장자리 네 변에 고르게 나눠 붙인다.
			무작위로 뿌리면 한쪽만 얼어붙어 고장난 것처럼 보인다.
		]]
		local side = (i - 1) % 4
		local along = rng:NextNumber(0.05, 0.95)
		local x, y = 0, 0
		if side == 0 then
			x, y = along, 0
		elseif side == 1 then
			x, y = along, 1
		elseif side == 2 then
			x, y = 0, along
		else
			x, y = 1, along
		end

		local crystal = frame(canvas, {
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(0.02, 0.02),
			BackgroundColor3 = color,
			BackgroundTransparency = 1,
			Rotation = rng:NextNumber(0, 90),
			ZIndex = 2,
		})
		gradient(crystal, NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		}), (side < 2) and (side == 0 and 90 or 270) or (side == 2 and 0 or 180))

		local scale = rng:NextNumber(0.16, 0.34)
		TweenService:Create(crystal, TweenInfo.new(grow * rng:NextNumber(0.6, 1.2), Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(scale, scale),
			BackgroundTransparency = maxAlpha,
			Rotation = crystal.Rotation + rng:NextNumber(-25, 25),
		}):Play()
	end
end

--- 균열. 테두리가 느리게 뛴다. 가운데를 가리지 않는다.
function renderers.pulse(spec)
	local color = spec.Color or Color3.fromRGB(255, 92, 48)
	local maxAlpha = tonumber(spec.MaxAlpha) or 0.42
	local edges = {}

	local sides = {
		{ pos = UDim2.fromScale(0.5, 0), size = UDim2.fromScale(1, 0.28), rot = 270, anchor = Vector2.new(0.5, 0) },
		{ pos = UDim2.fromScale(0.5, 1), size = UDim2.fromScale(1, 0.28), rot = 90, anchor = Vector2.new(0.5, 1) },
		{ pos = UDim2.fromScale(0, 0.5), size = UDim2.fromScale(0.22, 1), rot = 180, anchor = Vector2.new(0, 0.5) },
		{ pos = UDim2.fromScale(1, 0.5), size = UDim2.fromScale(0.22, 1), rot = 0, anchor = Vector2.new(1, 0.5) },
	}
	for _, side in ipairs(sides) do
		local edge = frame(canvas, {
			AnchorPoint = side.anchor,
			Position = side.pos,
			Size = side.size,
			BackgroundColor3 = color,
			BackgroundTransparency = 1,
			ZIndex = 2,
		})
		gradient(edge, NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.1),
		}), side.rot)
		table.insert(edges, edge)
	end

	local period = math.max(tonumber(spec.Period) or 1.6, 0.2)
	track(RunService.RenderStepped:Connect(function()
		--[[
			심장박동이라 사인파가 아니다.
			한 번 크게, 곧이어 작게 두 번 뛰고 쉰다.
		]]
		local t = (Workspace:GetServerTimeNow() % period) / period
		local beat = math.max(math.sin(t * math.pi * 2) ^ 4, math.sin(t * math.pi * 4) ^ 8 * 0.6)
		for _, edge in ipairs(edges) do
			edge.BackgroundTransparency = 1 - beat * maxAlpha
		end
	end))
end

--- 황금비. 가로 폭을 줄였다 늘여서 뒤집히는 것처럼 보이게 한다.
function renderers.coins(spec)
	local color = spec.Color or Color3.fromRGB(255, 212, 84)
	local spin = tonumber(spec.Spin) or 200

	return spawner(tonumber(spec.Rate) or 12, function()
		local size = viewport()
		local coin = frame(canvas, {
			Position = UDim2.fromOffset(rng:NextNumber(0, 1) * size.X, -40),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.05,
			ZIndex = 3,
		})
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = coin
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 246, 200)
		stroke.Thickness = 2
		stroke.Transparency = 0.3
		stroke.Parent = coin

		local phase = rng:NextNumber(0, math.pi * 2)
		local rate = spin / 60
		local spinConnection
		spinConnection = RunService.RenderStepped:Connect(function()
			if not coin.Parent then
				spinConnection:Disconnect()
				return
			end
			local flip = math.abs(math.cos(Workspace:GetServerTimeNow() * rate + phase))
			coin.Size = UDim2.fromOffset(math.max(3, 18 * flip), 18)
		end)
		track(spinConnection)

		local travel = TweenService:Create(coin, TweenInfo.new(rng:NextNumber(1.6, 2.8), Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = coin.Position + UDim2.fromOffset(rng:NextNumber(-60, 60), size.Y + 90),
		})
		travel.Completed:Once(function()
			spinConnection:Disconnect()
			coin:Destroy()
		end)
		travel:Play()
	end)
end

--- 성운. 화면 중심을 축으로 별이 아주 느리게 돈다.
function renderers.stars(spec)
	local count = math.clamp(math.floor(tonumber(spec.Count) or 120), 10, 300)
	local holder = frame(canvas, {
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(2.2, 2.2),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})

	for _ = 1, count do
		local dot = frame(holder, {
			Position = UDim2.fromScale(rng:NextNumber(0, 1), rng:NextNumber(0, 1)),
			Size = UDim2.fromOffset(rng:NextInteger(2, 5), rng:NextInteger(2, 5)),
			BackgroundColor3 = pick(spec.Colors, Color3.new(1, 1, 1)),
			BackgroundTransparency = rng:NextNumber(0.1, 0.6),
			ZIndex = 2,
		})
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
	end

	local speed = tonumber(spec.Speed) or 0.045
	track(RunService.RenderStepped:Connect(function()
		holder.Rotation = (Workspace:GetServerTimeNow() * speed * 60) % 360
	end))
end

--- 타코. 네모난 색종이가 빠르게 쏟아진다.
function renderers.confetti(spec)
	return spawner(tonumber(spec.Rate) or 20, function()
		local size = viewport()
		local piece = frame(canvas, {
			Position = UDim2.fromOffset(rng:NextNumber(0, 1) * size.X, -30),
			Size = UDim2.fromOffset(rng:NextInteger(7, 13), rng:NextInteger(12, 20)),
			BackgroundColor3 = pick(spec.Colors, Color3.fromRGB(255, 176, 70)),
			BackgroundTransparency = 0.05,
			Rotation = rng:NextNumber(0, 360),
			ZIndex = 3,
		})

		local travel = TweenService:Create(piece, TweenInfo.new(rng:NextNumber(2.2, 3.6), Enum.EasingStyle.Linear), {
			Position = piece.Position + UDim2.fromOffset(rng:NextNumber(-160, 160), size.Y + 70),
			Rotation = piece.Rotation + rng:NextNumber(-720, 720),
		})
		travel.Completed:Once(function()
			piece:Destroy()
		end)
		travel:Play()
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
	흔들림이 아니라 흔들거림.

	카메라 흔들기는 이미 EventFxController 가 한다. 그건 "쿵" 하는 순간용이고,
	이건 연출 내내 아주 느리게 도는 기울기다. 둘을 같이 쓰면 멀미가 난다.
]]
local function setSway(amount: number)
	--[[
		세기가 바뀌면 반드시 다시 건다.

		"이미 걸려 있으니 넘어간다" 로 두면 앞 연출의 세기가 그대로 남는다.
		오로라(0.35)에서 성운(0.6)으로 바꿔도 화면이 안 달라지는 이유가 이거였다.
	]]
	if swayBound then
		RunService:UnbindFromRenderStep(SWAY_BIND)
		swayBound = false
	end
	if amount <= 0 or ClientState.settings.lowGraphics then
		return
	end

	swayBound = true
	RunService:BindToRenderStep(SWAY_BIND, Enum.RenderPriority.Camera.Value + 2, function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local t = Workspace:GetServerTimeNow()
		camera.CFrame = camera.CFrame * CFrame.Angles(
			math.rad(math.sin(t * 0.35) * amount * 0.5),
			math.rad(math.sin(t * 0.21) * amount * 0.4),
			math.rad(math.sin(t * 0.27) * amount)
		)
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
	titleCard.BackgroundTransparency = 1

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

local function clearScreen()
	threads += 1
	if stopRenderer then
		pcall(stopRenderer)
		stopRenderer = nil
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)

	if canvas then
		for _, child in ipairs(canvas:GetChildren()) do
			child:Destroy()
		end
	end
end

local function stopShow()
	running = nil
	clearScreen()
	setSway(0)
	applyGrade(ShowConfig.BaseGrade, ShowConfig.FadeSeconds)
end

local function startShow(show)
	clearScreen()
	running = show.Id

	applyGrade(show.Grade or ShowConfig.BaseGrade, ShowConfig.FadeSeconds)

	local camera = show.Camera or {}
	setSway(tonumber(camera.Sway) or 0)

	if not ClientState.settings.lowGraphics then
		local renderer = renderers[show.Screen and show.Screen.Kind or ""]
		if renderer then
			local ok, result = pcall(renderer, show.Screen)
			if ok then
				stopRenderer = result
			else
				warn("[ShowClient] 화면 연출 실패(" .. show.Id .. "): " .. tostring(result))
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
	screen = UI.create("ScreenGui", {
		Name = "RadShow",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		--[[
			토스트(150)보다 아래, 패널(60)보다 위에 둔다.
			연출이 알림을 덮으면 무슨 일이 났는지 읽을 수 없다.
		]]
		DisplayOrder = Theme.Z.Toast - 10,
		Parent = playerGui,
	})

	canvas = UI.create("Frame", {
		Name = "Canvas",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Parent = screen,
	})

	titleCard = UI.create("Frame", {
		Name = "TitleCard",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(720, 90),
		Position = UDim2.fromScale(0.5, 0.22),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 20,
		Parent = screen,
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

	-- 저사양으로 바꾸면 화면 연출만 걷어낸다. 하늘은 서버가 정한 그대로 둔다.
	ClientState.SettingsChanged:Connect(function(settings)
		if settings.lowGraphics and running then
			clearScreen()
			setSway(0)
			applyGrade(ShowConfig.BaseGrade, 1)
		end
	end)
end

local ok, err = pcall(start)
if not ok then
	warn("[ShowClient] 연출 화면 시작 실패: " .. tostring(err))
end

--!nonstrict

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local ShowConfig = require(Shared.Config.ShowConfig)
local ParticleAssets = require(Shared.UI.ParticleAssets)
local NetServer = require(Shared.Net.NetServer)

local BaseService = require(script.Parent.BaseService)
local WorldService = require(script.Parent.WorldService)

local ShowService = {}

local RUNTIME_TAG = "RadShowRuntime"
local RUNTIME_FOLDER = "RadShowRuntime"

local rng = Random.new(os.clock() * 1e6)
local started = false

--[[
	지금 도는 연출.

	  show      ShowConfig 항목
	  endsAt    Workspace:GetServerTimeNow() 기준 종료 시각
	  folder    맵에 놓은 것들을 담아 둔 폴더. 통째로 Destroy 하면 정리가 끝난다.
	  threads   반복 연출(운석 낙하 등)을 돌리는 코루틴
	  token     세대 번호. 늦게 도착한 콜백이 다음 연출을 건드리지 못하게 막는다.
]]
local active = nil
local token = 0

--------------------------------------------------------------------------------
-- 맵 좌표
--------------------------------------------------------------------------------

--[[
	맵의 한가운데.

	기지들의 평균 위치를 쓴다. 스폰 파트나 원점은 맵 구석에 있는 경우가 많아서
	거기를 중심으로 잡으면 연출이 한쪽으로 쏠린다.
]]
local function mapCenter(): Vector3
	local sum, count = Vector3.zero, 0
	for _, base in ipairs(BaseService.allBases()) do
		local ok, pivot = pcall(function()
			return base:GetPivot().Position
		end)
		if ok and typeof(pivot) == "Vector3" then
			sum += pivot
			count += 1
		end
	end
	if count == 0 then
		local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
		return spawn and spawn.Position or Vector3.zero
	end
	return sum / count
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

--- 이 좌표 바로 아래의 땅 높이. 못 찾으면 기준 높이를 그대로 돌려준다.
local function groundAt(position: Vector3, fallbackY: number): number
	groundParams.FilterDescendantsInstances = { Workspace:FindFirstChild(RUNTIME_FOLDER) }

	local origin = Vector3.new(position.X, position.Y + 400, position.Z)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -1200, 0), groundParams)
	if hit then
		return hit.Position.Y
	end
	return fallbackY
end

--------------------------------------------------------------------------------
-- 조명
--------------------------------------------------------------------------------

local function tweenLighting(target, seconds: number)
	local filtered = {}
	for key, value in pairs(target) do
		if Lighting[key] ~= nil then
			filtered[key] = value
		end
	end
	TweenService:Create(Lighting, TweenInfo.new(math.max(seconds, 0.1)), filtered):Play()
end

--[[
	기준 조명으로 되돌린다.

	place 에 저장된 값으로 돌아가지 않는 게 중요하다.
	"너무 밝다" 의 원인이 그 저장값이라, 되돌리면 다시 밝아진다.
]]
function ShowService.applyBaseLighting(instant: boolean?)
	tweenLighting(ShowConfig.BaseLighting, instant and 0.1 or ShowConfig.FadeSeconds)
end

--------------------------------------------------------------------------------
-- 맵에 놓는 것들
--------------------------------------------------------------------------------

local function runtimeFolder(): Folder
	local folder = Workspace:FindFirstChild(RUNTIME_FOLDER)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = RUNTIME_FOLDER
		folder:SetAttribute(RUNTIME_TAG, true)
		folder.Parent = Workspace
	end
	return folder
end

local function decorate(instance: Instance, parent: Instance)
	instance:SetAttribute(RUNTIME_TAG, true)
	instance.Parent = parent
end

--[[
	하늘을 덮는 한 장짜리 방출판.

	비·눈·꽃잎·금화가 전부 이걸 쓴다. 입자 하나하나를 파트로 만들면
	사람 수만큼 복제가 늘어나는데, 이 방식은 파트 하나면 끝난다.
	차이는 크기·속도·색·수명뿐이고, 그 네 값이 결과를 완전히 다르게 만든다.
]]
local function spawnFalling(folder: Folder, center: Vector3, spec, texture: string, lifetime: number)
	local sheet = Instance.new("Part")
	sheet.Name = "FallSheet"
	sheet.Size = Vector3.new(760, 4, 760)
	sheet.Position = center + Vector3.new(0, 240, 0)
	sheet.Anchored = true
	sheet.CanCollide = false
	sheet.CanQuery = false
	sheet.CanTouch = false
	sheet.CastShadow = false
	sheet.Transparency = 1
	decorate(sheet, folder)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = ParticleAssets.get(texture)
	emitter.Color = ColorSequence.new(spec.Color or Color3.new(1, 1, 1))
	emitter.LightEmission = 0.4
	emitter.LightInfluence = 0.25
	emitter.Size = NumberSequence.new(tonumber(spec.Size) or 3)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.08, 0.1),
		NumberSequenceKeypoint.new(0.9, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rate = math.clamp(tonumber(spec.Rate) or 100, 1, 500)
	emitter.Lifetime = NumberRange.new(lifetime * 0.8, lifetime * 1.2)
	emitter.Speed = NumberRange.new((tonumber(spec.Speed) or 20) * 0.85, (tonumber(spec.Speed) or 20) * 1.15)
	emitter.SpreadAngle = Vector2.new(14, 14)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Acceleration = Vector3.new(rng:NextNumber(-6, 6), -12, rng:NextNumber(-6, 6))
	emitter.Parent = sheet
	return sheet
end

--[[
	하늘을 도는 빛덩이.

	오로라와 성운이 이걸 쓴다. 고개를 들었을 때 뭔가 지나가야
	"하늘이 변했다" 가 색 필터가 아니라 사건으로 읽힌다.
]]
local function spawnOrbit(folder: Folder, center: Vector3, spec)
	local count = math.clamp(math.floor(tonumber(spec.Count) or 6), 1, 24)
	local radius = tonumber(spec.Radius) or 260
	local height = tonumber(spec.Height) or 180

	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local orb = Instance.new("Part")
		orb.Name = "Orb"
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(14, 14, 14)
		orb.Anchored = true
		orb.CanCollide = false
		orb.CanQuery = false
		orb.CanTouch = false
		orb.CastShadow = false
		orb.Material = Enum.Material.Neon
		orb.Color = spec.Color or Color3.fromRGB(160, 220, 255)
		orb.Transparency = 0.35
		orb.Position = center + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		decorate(orb, folder)

		local trail0 = Instance.new("Attachment")
		trail0.Position = Vector3.new(0, 0, 6)
		trail0.Parent = orb
		local trail1 = Instance.new("Attachment")
		trail1.Position = Vector3.new(0, 0, -6)
		trail1.Parent = orb

		local trail = Instance.new("Trail")
		trail.Attachment0 = trail0
		trail.Attachment1 = trail1
		trail.Color = ColorSequence.new(spec.Color or Color3.fromRGB(160, 220, 255))
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Lifetime = 2.4
		trail.LightEmission = 1
		trail.Parent = orb

		--[[
			한 바퀴를 트윈 하나로 돌릴 수는 없다. 회전은 늘 짧은 쪽으로 간다.
			네 토막으로 끊어 이어 붙인다.
		]]
		local step = 0
		local orbitSeconds = 26 + i * 0.6
		task.spawn(function()
			while orb.Parent do
				step += 1
				local a = angle + step * (math.pi / 2)
				local goal = center + Vector3.new(math.cos(a) * radius, height + math.sin(step) * 12, math.sin(a) * radius)
				TweenService:Create(orb, TweenInfo.new(orbitSeconds / 4, Enum.EasingStyle.Linear), {
					Position = goal,
				}):Play()
				task.wait(orbitSeconds / 4)
			end
		end)
	end
end

--[[
	바닥이 갈라진다.

	하늘만 건드리는 연출들과 달리, 이건 발밑을 본다.
	땅 높이를 광선으로 찾아 그 위에 살짝 띄운다 — 파묻히면 아무것도 안 보인다.
]]
local function spawnCracks(folder: Folder, center: Vector3, spec)
	local count = math.clamp(math.floor(tonumber(spec.Count) or 12), 1, 40)
	local radius = tonumber(spec.Radius) or 240
	local baseY = center.Y

	for i = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = radius * math.sqrt(rng:NextNumber(0.05, 1))
		local spot = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local y = groundAt(spot, baseY)

		local crack = Instance.new("Part")
		crack.Name = "Crack"
		crack.Size = Vector3.new(tonumber(spec.Width) or 5, 0.4, 1)
		crack.CFrame = CFrame.new(Vector3.new(spot.X, y + 0.25, spot.Z))
			* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		crack.Anchored = true
		crack.CanCollide = false
		crack.CanQuery = false
		crack.CanTouch = false
		crack.CastShadow = false
		crack.Material = Enum.Material.Neon
		crack.Color = spec.Color or Color3.fromRGB(255, 108, 40)
		crack.Transparency = 1
		decorate(crack, folder)

		local light = Instance.new("PointLight")
		light.Color = spec.Color or Color3.fromRGB(255, 108, 40)
		light.Brightness = 0
		light.Range = 26
		light.Parent = crack

		local attachment = Instance.new("Attachment")
		attachment.Parent = crack

		local embers = Instance.new("ParticleEmitter")
		embers.Texture = ParticleAssets.get("Ember")
		embers.Color = ColorSequence.new(spec.Color or Color3.fromRGB(255, 140, 60))
		embers.LightEmission = 1
		embers.LightInfluence = 0
		embers.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 2.2),
			NumberSequenceKeypoint.new(1, 0),
		})
		embers.Transparency = NumberSequence.new(0.2)
		embers.Rate = 12
		embers.Lifetime = NumberRange.new(1.4, 2.6)
		embers.Speed = NumberRange.new(6, 16)
		embers.SpreadAngle = Vector2.new(24, 24)
		embers.Parent = attachment

		local grow = TweenInfo.new(tonumber(spec.GrowSeconds) or 3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, i * 0.08)
		TweenService:Create(crack, grow, {
			Size = Vector3.new(tonumber(spec.Width) or 5, 0.4, tonumber(spec.Length) or 46),
			Transparency = 0.1,
		}):Play()
		TweenService:Create(light, grow, { Brightness = 2.2 }):Play()
	end
end

--[[
	회전하는 색 조명.

	디스코와 타코가 쓴다. 원통을 눕혀 아래로 기울이면 무대 조명처럼 보인다.
]]
local function spawnSpotlights(folder: Folder, center: Vector3, spec)
	local count = math.clamp(math.floor(tonumber(spec.Count) or 6), 1, 16)
	local radius = tonumber(spec.Radius) or 190
	local height = tonumber(spec.Height) or 90
	local palette = {
		Color3.fromRGB(255, 96, 170),
		Color3.fromRGB(110, 170, 255),
		Color3.fromRGB(120, 255, 180),
		Color3.fromRGB(255, 226, 110),
		Color3.fromRGB(196, 120, 255),
	}

	for i = 1, count do
		local color = palette[(i - 1) % #palette + 1]
		local beam = Instance.new("Part")
		beam.Name = "Spotlight"
		beam.Shape = Enum.PartType.Cylinder
		beam.Size = Vector3.new(height * 2.2, 26, 26)
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.CastShadow = false
		beam.Material = Enum.Material.Neon
		beam.Color = color
		beam.Transparency = 0.82
		decorate(beam, folder)

		local pivot = center + Vector3.new(0, height, 0)
		local step = 0
		local turnSeconds = 6 / math.max(tonumber(spec.Speed) or 0.35, 0.05)
		local phase = (i - 1) / count * math.pi * 2

		task.spawn(function()
			while beam.Parent do
				step += 1
				local a = phase + step * (math.pi / 2)
				local target = center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
				local look = CFrame.lookAt(pivot, target)
				TweenService:Create(beam, TweenInfo.new(turnSeconds / 4, Enum.EasingStyle.Linear), {
					CFrame = look * CFrame.new(0, 0, -height) * CFrame.Angles(0, math.rad(90), 0),
				}):Play()
				task.wait(turnSeconds / 4)
			end
		end)
	end
end

--[[
	운석 낙하.

	이 연출만 "가서 볼 수 있는" 게 남는다.
	떨어진 자리에 그을음이 잠깐 남고, 근처에 있던 사람은 카메라가 흔들린다.
]]
local function dropMeteor(folder: Folder, center: Vector3, spec, generation: number)
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = (tonumber(spec.Radius) or 320) * math.sqrt(rng:NextNumber(0.05, 1))
	local spot = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	local groundY = groundAt(spot, center.Y)
	local landing = Vector3.new(spot.X, groundY + 2, spot.Z)
	local start = landing + Vector3.new(rng:NextNumber(-90, 90), tonumber(spec.Height) or 520, rng:NextNumber(-90, 90))

	local rock = Instance.new("Part")
	rock.Name = "Meteor"
	rock.Shape = Enum.PartType.Ball
	rock.Size = Vector3.new(9, 9, 9)
	rock.Position = start
	rock.Anchored = true
	rock.CanCollide = false
	rock.CanQuery = false
	rock.CanTouch = false
	rock.CastShadow = false
	rock.Material = Enum.Material.Neon
	rock.Color = spec.Color or Color3.fromRGB(255, 150, 60)
	decorate(rock, folder)

	local light = Instance.new("PointLight")
	light.Color = rock.Color
	light.Brightness = 4
	light.Range = 45
	light.Parent = rock

	local tail0 = Instance.new("Attachment")
	tail0.Position = Vector3.new(0, 4, 0)
	tail0.Parent = rock
	local tail1 = Instance.new("Attachment")
	tail1.Position = Vector3.new(0, -4, 0)
	tail1.Parent = rock

	local trail = Instance.new("Trail")
	trail.Attachment0 = tail0
	trail.Attachment1 = tail1
	trail.Color = ColorSequence.new(rock.Color, Color3.fromRGB(255, 236, 190))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 1.1
	trail.LightEmission = 1
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = rock

	local fall = TweenService:Create(
		rock,
		TweenInfo.new(tonumber(spec.FallSeconds) or 1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = landing }
	)

	fall.Completed:Once(function()
		if not rock.Parent or token ~= generation then
			return
		end

		local burst = Instance.new("Part")
		burst.Name = "Impact"
		burst.Shape = Enum.PartType.Ball
		burst.Size = Vector3.new(4, 4, 4)
		burst.Position = landing
		burst.Anchored = true
		burst.CanCollide = false
		burst.CanQuery = false
		burst.CanTouch = false
		burst.CastShadow = false
		burst.Material = Enum.Material.Neon
		burst.Color = Color3.fromRGB(255, 226, 176)
		burst.Transparency = 0.1
		decorate(burst, folder)

		local shock = Instance.new("Attachment")
		shock.Parent = burst

		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = ParticleAssets.get("Spark")
		sparks.Color = ColorSequence.new(rock.Color, Color3.fromRGB(255, 240, 210))
		sparks.LightEmission = 1
		sparks.LightInfluence = 0
		sparks.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 3.2),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparks.Transparency = NumberSequence.new(0.1)
		sparks.Rate = 0
		sparks.Lifetime = NumberRange.new(0.5, 1.2)
		sparks.Speed = NumberRange.new(40, 90)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Parent = shock
		sparks:Emit(70)

		TweenService:Create(burst, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = Vector3.new(46, 46, 46),
			Transparency = 1,
		}):Play()

		rock:Destroy()

		-- 가까이 있던 사람만 흔든다. 맵 반대편까지 흔들면 무슨 일인지 알 수 없다.
		for _, player in ipairs(Players:GetPlayers()) do
			if NetServer.isNear(player, landing, 220) then
				NetServer.fire(player, "EventFx", {
					shake = tonumber(spec.Shake) or 0.5,
					seconds = 0.6,
					punch = 4,
				})
			end
		end

		task.delay(tonumber(spec.ScorchSeconds) or 6, function()
			if burst.Parent then
				burst:Destroy()
			end
		end)
	end)

	fall:Play()
end

local WORLD_BUILDERS = {
	rain = function(folder, center, spec)
		spawnFalling(folder, center, spec, "Shard", 2.2)
	end,
	fall = function(folder, center, spec)
		spawnFalling(folder, center, spec, "Glow", 7)
	end,
	orbit = spawnOrbit,
	cracks = spawnCracks,
	spotlights = spawnSpotlights,
}

--------------------------------------------------------------------------------
-- 소리
--------------------------------------------------------------------------------

--[[
	노래는 서버가 재생하지 않는다.

	서버에서 재생하면 음악을 꺼 둔 사람에게도 들린다.
	SoundService 에 올려 두기만 하면 MusicController 가 각자 설정을 보고
	켜거나 끈 뒤 시간을 맞춰 재생한다. 타코 파티가 쓰던 방식 그대로다.
]]
local function placeSong(show)
	local spec = show.Sound
	if type(spec) ~= "table" or type(spec.Id) ~= "string" or spec.Id == "" then
		return nil
	end

	local song = Instance.new("Sound")
	song.Name = "RadShowSong"
	song.SoundId = spec.Id
	song.Looped = spec.Looped ~= false
	song.Volume = 0
	song.Playing = false
	song.TimePosition = 0
	song:SetAttribute("RadWorldEventRuntime", true)
	song:SetAttribute("RadBaseVolume", math.clamp(tonumber(spec.Volume) or 0.35, 0, 10))
	song:SetAttribute("RadStartedAt", Workspace:GetServerTimeNow())
	song:SetAttribute(RUNTIME_TAG, true)
	song.Parent = SoundService
	return song
end

--------------------------------------------------------------------------------
-- 시작 / 정지
--------------------------------------------------------------------------------

local function payload()
	if not active then
		return { id = nil }
	end
	return {
		id = active.show.Id,
		endsAt = active.endsAt,
		seconds = active.seconds,
		serverNow = Workspace:GetServerTimeNow(),
	}
end

local function broadcast()
	NetServer.fireAll("ShowSync", payload())
end

local function clearRuntime()
	local folder = Workspace:FindFirstChild(RUNTIME_FOLDER)
	if folder then
		folder:Destroy()
	end
	for _, child in ipairs(SoundService:GetChildren()) do
		if child:GetAttribute(RUNTIME_TAG) == true then
			child:Destroy()
		end
	end
end

function ShowService.stop(silent: boolean?)
	if not active then
		return false
	end

	token += 1
	local finished = active
	active = nil

	clearRuntime()
	ShowService.applyBaseLighting()
	WorldService.pauseClock(false)

	if not silent then
		broadcast()
	end
	return true, finished.show.Id
end

function ShowService.trigger(showId: string?, seconds: number?)
	local show = ShowConfig.get(showId)
	if not show then
		return false, "unknown_show"
	end

	if active then
		ShowService.stop(true)
	end

	token += 1
	local generation = token
	local duration = ShowConfig.seconds(show, seconds)
	local folder = runtimeFolder()
	local center = mapCenter()

	--[[
		연출이 도는 동안 시계를 멈춘다.
		안 멈추면 WorldService 가 매 초 ClockTime 을 덮어써서
		밤 연출인데 해가 뜬다.
	]]
	WorldService.pauseClock(true)
	tweenLighting(show.Sky or ShowConfig.BaseLighting, ShowConfig.FadeSeconds)

	local builder = WORLD_BUILDERS[show.World and show.World.Kind or "none"]
	if builder then
		local ok, err = pcall(builder, folder, center, show.World)
		if not ok then
			warn("[ShowService] 월드 연출 실패(" .. show.Id .. "): " .. tostring(err))
		end
	end

	local song = placeSong(show)

	active = {
		show = show,
		seconds = duration,
		endsAt = Workspace:GetServerTimeNow() + duration,
		folder = folder,
		song = song,
		generation = generation,
	}

	-- 운석처럼 계속 무언가를 떨어뜨리는 연출은 여기서 반복시킨다.
	if show.World and show.World.Kind == "impact" then
		task.spawn(function()
			while token == generation and active do
				local ok, err = pcall(dropMeteor, folder, center, show.World, generation)
				if not ok then
					warn("[ShowService] 운석 낙하 실패: " .. tostring(err))
				end
				task.wait(math.max(tonumber(show.World.Interval) or 2.6, 0.4))
			end
		end)
	end

	broadcast()

	task.delay(duration, function()
		if token == generation and active then
			ShowService.stop()
		end
	end)

	return true, show.Id
end

function ShowService.current()
	return active and active.show or nil
end

function ShowService.getState()
	return payload()
end

function ShowService.start()
	if started then
		return
	end
	started = true

	clearRuntime()
	ShowService.applyBaseLighting(true)

	Players.PlayerAdded:Connect(function(player)
		task.delay(3, function()
			if player.Parent then
				NetServer.fire(player, "ShowSync", payload())
			end
		end)
	end)
end

return ShowService

--!nonstrict

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local WorldConfig = require(Shared.Config.WorldConfig)
local ShowConfig = require(Shared.Config.ShowConfig)
local Rng = require(Shared.Util.Rng)
local NetServer = require(Shared.Net.NetServer)

local WorldService = {}

local rng = Random.new(os.clock() * 1e6)
local startedAt = 0
local active = nil
local runtimeEventObject: Instance? = nil
local runtimeEventSong: Sound? = nil

WorldService.clockPaused = false

function WorldService.pauseClock(paused: boolean)
	WorldService.clockPaused = paused == true
end

local function payload()
	if not active then
		return { id = nil }
	end
	return {
		id = active.Id,
		endsAt = active.endsAt,
		seconds = active.Seconds,
	}
end

local function broadcast()
	NetServer.fireAll("WorldEvent", payload())
end

function WorldService.currentEvent()
	if not active then
		return nil
	end
	if Workspace:GetServerTimeNow() >= active.endsAt then
		return nil
	end
	return active
end

function WorldService.multiplier(kind: string): number
	local event = WorldService.currentEvent()
	if not event then
		return 1
	end
	return event[kind] or 1
end

function WorldService.isNight(): boolean
	local _, night = WorldConfig.clockAt(Workspace:GetServerTimeNow() - startedAt)
	return night
end

local function clearRuntimeEvent()
	if runtimeEventObject then
		runtimeEventObject:Destroy()
		runtimeEventObject = nil
	end
	if runtimeEventSong then
		runtimeEventSong:Stop()
		runtimeEventSong:Destroy()
		runtimeEventSong = nil
	end

	-- Studio에서 실행 중 서비스를 다시 시작한 경우 남은 복제본만 정리한다.
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:GetAttribute("RadWorldEventRuntime") == true then
			child:Destroy()
		end
	end
	for _, child in ipairs(SoundService:GetChildren()) do
		if child:GetAttribute("RadWorldEventRuntime") == true then
			child:Destroy()
		end
	end
end

local function findTacoSong(eventsFolder: Instance, tacoTemplate: Instance?): Sound?
	local separate = eventsFolder:FindFirstChild("TacoSong")
	if separate and separate:IsA("Sound") then
		return separate
	end
	if tacoTemplate then
		local nested = tacoTemplate:FindFirstChild("TacoSong", true)
		if nested and nested:IsA("Sound") then
			return nested
		end
	end
	return nil
end

local function playTacoSong(songTemplate: Sound?)
	local configuredId = WorldConfig.Events.TacoSongId

	--[[
		맵에 Sound 를 안 넣어 뒀어도 노래는 나와야 한다.
		설정에 ID 가 있으면 그걸로 하나 만들어 쓴다.
	]]
	if not songTemplate then
		if type(configuredId) ~= "string" or configuredId == "" then
			warn("[WorldService] TacoSong이 없습니다. ServerStorage.Events.TacoSong 또는 Taco 내부에 Sound를 넣어 주세요.")
			return
		end
		songTemplate = Instance.new("Sound")
		songTemplate.Name = "TacoSong"
		songTemplate.Volume = tonumber(WorldConfig.Events.TacoSongVolume) or 0.5
	end

	local song = songTemplate:Clone()
	song.Name = "RadTacoSong"

	-- 설정한 ID 가 항상 이긴다. 맵마다 다른 노래가 나오면 그 노래가 아니게 된다.
	if type(configuredId) == "string" and configuredId ~= "" then
		song.SoundId = configuredId
	end
	if song.SoundId == "" then
		warn("[WorldService] TacoSong.SoundId가 비어 있어 노래를 재생할 수 없습니다.")
		song:Destroy()
		return
	end
	song:SetAttribute("RadWorldEventRuntime", true)
	song:SetAttribute("RadBaseVolume", math.clamp(songTemplate.Volume, 0, 10))
	song:SetAttribute("RadStartedAt", Workspace:GetServerTimeNow())
	song.Looped = songTemplate:GetAttribute("EventLooped") ~= false
	song.Playing = false
	song.TimePosition = 0
	song.Parent = SoundService
	runtimeEventSong = song

	-- 설정만 보고 즉석에서 만든 원본이면 남겨 둘 이유가 없다
	if not songTemplate.Parent then
		songTemplate:Destroy()
	end
	-- 각 클라이언트의 음악 설정을 지키기 위해 서버에서는 재생하지 않는다.
	-- MusicController가 이 Sound를 감지해 로컬에서 동기화한 뒤 재생한다.
end

local function spawnTacoEvent()
	clearRuntimeEvent()

	local eventsFolder = ServerStorage:FindFirstChild("Events")
	if not eventsFolder then
		warn("[WorldService] Taco 이벤트를 시작했지만 ServerStorage.Events가 없습니다.")
		return
	end
	local template = eventsFolder:FindFirstChild("Taco")
	local songTemplate = findTacoSong(eventsFolder, template)

	if template then
		local ok, cloneOrError = pcall(function()
			return template:Clone()
		end)
		if not ok or not cloneOrError then
			warn("[WorldService] ServerStorage.Events.Taco 복제 실패: " .. tostring(cloneOrError))
		else
			local clone = cloneOrError
			-- Taco 안에 둔 원본 Sound가 공간음으로 한 번 더 재생되지 않게 한다.
			for _, descendant in ipairs(clone:GetDescendants()) do
				if descendant:IsA("Sound") and descendant.Name == "TacoSong" then
					descendant.Playing = false
				end
			end
			clone:SetAttribute("RadWorldEventRuntime", true)
			clone.Parent = Workspace
			runtimeEventObject = clone
			-- 위치, Anchored, 속도는 템플릿 값을 그대로 둔다. 준비한 Taco가 그대로 낙하한다.
		end
	else
		warn("[WorldService] Taco 이벤트를 시작했지만 ServerStorage.Events.Taco가 없습니다.")
	end

	-- Taco 파트가 없더라도 노래 템플릿이 준비돼 있으면 음악은 재생한다.
	playTacoSong(songTemplate)
end

local function startEvent()
	local weights = {}
	for _, event in ipairs(WorldConfig.Events.List) do
		weights[event.Id] = event.Weight
	end

	local id = Rng.weightedPick(weights, rng)
	local config = id and WorldConfig.event(id)
	if not config then
		return
	end

	active = table.clone(config)
	active.endsAt = Workspace:GetServerTimeNow() + config.Seconds

	if config.Id == "Taco" then
		spawnTacoEvent()
	else
		clearRuntimeEvent()
	end
	broadcast()
end

local function endEvent()
	if not active then
		return
	end
	clearRuntimeEvent()
	active = nil
	broadcast()
end

function WorldService.start()
	startedAt = Workspace:GetServerTimeNow()
	clearRuntimeEvent()

	--[[
		place 에 저장된 조명은 너무 밝다.

		서버가 뜨자마자 기준값으로 덮어쓴다. 여기서 먼저 깔아 두면
		이벤트가 조명을 저장했다 되돌릴 때도 이 값으로 돌아온다.
	]]
	for key, value in pairs(ShowConfig.BaseLighting) do
		if Lighting[key] ~= nil then
			Lighting[key] = value
		end
	end

	Lighting.ClockTime = WorldConfig.Day.SunriseHour

	task.spawn(function()
		while true do
			if not WorldService.clockPaused then
				local hour = WorldConfig.clockAt(Workspace:GetServerTimeNow() - startedAt)
				Lighting.ClockTime = hour
			end
			task.wait(1)
		end
	end)

	task.spawn(function()
		task.wait(WorldConfig.Events.FirstDelaySeconds)
		while true do
			startEvent()
			if active then
				task.wait(active.Seconds)
				endEvent()
			end
			task.wait(WorldConfig.Events.IntervalSeconds)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.delay(3, function()
			if player.Parent then
				NetServer.fire(player, "WorldEvent", payload())
			end
		end)
	end)
end

return WorldService

--!nonstrict

local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Theme = require(Shared.UI.Theme)

local ClientState = require(script.Parent.Parent.ClientState)

local MusicController = {}

local BACKGROUND_VOLUME = 0.05

local music: Sound? = nil
local eventMusic: Sound? = nil
local syncedEventMusic: Sound? = nil

--[[
	이벤트 노래.

	타코 파티만 있던 시절에는 이름으로 골랐다. 이제 연출(Show)마다
	각자의 노래를 올려 두므로 이름이 아니라 표식으로 고른다.
	서버가 SoundService 에 올려 두기만 하면 여기서 각자 설정에 맞춰 재생한다.
]]
local function isEventSong(instance: Instance): boolean
	return instance:IsA("Sound")
		and instance:GetAttribute("RadWorldEventRuntime") == true
end

local function eventVolume(sound: Sound): number
	return math.clamp(tonumber(sound:GetAttribute("RadBaseVolume")) or sound.Volume, 0, 10)
end

local function syncAndPlay(sound: Sound)
	local function begin()
		if eventMusic ~= sound or not sound.Parent then
			return
		end
		if ClientState.settingsReceived ~= true or ClientState.settings.music == false then
			return
		end

		local startedAt = tonumber(sound:GetAttribute("RadStartedAt")) or Workspace:GetServerTimeNow()
		local elapsed = math.max(Workspace:GetServerTimeNow() - startedAt, 0)
		local length = sound.TimeLength
		if length > 0 then
			if sound.Looped then
				elapsed %= length
			elseif elapsed >= length then
				return
			end
			sound.TimePosition = elapsed
		end
		sound.Volume = eventVolume(sound)
		sound:Play()
	end

	if sound.IsLoaded then
		begin()
	else
		sound.Loaded:Once(begin)
	end
end

local function apply()
	if not music or ClientState.settingsReceived ~= true then
		return
	end
	if eventMusic and not eventMusic.Parent then
		eventMusic = nil
		syncedEventMusic = nil
	end

	if ClientState.settings.music == false then
		if music.IsPlaying then
			music:Stop()
		end
		if eventMusic and eventMusic.IsPlaying then
			eventMusic:Stop()
		end
		syncedEventMusic = nil
		return
	end

	if eventMusic then
		-- 이벤트 음악과 평상시 음악이 겹쳐 들리지 않게 한다.
		if music.IsPlaying then
			music:Stop()
		end
		eventMusic.Volume = eventVolume(eventMusic)
		if syncedEventMusic ~= eventMusic then
			syncedEventMusic = eventMusic
			syncAndPlay(eventMusic)
		elseif eventMusic.IsLoaded and not eventMusic.IsPlaying then
			eventMusic:Play()
		end
	elseif not music.IsPlaying then
		music:Play()
	end
end

local function useEventMusic(sound: Sound)
	if eventMusic == sound then
		return
	end
	if eventMusic and eventMusic.IsPlaying then
		eventMusic:Stop()
	end
	eventMusic = sound
	syncedEventMusic = nil
	apply()
end

function MusicController.start()
	if music then
		return
	end

	music = Instance.new("Sound")
	music.Name = "RadMusic"
	music.SoundId = Theme.Sound.Music
	music.Looped = true
	music.Volume = BACKGROUND_VOLUME
	music.Parent = SoundService

	for _, child in ipairs(SoundService:GetChildren()) do
		if isEventSong(child) then
			useEventMusic(child)
			break
		end
	end

	SoundService.ChildAdded:Connect(function(child)
		if isEventSong(child) then
			useEventMusic(child)
		end
	end)
	SoundService.ChildRemoved:Connect(function(child)
		if child == eventMusic then
			eventMusic = nil
			syncedEventMusic = nil
			apply()
		end
	end)

	if ClientState.settingsReceived then
		apply()
	end
	ClientState.SettingsChanged:Connect(apply)
end

return MusicController

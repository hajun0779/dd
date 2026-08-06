--!nonstrict

--[[
	하루와 이벤트.

	서버 하나가 시계를 돌리고 모두가 같은 시간을 본다.
	Lighting 은 자동으로 복제되므로 시간 자체는 리모트가 필요 없다.
]]
local WorldConfig = {}

--[[
	하루 길이.

	낮이 밤보다 훨씬 길다. 밤은 분위기를 바꾸는 양념이지
	플레이를 방해하는 벌이 되면 안 된다.
]]
WorldConfig.Day = {
	DayMinutes = 12,
	NightMinutes = 4,

	--- 게임 속 시각 기준 (24시간)
	SunriseHour = 6,
	SunsetHour = 18,

	--- 밤에는 훔치기가 더 잘 보이지 않는다. 도둑에게 유리한 시간.
	NightStealBonus = 1.25,
}

--[[
	이벤트.

	일정 시간마다 하나씩 열린다. 무엇이 열릴지는 가중치로 뽑는다.

	  Income  그동안 수입 배율
	  Luck    알에서 좋은 게 나올 확률 배율
	  Growth  먹이 효율 배율
]]
WorldConfig.Events = {
	IntervalSeconds = 600,
	FirstDelaySeconds = 120,

	--[[
		타코 파티 노래.

		ServerStorage 에 넣어 둔 Sound 가 있어도 이 ID 로 덮어쓴다.
		맵마다 다른 노래가 나오면 "그 노래" 가 아니게 된다.
		비워 두면 맵에 있는 Sound 를 그대로 쓴다.
	]]
	TacoSongId = "rbxassetid://142376088",
	TacoSongVolume = 0.5,

	List = {
		{
			Id = "Taco",
			LocaleKey = "event_taco",
			Icon = "icon_fruit",
			Color = Color3.fromRGB(255, 176, 70),
			Seconds = 180,
			Weight = 100,
			Income = 2,
		},
		{
			Id = "Meteor",
			LocaleKey = "event_meteor",
			Icon = "icon_star",
			Color = Color3.fromRGB(160, 140, 255),
			Seconds = 150,
			Weight = 70,
			Luck = 2.5,
		},
		{
			Id = "Feast",
			LocaleKey = "event_feast",
			Icon = "icon_egg",
			Color = Color3.fromRGB(140, 230, 140),
			Seconds = 240,
			Weight = 80,
			Growth = 3,
		},
		{
			Id = "GoldRush",
			LocaleKey = "event_goldrush",
			Icon = "icon_money",
			Color = Color3.fromRGB(255, 214, 80),
			Seconds = 120,
			Weight = 40,
			Income = 4,
		},
		{
			Id = "Blackout",
			LocaleKey = "event_blackout",
			Icon = "icon_siren",
			Color = Color3.fromRGB(120, 140, 200),
			Seconds = 120,
			Weight = 25,
			Income = 1,
			OpensDoors = true,
		},
	},
}

function WorldConfig.event(id: string)
	for _, event in ipairs(WorldConfig.Events.List) do
		if event.Id == id then
			return event
		end
	end
	return nil
end

--- 하루 한 바퀴에 걸리는 실제 시간(초)
function WorldConfig.cycleSeconds(): number
	return (WorldConfig.Day.DayMinutes + WorldConfig.Day.NightMinutes) * 60
end

--[[
	지금이 하루 중 몇 시인지 (0 ~ 24).

	낮과 밤에 쓰는 실제 시간이 다르므로 단순 비례가 아니다.
	낮 구간을 길게 늘리고 밤 구간을 압축한다.
]]
function WorldConfig.clockAt(elapsed: number): (number, boolean)
	local D = WorldConfig.Day
	local daySeconds = D.DayMinutes * 60
	local nightSeconds = D.NightMinutes * 60
	local total = daySeconds + nightSeconds

	local t = elapsed % total
	local dayHours = D.SunsetHour - D.SunriseHour
	local nightHours = 24 - dayHours

	if t < daySeconds then
		return D.SunriseHour + (t / daySeconds) * dayHours, false
	end

	local nightT = (t - daySeconds) / nightSeconds
	return (D.SunsetHour + nightT * nightHours) % 24, true
end

function WorldConfig.formatClock(hour: number): string
	local h = math.floor(hour) % 24
	local m = math.floor((hour % 1) * 60)
	return ("%02d:%02d"):format(h, m)
end

return WorldConfig

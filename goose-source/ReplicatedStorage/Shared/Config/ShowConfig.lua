--!nonstrict

--[[
	연출(Show).

	관리자가 직접 켜는 맵 전체 이벤트다. 타코 파티처럼 정해진 시간에 도는 게
	아니라, 원할 때 골라서 튼다.

	기존 이벤트 연출이 전부 비슷해 보였던 이유는 건드리는 곳이 하나였기 때문이다.
	전부 "하늘 색 바꾸고 화면 번쩍" 이었다.

	그래서 연출 하나를 다섯 축으로 쪼갰고, 열 가지가 서로 다른 축을 주력으로 쓴다.

	  Sky     하늘·안개·밝기            느리고 넓게 바뀌는 것
	  Grade   블룸·대비·채도·틴트       화면의 "재질" 을 바꾸는 것
	  Camera  흔들림·펀치·기울기        몸으로 느끼는 것
	  Screen  화면에 그리는 것          비·번개·꽃잎·금화처럼 눈앞을 지나가는 것
	  World   맵에 실제로 놓는 것       운석·균열·스포트라이트처럼 가서 볼 수 있는 것

	  오로라   Sky 주력, 카메라 안 흔듦, 조용함
	  폭풍우   Screen 주력(비+번개), Sky 어둡게, 불규칙한 섬광
	  유성우   World 주력(진짜 떨어짐), 착탄마다 흔들림
	  벚꽃     Screen 주력, 카메라 정지, 채도만 올림
	  디스코   Grade 주력(색이 계속 순환), World 스포트라이트
	  혹한     Sky+Screen(성에), 화면 가장자리가 얼어붙음
	  균열     World 주력(바닥이 갈라짐), 카메라 계속 진동
	  황금비   Screen 주력(금화), 틴트만 노랗게
	  성운     Sky 주력(밤하늘), 별이 회전
	  타코     Grade 주력 + 노래, 색종이

	숫자는 전부 여기에만 있다. ShowService 와 ShowClient 는 이 표를 읽기만 한다.
]]
local ShowConfig = {}

--[[
	화면이 너무 밝다는 말이 계속 나와서 기준을 여기 하나로 모았다.

	연출이 끝나면 Lighting 은 반드시 이 값으로 돌아온다.
	place 에 저장된 값으로 돌아가지 않는다 — 그 값이 밝음의 원인이기 때문이다.
]]
ShowConfig.BaseLighting = {
	Brightness = 1.35,
	ExposureCompensation = -0.15,
	Ambient = Color3.fromRGB(68, 72, 86),
	OutdoorAmbient = Color3.fromRGB(94, 100, 116),
	EnvironmentDiffuseScale = 0.55,
	EnvironmentSpecularScale = 0.35,
	FogColor = Color3.fromRGB(148, 166, 194),
	FogStart = 220,
	FogEnd = 1400,
}

--- 연출이 끝날 때 화면 보정을 되돌릴 값
ShowConfig.BaseGrade = {
	Bloom = 0.18,
	BloomSize = 24,
	BloomThreshold = 0.94,
	Contrast = 0,
	Saturation = 0,
	Brightness = 0,
	Tint = Color3.fromRGB(255, 255, 255),
}

ShowConfig.DefaultSeconds = 75
ShowConfig.FadeSeconds = 2.5

--- 한 서버에서 동시에 도는 연출은 하나뿐이다
ShowConfig.MaxConcurrent = 1

ShowConfig.List = {
	--------------------------------------------------------------------
	{
		Id = "Aurora",
		LocaleKey = "show_aurora",
		Icon = "icon_star",
		Palette = "cyan",
		Seconds = 90,
		Sound = { Id = "", Volume = 0.3 },

		Sky = {
			ClockTime = 23.2,
			Brightness = 0.55,
			ExposureCompensation = -0.05,
			Ambient = Color3.fromRGB(28, 46, 62),
			OutdoorAmbient = Color3.fromRGB(34, 58, 78),
			FogColor = Color3.fromRGB(18, 40, 56),
			FogStart = 180,
			FogEnd = 1600,
		},
		Grade = {
			Bloom = 0.55,
			BloomSize = 56,
			BloomThreshold = 0.8,
			Contrast = 0.06,
			Saturation = 0.3,
			Tint = Color3.fromRGB(206, 236, 255),
		},
		Camera = { Shake = 0, Punch = 0, Sway = 0.35 },
		Screen = {
			Kind = "curtain",
			Colors = {
				Color3.fromRGB(96, 255, 196),
				Color3.fromRGB(120, 176, 255),
				Color3.fromRGB(196, 128, 255),
			},
			Bands = 7,
			Speed = 0.12,
			Height = 0.62,
			Alpha = 0.72,
		},
		World = { Kind = "orbit", Count = 6, Color = Color3.fromRGB(120, 255, 210), Radius = 260, Height = 170 },
	},

	--------------------------------------------------------------------
	{
		Id = "Storm",
		LocaleKey = "show_storm",
		Icon = "icon_bolt",
		Palette = "blue",
		Seconds = 80,
		Sound = { Id = "", Volume = 0.4 },

		Sky = {
			ClockTime = 16.4,
			Brightness = 0.42,
			ExposureCompensation = -0.3,
			Ambient = Color3.fromRGB(30, 34, 44),
			OutdoorAmbient = Color3.fromRGB(46, 52, 66),
			FogColor = Color3.fromRGB(44, 52, 66),
			FogStart = 60,
			FogEnd = 620,
		},
		Grade = {
			Bloom = 0.3,
			BloomSize = 30,
			BloomThreshold = 0.9,
			Contrast = 0.22,
			Saturation = -0.4,
			Tint = Color3.fromRGB(198, 214, 240),
		},
		Camera = { Shake = 0.22, ShakeSeconds = 0.7, Punch = 0, Sway = 0 },
		Screen = {
			Kind = "lightning",
			Color = Color3.fromRGB(226, 238, 255),
			-- 번개 사이 간격. 규칙적이면 금방 지겨워진다.
			MinGap = 1.4,
			MaxGap = 5.2,
			Forks = 4,
		},
		World = { Kind = "rain", Rate = 260, Color = Color3.fromRGB(180, 200, 230), Speed = 190 },
	},

	--------------------------------------------------------------------
	{
		Id = "Meteor",
		LocaleKey = "show_meteor",
		Icon = "icon_fire",
		Palette = "orange",
		Seconds = 70,
		Sound = { Id = "", Volume = 0.35 },

		Sky = {
			ClockTime = 21.4,
			Brightness = 0.6,
			ExposureCompensation = -0.1,
			Ambient = Color3.fromRGB(38, 30, 44),
			OutdoorAmbient = Color3.fromRGB(52, 42, 60),
			FogColor = Color3.fromRGB(48, 30, 40),
			FogStart = 140,
			FogEnd = 1200,
		},
		Grade = {
			Bloom = 0.6,
			BloomSize = 46,
			BloomThreshold = 0.82,
			Contrast = 0.14,
			Saturation = 0.1,
			Tint = Color3.fromRGB(255, 210, 176),
		},
		Camera = { Shake = 0, Punch = 0, Sway = 0 },
		Screen = {
			Kind = "streaks",
			Color = Color3.fromRGB(255, 208, 140),
			Rate = 2.2,
			Angle = 28,
		},
		--[[
			이건 화면 그림이 아니라 진짜 파트가 떨어진다.
			착탄 지점에 가 볼 수 있어야 "일어났다" 는 느낌이 든다.
		]]
		World = {
			Kind = "impact",
			Interval = 2.6,
			Radius = 320,
			Height = 520,
			FallSeconds = 1.1,
			Color = Color3.fromRGB(255, 150, 60),
			Shake = 0.5,
			ScorchSeconds = 6,
		},
	},

	--------------------------------------------------------------------
	{
		Id = "Sakura",
		LocaleKey = "show_sakura",
		Icon = "icon_fruit",
		Palette = "pink",
		Seconds = 110,
		Sound = { Id = "", Volume = 0.28 },

		Sky = {
			ClockTime = 7.6,
			Brightness = 1.1,
			ExposureCompensation = -0.05,
			Ambient = Color3.fromRGB(92, 74, 84),
			OutdoorAmbient = Color3.fromRGB(126, 104, 116),
			FogColor = Color3.fromRGB(236, 198, 214),
			FogStart = 260,
			FogEnd = 1500,
		},
		Grade = {
			Bloom = 0.34,
			BloomSize = 40,
			BloomThreshold = 0.88,
			Contrast = -0.04,
			Saturation = 0.34,
			Tint = Color3.fromRGB(255, 226, 236),
		},
		-- 조용한 연출이다. 카메라를 흔들면 분위기가 통째로 깨진다.
		Camera = { Shake = 0, Punch = 0, Sway = 0.2 },
		Screen = {
			Kind = "petals",
			Colors = {
				Color3.fromRGB(255, 196, 216),
				Color3.fromRGB(255, 222, 236),
				Color3.fromRGB(246, 168, 200),
			},
			Rate = 9,
			Drift = 130,
		},
		World = { Kind = "fall", Rate = 90, Color = Color3.fromRGB(255, 196, 220), Size = 3.4, Speed = 14 },
	},

	--------------------------------------------------------------------
	{
		Id = "Disco",
		LocaleKey = "show_disco",
		Icon = "icon_music",
		Palette = "purple",
		Seconds = 90,
		Sound = { Id = "", Volume = 0.45 },

		Sky = {
			ClockTime = 0.6,
			Brightness = 0.34,
			ExposureCompensation = -0.2,
			Ambient = Color3.fromRGB(22, 18, 34),
			OutdoorAmbient = Color3.fromRGB(30, 24, 46),
			FogColor = Color3.fromRGB(26, 16, 44),
			FogStart = 90,
			FogEnd = 700,
		},
		--[[
			이 연출만 Grade 가 고정값이 아니다.
			ShowClient 가 Cycle 색을 돌려 가며 틴트를 계속 바꾼다.
		]]
		Grade = {
			Bloom = 0.7,
			BloomSize = 52,
			BloomThreshold = 0.76,
			Contrast = 0.2,
			Saturation = 0.5,
			Tint = Color3.fromRGB(255, 255, 255),
			Cycle = {
				Color3.fromRGB(255, 120, 190),
				Color3.fromRGB(130, 160, 255),
				Color3.fromRGB(140, 255, 190),
				Color3.fromRGB(255, 224, 120),
			},
			CycleSeconds = 1.1,
		},
		Camera = { Shake = 0.06, ShakeSeconds = 0.4, Punch = 0, Sway = 0.5 },
		Screen = { Kind = "disco", Rays = 10, Speed = 0.5, Alpha = 0.86 },
		World = { Kind = "spotlights", Count = 8, Radius = 190, Height = 90, Speed = 0.35 },
	},

	--------------------------------------------------------------------
	{
		Id = "Frost",
		LocaleKey = "show_frost",
		Icon = "icon_snow",
		Palette = "cyan",
		Seconds = 85,
		Sound = { Id = "", Volume = 0.3 },

		Sky = {
			ClockTime = 15.2,
			Brightness = 0.72,
			ExposureCompensation = -0.12,
			Ambient = Color3.fromRGB(58, 74, 88),
			OutdoorAmbient = Color3.fromRGB(92, 116, 136),
			FogColor = Color3.fromRGB(198, 220, 238),
			FogStart = 40,
			FogEnd = 420,
		},
		Grade = {
			Bloom = 0.4,
			BloomSize = 44,
			BloomThreshold = 0.84,
			Contrast = 0.05,
			Saturation = -0.55,
			Tint = Color3.fromRGB(196, 226, 255),
		},
		Camera = { Shake = 0.04, ShakeSeconds = 1.4, Punch = 0, Sway = 0.15 },
		--[[
			화면 가장자리부터 안쪽으로 성에가 자란다.
			가운데를 막지 않아야 플레이가 가능하다.
		]]
		Screen = {
			Kind = "frost",
			Color = Color3.fromRGB(214, 240, 255),
			Crystals = 26,
			GrowSeconds = 14,
			MaxAlpha = 0.55,
		},
		World = { Kind = "fall", Rate = 220, Color = Color3.fromRGB(235, 246, 255), Size = 2.2, Speed = 26 },
	},

	--------------------------------------------------------------------
	{
		Id = "Rift",
		LocaleKey = "show_rift",
		Icon = "icon_warning",
		Palette = "red",
		Seconds = 70,
		Sound = { Id = "", Volume = 0.4 },

		Sky = {
			ClockTime = 18.6,
			Brightness = 0.5,
			ExposureCompensation = -0.25,
			Ambient = Color3.fromRGB(52, 20, 18),
			OutdoorAmbient = Color3.fromRGB(66, 26, 22),
			FogColor = Color3.fromRGB(60, 16, 10),
			FogStart = 70,
			FogEnd = 560,
		},
		Grade = {
			Bloom = 0.5,
			BloomSize = 38,
			BloomThreshold = 0.86,
			Contrast = 0.26,
			Saturation = 0.18,
			Tint = Color3.fromRGB(255, 176, 150),
		},
		-- 끊기지 않고 계속 낮게 우는 진동. 이 연출의 정체성이다.
		Camera = { Shake = 0.12, ShakeSeconds = 999, Punch = 0, Sway = 0 },
		Screen = {
			Kind = "pulse",
			Color = Color3.fromRGB(255, 92, 48),
			Period = 1.6,
			MaxAlpha = 0.42,
		},
		World = {
			Kind = "cracks",
			Count = 14,
			Radius = 240,
			Color = Color3.fromRGB(255, 108, 40),
			Length = 46,
			Width = 5,
			GrowSeconds = 3,
		},
	},

	--------------------------------------------------------------------
	{
		Id = "GoldRain",
		LocaleKey = "show_goldrain",
		Icon = "icon_money",
		Palette = "yellow",
		Seconds = 60,
		Sound = { Id = "", Volume = 0.35 },

		Sky = {
			ClockTime = 12.6,
			Brightness = 1.15,
			ExposureCompensation = -0.05,
			Ambient = Color3.fromRGB(96, 84, 52),
			OutdoorAmbient = Color3.fromRGB(132, 116, 72),
			FogColor = Color3.fromRGB(246, 224, 160),
			FogStart = 240,
			FogEnd = 1400,
		},
		Grade = {
			Bloom = 0.66,
			BloomSize = 50,
			BloomThreshold = 0.8,
			Contrast = 0.1,
			Saturation = 0.24,
			Tint = Color3.fromRGB(255, 234, 168),
		},
		Camera = { Shake = 0, Punch = 0.06, Sway = 0 },
		Screen = {
			Kind = "coins",
			Color = Color3.fromRGB(255, 212, 84),
			Rate = 14,
			Spin = 220,
		},
		World = { Kind = "fall", Rate = 140, Color = Color3.fromRGB(255, 214, 90), Size = 2.8, Speed = 44 },
	},

	--------------------------------------------------------------------
	{
		Id = "Nebula",
		LocaleKey = "show_nebula",
		Icon = "icon_globe",
		Palette = "purple",
		Seconds = 100,
		Sound = { Id = "", Volume = 0.3 },

		Sky = {
			ClockTime = 0,
			Brightness = 0.38,
			ExposureCompensation = 0,
			Ambient = Color3.fromRGB(30, 24, 52),
			OutdoorAmbient = Color3.fromRGB(38, 30, 66),
			FogColor = Color3.fromRGB(22, 14, 44),
			FogStart = 200,
			FogEnd = 2000,
		},
		Grade = {
			Bloom = 0.62,
			BloomSize = 60,
			BloomThreshold = 0.78,
			Contrast = 0.16,
			Saturation = 0.28,
			Tint = Color3.fromRGB(206, 190, 255),
		},
		Camera = { Shake = 0, Punch = 0, Sway = 0.6 },
		Screen = {
			Kind = "stars",
			Colors = {
				Color3.fromRGB(255, 255, 255),
				Color3.fromRGB(186, 196, 255),
				Color3.fromRGB(255, 190, 226),
			},
			Count = 130,
			Speed = 0.045,
		},
		World = { Kind = "orbit", Count = 10, Color = Color3.fromRGB(178, 150, 255), Radius = 300, Height = 220 },
	},

	--------------------------------------------------------------------
	{
		Id = "Taco",
		LocaleKey = "show_taco",
		Icon = "icon_fruit",
		Palette = "orange",
		Seconds = 120,
		--- 타코 파티 노래
		Sound = { Id = "rbxassetid://142376088", Volume = 0.5, Looped = true },

		Sky = {
			ClockTime = 14.2,
			Brightness = 1.0,
			ExposureCompensation = -0.08,
			Ambient = Color3.fromRGB(92, 70, 48),
			OutdoorAmbient = Color3.fromRGB(126, 98, 66),
			FogColor = Color3.fromRGB(255, 206, 150),
			FogStart = 200,
			FogEnd = 1300,
		},
		Grade = {
			Bloom = 0.45,
			BloomSize = 42,
			BloomThreshold = 0.85,
			Contrast = 0.12,
			Saturation = 0.4,
			Tint = Color3.fromRGB(255, 220, 176),
			Cycle = {
				Color3.fromRGB(255, 220, 176),
				Color3.fromRGB(255, 196, 140),
				Color3.fromRGB(255, 236, 200),
			},
			CycleSeconds = 2.4,
		},
		Camera = { Shake = 0.05, ShakeSeconds = 0.5, Punch = 0, Sway = 0.4 },
		Screen = {
			Kind = "confetti",
			Colors = {
				Color3.fromRGB(255, 176, 70),
				Color3.fromRGB(255, 106, 96),
				Color3.fromRGB(120, 224, 140),
				Color3.fromRGB(120, 180, 255),
			},
			Rate = 22,
		},
		World = { Kind = "spotlights", Count = 5, Radius = 150, Height = 70, Speed = 0.22 },
	},
}

ShowConfig.Index = {}
for order, show in ipairs(ShowConfig.List) do
	show.Order = order
	ShowConfig.Index[show.Id] = show
	ShowConfig.Index[string.lower(show.Id)] = show
end

--- 대소문자를 가리지 않는다. 관리자 패널에 손으로 치는 값이라서다.
function ShowConfig.get(id: string?)
	if type(id) ~= "string" then
		return nil
	end
	return ShowConfig.Index[id] or ShowConfig.Index[string.lower(id)]
end

function ShowConfig.ids(): { string }
	local out = table.create(#ShowConfig.List)
	for index, show in ipairs(ShowConfig.List) do
		out[index] = show.Id
	end
	return out
end

function ShowConfig.seconds(show, override: number?): number
	local requested = tonumber(override) or 0
	if requested > 0 then
		return math.clamp(requested, 5, 900)
	end
	return math.clamp(tonumber(show and show.Seconds) or ShowConfig.DefaultSeconds, 5, 900)
end

return ShowConfig

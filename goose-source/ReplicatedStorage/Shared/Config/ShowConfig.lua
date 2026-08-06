--!nonstrict

--[[
	연출(Show).

	관리자가 직접 켜는 맵 전체 이벤트다. 타코 파티처럼 정해진 시간에 도는 게
	아니라, 원할 때 골라서 튼다.

	전부 3D 다. 화면에 그림을 덧대지 않는다.

	처음에는 꽃잎·금화·번개를 화면 위에 사각형으로 그렸는데, 그러면 월드에서
	일어나는 일이 아니라 화면에 씌운 필터로 보인다. 원근도 없고 건물 뒤로
	가려지지도 않아서, 고개를 돌려도 똑같은 게 똑같은 자리에 붙어 있다.

	그래서 두 가지로만 만든다.

	  Local   내 카메라를 따라다니는 3D 방출기.
	          비·눈·꽃잎·금화·불티가 여기서 나온다. 이 화면에만 있고 복제되지 않는다.
	          카메라 밑에 두므로 서버는 아무것도 모른다.

	  World   서버가 맵에 놓는 3D 물체.
	          운석·균열·조명·오로라 커튼처럼 "가서 볼 수 있는" 것.
	          모두가 같은 것을 본다.

	나머지 세 축은 3D 장면 자체를 바꾸는 것이라 그대로 둔다.

	  Sky     하늘·안개·밝기
	  Grade   블룸·대비·채도 (렌더된 3D 화면을 보정하는 것이지 덧그리는 게 아니다)
	  Camera  흔들림·기울기
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

--[[
	내 주변 3D 방출기의 기본값.

	Kind    fall 위에서 떨어짐 / rise 아래에서 솟음 / swirl 주변을 떠다님
	Spread  방출판 한 변의 길이(스터드). 넓을수록 시야를 채우지만 밀도가 준다.
	Height  카메라에서 위/아래로 얼마나 떨어뜨릴지
]]
ShowConfig.LocalDefaults = {
	Kind = "fall",
	Texture = "Glow",
	Rate = 80,
	Size = 2,
	Speed = 30,
	Lifetime = 4,
	Spread = 90,
	Height = 40,
	Drag = 0,
	Spin = 60,
	SpreadAngle = 12,
	LightEmission = 0.4,
	Transparency = 0.15,
	Squash = 0,
}

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

		--- 발밑에서 천천히 솟아오르는 빛가루
		Local = {
			Kind = "rise",
			Texture = "Glow",
			Colors = {
				Color3.fromRGB(96, 255, 196),
				Color3.fromRGB(120, 176, 255),
				Color3.fromRGB(196, 128, 255),
			},
			Rate = 34,
			Size = 3.2,
			Speed = 9,
			Lifetime = 7,
			Spread = 110,
			Height = -14,
			Drag = 1.4,
			SpreadAngle = 26,
			LightEmission = 1,
			Transparency = 0.5,
		},
		--- 하늘 높이 걸린 진짜 3D 오로라 커튼
		World = {
			Kind = "aurora",
			Curtains = 5,
			Colors = {
				Color3.fromRGB(96, 255, 196),
				Color3.fromRGB(120, 176, 255),
				Color3.fromRGB(196, 128, 255),
			},
			Radius = 420,
			Height = 320,
			Width = 190,
			Length = 620,
		},
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

		--- 빗줄기. 길쭉하게 눌러야 방울이 아니라 줄기로 보인다.
		Local = {
			Kind = "fall",
			Texture = "Shard",
			Colors = { Color3.fromRGB(180, 200, 230) },
			Rate = 340,
			Size = 1.6,
			Speed = 110,
			Lifetime = 1.4,
			Spread = 70,
			Height = 55,
			SpreadAngle = 5,
			Squash = 2.4,
			LightEmission = 0.2,
			Transparency = 0.35,
			Spin = 0,

			--[[
				3D 번개.

				하늘에 실제 파트로 갈래를 세우고, 그 끝에 빛을 달아
				주변 지형이 실제로 밝아지게 한다. 화면을 하얗게 덮는 것과는 다르다.
			]]
			Lightning = {
				MinGap = 1.6,
				MaxGap = 5.4,
				Forks = 6,
				Distance = 240,
				Height = 340,
				Thickness = 3.4,
				Color = Color3.fromRGB(226, 238, 255),
				Brightness = 8,
				FlashSeconds = 0.28,
			},
		},
		World = { Kind = "none" },
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

		--- 멀리 하늘을 비스듬히 긋고 지나가는 잔별
		Local = {
			Kind = "fall",
			Texture = "Spark",
			Colors = { Color3.fromRGB(255, 208, 140), Color3.fromRGB(255, 246, 210) },
			Rate = 26,
			Size = 2.4,
			Speed = 140,
			Lifetime = 2.2,
			Spread = 220,
			Height = 150,
			SpreadAngle = 8,
			Squash = 3.2,
			LightEmission = 1,
			Transparency = 0.1,
			Spin = 0,
			Tilt = 34,
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

		--[[
			꽃잎.

			Drag 를 크게 잡는 게 핵심이다. 저항이 없으면 그냥 떨어지는 점이 되고,
			저항이 있어야 공중에서 머뭇거리며 흩날린다.
		]]
		Local = {
			Kind = "fall",
			Texture = "Glow",
			Colors = {
				Color3.fromRGB(255, 196, 216),
				Color3.fromRGB(255, 222, 236),
				Color3.fromRGB(246, 168, 200),
			},
			Rate = 90,
			Size = 1.5,
			Speed = 12,
			Lifetime = 9,
			Spread = 100,
			Height = 45,
			Drag = 2.2,
			SpreadAngle = 45,
			Spin = 180,
			LightEmission = 0.3,
			Transparency = 0.1,
			Wind = 14,
		},
		World = { Kind = "none" },
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

		--- 바닥에서 떠오르는 색 빛알
		Local = {
			Kind = "rise",
			Texture = "Spark",
			Colors = {
				Color3.fromRGB(255, 96, 170),
				Color3.fromRGB(110, 170, 255),
				Color3.fromRGB(120, 255, 180),
				Color3.fromRGB(255, 226, 110),
			},
			Rate = 60,
			Size = 1.4,
			Speed = 16,
			Lifetime = 4.5,
			Spread = 70,
			Height = -10,
			Drag = 0.8,
			SpreadAngle = 34,
			LightEmission = 1,
			Transparency = 0.1,
		},
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
			--- 눈보라는 안개가 짙어야 눈이 실제로 시야를 가리는 느낌이 난다
			FogStart = 30,
			FogEnd = 320,
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

		--- 옆에서 들이치는 눈보라
		Local = {
			Kind = "fall",
			Texture = "Glow",
			Colors = { Color3.fromRGB(235, 246, 255), Color3.fromRGB(206, 230, 250) },
			Rate = 260,
			Size = 1.1,
			Speed = 34,
			Lifetime = 3.4,
			Spread = 80,
			Height = 40,
			Drag = 0.6,
			SpreadAngle = 30,
			Spin = 90,
			LightEmission = 0.6,
			Transparency = 0.2,
			Wind = 42,
		},
		World = { Kind = "none" },
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

		--- 발밑에서 솟는 불티
		Local = {
			Kind = "rise",
			Texture = "Ember",
			Colors = { Color3.fromRGB(255, 108, 40), Color3.fromRGB(255, 196, 110) },
			Rate = 110,
			Size = 1.6,
			Speed = 22,
			Lifetime = 5,
			Spread = 90,
			Height = -12,
			Drag = 1.1,
			SpreadAngle = 30,
			LightEmission = 1,
			Transparency = 0.1,
			Spin = 120,
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

		--- 빙글빙글 돌며 떨어지는 금화
		Local = {
			Kind = "fall",
			Texture = "Ring",
			Colors = { Color3.fromRGB(255, 212, 84), Color3.fromRGB(255, 246, 190) },
			Rate = 130,
			Size = 1.8,
			Speed = 44,
			Lifetime = 3.2,
			Spread = 85,
			Height = 45,
			Drag = 0.4,
			SpreadAngle = 16,
			Spin = 420,
			LightEmission = 0.9,
			Transparency = 0.05,
		},
		World = { Kind = "none" },
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

		--- 주변을 아주 느리게 떠다니는 별가루
		Local = {
			Kind = "swirl",
			Texture = "Spark",
			Colors = {
				Color3.fromRGB(255, 255, 255),
				Color3.fromRGB(186, 196, 255),
				Color3.fromRGB(255, 190, 226),
			},
			Rate = 70,
			Size = 0.9,
			Speed = 3,
			Lifetime = 12,
			Spread = 120,
			Height = 6,
			Drag = 0.4,
			SpreadAngle = 180,
			LightEmission = 1,
			Transparency = 0.15,
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

		--- 쏟아지는 색종이
		Local = {
			Kind = "fall",
			Texture = "Shard",
			Colors = {
				Color3.fromRGB(255, 176, 70),
				Color3.fromRGB(255, 106, 96),
				Color3.fromRGB(120, 224, 140),
				Color3.fromRGB(120, 180, 255),
			},
			Rate = 200,
			Size = 1.3,
			Speed = 26,
			Lifetime = 5,
			Spread = 90,
			Height = 42,
			Drag = 1.6,
			SpreadAngle = 40,
			Spin = 540,
			LightEmission = 0.2,
			Transparency = 0.05,
			Wind = 18,
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

--- 비어 있는 값은 기본값으로 메운다
function ShowConfig.localSpec(show)
	local spec = show and show.Local
	if type(spec) ~= "table" then
		return nil
	end
	local out = {}
	for key, value in pairs(ShowConfig.LocalDefaults) do
		out[key] = value
	end
	for key, value in pairs(spec) do
		out[key] = value
	end
	return out
end

return ShowConfig

--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RarityConfig = require(ReplicatedStorage.Shared.Config.RarityConfig)

local EggConfig = {}

EggConfig.Order = {
	"Basic",
	"Forest",
	"Frost",
	"Meadow",
	"Neon",
	"Ocean",
	"Storm",
	"Desert",
	"Void",
	"Cosmic",
	"Aurora",
	"Time",
	"Inferno",
	"Celestial",
	"Sakura",
	"Arcane",
	"CyberNova",
	"Dragon",
	"Dream",
	"Royal",
	"Chaos",
	"Genesis",
	"Summer",
	"Candy",
	"Exclusive",
}

--[[
	알을 눈으로 구분하는 두 값.

	  Glyph    화면 아이콘 위에 얹는 기호. RadAtlas 스프라이트 이름.
	  Pattern  3D 모델 껍데기에 새기는 무늬.
	           spots 점 · stripes 띠 · rings 고리 · shards 파편 · swirl 소용돌이 · crown 왕관

	색(Color/Accent)만으로는 스물여섯 종을 못 나눈다. 비슷한 파랑이 넷이라
	가방에서는 결국 같은 알로 보인다. 기호와 무늬가 그 구분을 맡는다.
]]
EggConfig.Data = {
	Basic = {
		Id = "Basic",
		Glyph = "icon_dots",
		Pattern = "spots",
		Color = Color3.fromRGB(245, 240, 228),
		Accent = Color3.fromRGB(214, 200, 176),
		RequiredRebirth = 0,
		LocaleKey = "egg_basic",
		ModelName = "BasicEgg",
		Price = 250,
		Currency = "Cash",
		Icon = "egg_basic",
		HatchTimeHint = 8,
		RarityWeights = {
			Common = 82000,
			Rare = 15500,
			Epic = 2300,
			Legendary = 190,
			Unknown = 9,
			LegendMoment = 1,
		},
		Geese = {
			Common = { "GooseWhite", "GooseYellow" },
			Rare = { "GooseMallard", "GooseBlue" },
			Epic = { "GoosePunk", "GooseChef" },
			Legendary = { "GooseKing" },
			Unknown = { "GooseVoid" },
			LegendMoment = { "GooseLegend" },
		},
	},

	Frost = {
		Id = "Frost",
		Glyph = "icon_snow",
		Pattern = "shards",
		Color = Color3.fromRGB(222, 240, 252),
		Accent = Color3.fromRGB(150, 198, 232),
		RequiredRebirth = 1,
		LocaleKey = "egg_frost",
		ModelName = "FrostEgg",
		Price = 25000,
		Currency = "Cash",
		Icon = "egg_frost",
		HatchTimeHint = 11,
		RarityWeights = {
			Common = 64000,
			Rare = 27000,
			Epic = 8000,
			Legendary = 920,
			Unknown = 76,
			LegendMoment = 4,
		},
		Geese = {
			Common = { "GooseSnow", "GooseWhite" },
			Rare = { "GooseFrost", "GooseBlue" },
			Epic = { "GooseNinja", "GooseCyber" },
			Legendary = { "GooseStorm", "GooseAncient" },
			Unknown = { "GooseNull" },
			LegendMoment = { "GooseLegend" },
		},
	},

	Neon = {
		Id = "Neon",
		Glyph = "icon_bolt",
		Pattern = "stripes",
		Color = Color3.fromRGB(60, 66, 96),
		Accent = Color3.fromRGB(120, 240, 255),
		RequiredRebirth = 2,
		LocaleKey = "egg_neon",
		ModelName = "NeonEgg",
		Price = 150000,
		Currency = "Cash",
		Icon = "egg_neon",
		HatchTimeHint = 13,
		RarityWeights = {
			Common = 52000,
			Rare = 32000,
			Epic = 13500,
			Legendary = 2300,
			Unknown = 190,
			LegendMoment = 10,
		},
		Geese = {
			Common = { "GooseDusk" },
			Rare = { "GooseCandy", "GooseEmber" },
			Epic = { "GooseCyber", "GoosePunk", "GooseCoral" },
			Legendary = { "GoosePhantom", "GooseSun" },
			Unknown = { "GooseNull", "GooseGlitch" },
			LegendMoment = { "GooseCosmos" },
		},
	},

	Storm = {
		Id = "Storm",
		Glyph = "icon_siren",
		Pattern = "swirl",
		Color = Color3.fromRGB(118, 128, 150),
		Accent = Color3.fromRGB(236, 226, 120),
		RequiredRebirth = 3,
		LocaleKey = "egg_storm",
		ModelName = "StormEgg",
		Price = 800000,
		Currency = "Cash",
		Icon = "egg_storm",
		HatchTimeHint = 15,
		RarityWeights = {
			Common = 34000,
			Rare = 36000,
			Epic = 22000,
			Legendary = 7400,
			Unknown = 560,
			LegendMoment = 40,
		},
		Geese = {
			Common = { "GooseDusk" },
			Rare = { "GooseFrost" },
			Epic = { "GooseNinja", "GooseCyber" },
			Legendary = { "GooseStorm", "GooseMagma", "GoosePhantom" },
			Unknown = { "GooseAstral", "GooseNull" },
			LegendMoment = { "GooseCosmos" },
		},
	},

	Forest = {
		Id = "Forest",
		Glyph = "icon_luck",
		Pattern = "spots",
		Color = Color3.fromRGB(206, 226, 186),
		Accent = Color3.fromRGB(126, 168, 104),
		RequiredRebirth = 1,
		LocaleKey = "egg_forest",
		ModelName = "ForestEgg",
		Price = 5000,
		Currency = "Cash",
		Icon = "egg_forest",
		HatchTimeHint = 10,
		RarityWeights = {
			Common = 72000,
			Rare = 22000,
			Epic = 5300,
			Legendary = 660,
			Unknown = 38,
			LegendMoment = 2,
		},
		Geese = {
			Common = { "GooseYellow", "GooseLeaf" },
			Rare = { "GooseMallard", "GooseMoss" },
			Epic = { "GooseDruid", "GooseChef" },
			Legendary = { "GooseKing", "GooseAncient" },
			Unknown = { "GooseVoid" },
			LegendMoment = { "GooseLegend" },
		},
	},

	Meadow = {
		Id = "Meadow",
		Glyph = "icon_fruit",
		Pattern = "spots",
		Color = Color3.fromRGB(214, 238, 174),
		Accent = Color3.fromRGB(246, 190, 108),
		RequiredRebirth = 2,
		LocaleKey = "egg_meadow",
		ModelName = "MeadowEgg",
		Price = 75000,
		Currency = "Cash",
		Icon = "icon_egg",
		IsNew = true,
		HatchTimeHint = 12,
		RarityWeights = { Common = 58000, Rare = 27000, Epic = 12000, Legendary = 2700, Unknown = 285, LegendMoment = 15 },
		Geese = {
			Common = { "GooseDaisy" }, Rare = { "GooseBee" }, Epic = { "GooseFoxglove" },
			Legendary = { "GooseBloom" }, Unknown = { "GooseSpiritwood" }, LegendMoment = { "GooseGaia" },
		},
	},

	Ocean = {
		Id = "Ocean",
		Glyph = "icon_globe",
		Pattern = "rings",
		Color = Color3.fromRGB(98, 196, 232),
		Accent = Color3.fromRGB(72, 104, 202),
		RequiredRebirth = 3,
		LocaleKey = "egg_ocean",
		ModelName = "OceanEgg",
		Price = 650000,
		Currency = "Cash",
		Icon = "icon_egg",
		IsNew = true,
		HatchTimeHint = 15,
		RarityWeights = { Common = 43000, Rare = 30000, Epic = 19000, Legendary = 7200, Unknown = 750, LegendMoment = 50 },
		Geese = {
			Common = { "GoosePearl" }, Rare = { "GooseWave" }, Epic = { "GooseJelly" },
			Legendary = { "GooseTide" }, Unknown = { "GooseAbyss" }, LegendMoment = { "GooseLeviathan" },
		},
	},

	Desert = {
		Id = "Desert",
		Glyph = "icon_target",
		Pattern = "stripes",
		Color = Color3.fromRGB(226, 178, 106),
		Accent = Color3.fromRGB(60, 142, 142),
		RequiredRebirth = 4,
		LocaleKey = "egg_desert",
		ModelName = "DesertEgg",
		Price = 4000000,
		Currency = "Cash",
		Icon = "icon_egg",
		IsNew = true,
		HatchTimeHint = 18,
		RarityWeights = { Common = 28000, Rare = 30000, Epic = 26000, Legendary = 13500, Unknown = 2300, LegendMoment = 200 },
		Geese = {
			Common = { "GooseSand" }, Rare = { "GooseCactus" }, Epic = { "GooseScarab" },
			Legendary = { "GoosePharaoh" }, Unknown = { "GooseMirage" }, LegendMoment = { "GooseRa" },
		},
	},

	Aurora = {
		Id = "Aurora",
		Glyph = "icon_sound",
		Pattern = "swirl",
		Color = Color3.fromRGB(84, 126, 174),
		Accent = Color3.fromRGB(112, 255, 198),
		RequiredRebirth = 5,
		LocaleKey = "egg_aurora",
		ModelName = "AuroraEgg",
		Price = 25000000,
		Currency = "Cash",
		Icon = "icon_egg",
		IsNew = true,
		HatchTimeHint = 22,
		RarityWeights = { Common = 12000, Rare = 25000, Epic = 33000, Legendary = 24000, Unknown = 5500, LegendMoment = 500 },
		Geese = {
			Common = { "GooseMint" }, Rare = { "GoosePolar" }, Epic = { "GooseAurora" },
			Legendary = { "GooseComet" }, Unknown = { "GooseNebula" }, LegendMoment = { "GooseBorealis" },
		},
	},

	Time = {
		Id = "Time",
		Glyph = "icon_clock",
		Pattern = "rings",
		Color = Color3.fromRGB(96, 104, 132),
		Accent = Color3.fromRGB(246, 188, 78),
		RequiredRebirth = 6,
		LocaleKey = "egg_time",
		ModelName = "TimeEgg",
		Price = 120000000,
		Currency = "Cash",
		Icon = "icon_egg",
		IsNew = true,
		HatchTimeHint = 26,
		RarityWeights = { Common = 0, Rare = 12000, Epic = 32000, Legendary = 36000, Unknown = 17500, LegendMoment = 2500 },
		Geese = {
			Rare = { "GooseClockwork", "GooseGear" }, Epic = { "GooseChrono" },
			Legendary = { "GooseHourglass" }, Unknown = { "GooseParadox" }, LegendMoment = { "GooseEternity" },
		},
	},

	Summer = {
		Id = "Summer",
		Glyph = "shine_burst",
		Pattern = "stripes",
		Color = Color3.fromRGB(255, 226, 150),
		Accent = Color3.fromRGB(110, 208, 226),
		RequiredRebirth = 0,
		LocaleKey = "egg_summer",
		ModelName = "SummerEgg",
		Price = 799,
		Currency = "Robux",
		-- 반복 구매 알이므로 게임패스가 아니라 개발자 상품 ID를 넣는다.
		-- Creator Dashboard에서 상품을 만든 뒤 0을 실제 ID로 교체한다.
		ProductId = 0,
		Icon = "egg_summer",
		IsNew = true,
		HatchTimeHint = 12,
		RarityWeights = {
			Common = 48000,
			Rare = 34000,
			Epic = 15000,
			Legendary = 2800,
			Unknown = 190,
			LegendMoment = 10,
		},
		Geese = {
			Common = { "GooseSurf" },
			Rare = { "GooseBlue", "GooseSurf" },
			Epic = { "GooseTiki", "GoosePunk" },
			Legendary = { "GooseKing", "GooseSun" },
			Unknown = { "GooseVoid" },
			LegendMoment = { "GooseLegend" },
		},
	},

	Exclusive = {
		Id = "Exclusive",
		Glyph = "icon_vip",
		Pattern = "crown",
		Color = Color3.fromRGB(250, 238, 206),
		Accent = Color3.fromRGB(246, 190, 60),
		RequiredRebirth = 2,
		LocaleKey = "egg_exclusive",
		ModelName = "ExclusiveEgg",
		Price = 799,
		Currency = "Robux",
		-- 반복 구매 알이므로 게임패스가 아니라 개발자 상품 ID를 넣는다.
		-- Creator Dashboard에서 상품을 만든 뒤 0을 실제 ID로 교체한다.
		ProductId = 0,
		Icon = "egg_exclusive",
		IsNew = true,
		HatchTimeHint = 14,
		RarityWeights = {
			Common = 22000,
			Rare = 34000,
			Epic = 30000,
			Legendary = 12800,
			Unknown = 1120,
			LegendMoment = 80,
		},
		Geese = {
			Common = { "GooseWhite" },
			Rare = { "GooseBlue" },
			Epic = { "GoosePunk", "GooseTiki" },
			Legendary = { "GooseKing", "GooseSun", "GooseAncient" },
			Unknown = { "GooseVoid" },
			LegendMoment = { "GooseLegend" },
		},
	},

	Void = {
		Id = "Void",
		Glyph = "icon_close",
		Pattern = "shards",
		Color = Color3.fromRGB(54, 38, 82),
		Accent = Color3.fromRGB(158, 100, 246),
		RequiredRebirth = 4,
		LocaleKey = "egg_void",
		ModelName = "VoidEgg",
		Price = 2500000,
		Currency = "Cash",
		Icon = "egg_void",
		HatchTimeHint = 18,
		RarityWeights = {
			Common = 0,
			Rare = 40000,
			Epic = 38000,
			Legendary = 19700,
			Unknown = 2200,
			LegendMoment = 100,
		},
		Geese = {
			Rare = { "GooseMoss" },
			Epic = { "GooseDruid" },
			Legendary = { "GooseAncient", "GooseSun", "GoosePhantom" },
			Unknown = { "GooseVoid", "GooseNull", "GooseAstral" },
			LegendMoment = { "GooseLegend" },
		},
	},

	Cosmic = {
		Id = "Cosmic",
		Glyph = "icon_star",
		Pattern = "swirl",
		Color = Color3.fromRGB(34, 32, 70),
		Accent = Color3.fromRGB(255, 226, 140),
		RequiredRebirth = 5,
		LocaleKey = "egg_cosmic",
		ModelName = "CosmicEgg",
		Price = 12000000,
		Currency = "Cash",
		Icon = "egg_cosmic",
		HatchTimeHint = 22,
		RarityWeights = {
			Common = 0,
			Rare = 14000,
			Epic = 48000,
			Legendary = 33500,
			Unknown = 4300,
			LegendMoment = 200,
		},
		Geese = {
			Epic = { "GooseCyber", "GooseCoral" },
			Legendary = { "GooseMagma", "GoosePhantom", "GooseStorm" },
			Unknown = { "GooseAstral", "GooseGlitch", "GooseNull" },
			LegendMoment = { "GooseCosmos", "GooseOrigin" },
		},
	},

	Candy = {
		Id = "Candy",
		Glyph = "icon_gift",
		Pattern = "stripes",
		Color = Color3.fromRGB(255, 208, 228),
		Accent = Color3.fromRGB(246, 132, 182),
		RequiredRebirth = 0,
		LocaleKey = "egg_candy",
		ModelName = "CandyEgg",
		Price = 499,
		Currency = "Robux",
		-- 반복 구매 알이므로 게임패스가 아니라 개발자 상품 ID를 넣는다.
		-- Creator Dashboard에서 상품을 만든 뒤 0을 실제 ID로 교체한다.
		ProductId = 0,
		Icon = "egg_candy",
		IsNew = true,
		HatchTimeHint = 10,
		RarityWeights = {
			Common = 54000,
			Rare = 32000,
			Epic = 11500,
			Legendary = 2380,
			Unknown = 110,
			LegendMoment = 10,
		},
		Geese = {
			Common = { "GooseYellow", "GooseSnow" },
			Rare = { "GooseCandy", "GooseCoral" },
			Epic = { "GooseCoral", "GooseChef" },
			Legendary = { "GooseSun", "GoosePhantom" },
			Unknown = { "GooseAstral" },
			LegendMoment = { "GooseLegend" },
		},
	},

	-- 룰렛에서만 획득할 수 있으며 일반 알 상점에는 표시하지 않는다.
	Wheel = {
		Id = "Wheel",
		Glyph = "icon_spin",
		Pattern = "crown",
		Color = Color3.fromRGB(62, 52, 108),
		Accent = Color3.fromRGB(255, 202, 70),
		RequiredRebirth = 0,
		LocaleKey = "egg_wheel",
		ModelName = "WheelEgg",
		Price = 0,
		Currency = "Roulette",
		Icon = "egg_wheel",
		HatchTimeHint = 14,
		RarityWeights = {
			Common = 42000,
			Rare = 27000,
			Epic = 16000,
			Legendary = 9000,
			Unknown = 5000,
			LegendMoment = 1000,
		},
		Geese = {
			Common = { "GooseLucky" },
			Rare = { "GooseAzure" },
			Epic = { "GooseRuby" },
			Legendary = { "GooseCrown" },
			Unknown = { "GoosePrism" },
			LegendMoment = { "GooseEclipse" },
		},
	},
}

-- 7~10환생 후반 확장 알. 각 알은 전용 거위 6종을 한 등급씩 가진다.
local EXPANSION_EGGS = {
	{
		Id = "Inferno",
		Glyph = "icon_fire",
		Pattern = "shards", LocaleKey = "egg_inferno", RequiredRebirth = 7, Price = 5e12,
		Color = Color3.fromRGB(68, 24, 20), Accent = Color3.fromRGB(255, 112, 34), HatchTimeHint = 28,
		Weights = { Common = 20000, Rare = 26000, Epic = 26000, Legendary = 20000, Unknown = 7000, LegendMoment = 1000 },
		Geese = { "GooseCinder", "GooseEmberling", "GooseLavaBloom", "GoosePyroKnight", "GooseCaldera", "GooseIfrit" },
	},
	{
		Id = "Celestial",
		Glyph = "icon_crown2",
		Pattern = "crown", LocaleKey = "egg_celestial", RequiredRebirth = 7, Price = 2e13,
		Color = Color3.fromRGB(204, 232, 255), Accent = Color3.fromRGB(255, 220, 104), HatchTimeHint = 30,
		Weights = { Common = 18000, Rare = 25000, Epic = 27000, Legendary = 21000, Unknown = 7800, LegendMoment = 1200 },
		Geese = { "GooseCloudlet", "GooseStarlight", "GooseMoonveil", "GooseSeraph", "GooseSupernova", "GooseEmpyrean" },
	},
	{
		Id = "Sakura",
		Glyph = "sparkle",
		Pattern = "spots", LocaleKey = "egg_sakura", RequiredRebirth = 8, Price = 2.5e14,
		Color = Color3.fromRGB(255, 206, 226), Accent = Color3.fromRGB(246, 118, 174), HatchTimeHint = 32,
		Weights = { Common = 10000, Rare = 18000, Epic = 28000, Legendary = 28000, Unknown = 13000, LegendMoment = 3000 },
		Geese = { "GoosePetal", "GooseBlossom", "GooseKoi", "GooseHanami", "GooseMoonSakura", "GooseAmaterasu" },
	},
	{
		Id = "Arcane",
		Glyph = "icon_key",
		Pattern = "rings", LocaleKey = "egg_arcane", RequiredRebirth = 8, Price = 9e14,
		Color = Color3.fromRGB(78, 42, 128), Accent = Color3.fromRGB(88, 246, 222), HatchTimeHint = 34,
		Weights = { Common = 9000, Rare = 17000, Epic = 28000, Legendary = 29000, Unknown = 13800, LegendMoment = 3200 },
		Geese = { "GooseRune", "GoosePotion", "GooseSpellbound", "GooseArchmage", "GooseManaWraith", "GooseGrandArcanum" },
	},
	{
		Id = "CyberNova",
		Glyph = "icon_settings",
		Pattern = "stripes", LocaleKey = "egg_cyber_nova", RequiredRebirth = 8, Price = 3e15,
		Color = Color3.fromRGB(22, 32, 54), Accent = Color3.fromRGB(62, 240, 255), HatchTimeHint = 36,
		Weights = { Common = 8000, Rare = 16000, Epic = 28000, Legendary = 30000, Unknown = 14500, LegendMoment = 3500 },
		Geese = { "GoosePixel", "GooseCircuit", "GooseHologram", "GooseNeonRider", "GooseQuantum", "GooseSingularity" },
	},
	{
		Id = "Dragon",
		Glyph = "icon_strength",
		Pattern = "shards", LocaleKey = "egg_dragon", RequiredRebirth = 9, Price = 2e16,
		Color = Color3.fromRGB(106, 40, 32), Accent = Color3.fromRGB(92, 190, 255), HatchTimeHint = 38,
		Weights = { Common = 4000, Rare = 10000, Epic = 22000, Legendary = 30000, Unknown = 26000, LegendMoment = 8000 },
		Geese = { "GooseDrake", "GooseWyvern", "GooseScaleguard", "GooseDragonlord", "GooseVoidDragon", "GooseWorldDragon" },
	},
	{
		Id = "Dream",
		Glyph = "icon_music",
		Pattern = "swirl", LocaleKey = "egg_dream", RequiredRebirth = 9, Price = 7e16,
		Color = Color3.fromRGB(176, 184, 255), Accent = Color3.fromRGB(255, 146, 226), HatchTimeHint = 40,
		Weights = { Common = 3500, Rare = 9000, Epic = 21500, Legendary = 30500, Unknown = 27000, LegendMoment = 8500 },
		Geese = { "GoosePillow", "GooseBubbleDream", "GooseStarDream", "GooseDreamweaver", "GooseNightmare", "GooseLucidEmperor" },
	},
	{
		Id = "Royal",
		Glyph = "icon_trophy",
		Pattern = "crown", LocaleKey = "egg_royal", RequiredRebirth = 9, Price = 2e17,
		Color = Color3.fromRGB(70, 42, 112), Accent = Color3.fromRGB(255, 212, 62), HatchTimeHint = 42,
		Weights = { Common = 3000, Rare = 8500, Epic = 20500, Legendary = 31000, Unknown = 28000, LegendMoment = 9000 },
		Geese = { "GoosePage", "GooseBaron", "GooseDuchess", "GooseEmperor", "GooseHolyCrown", "GooseSovereign" },
	},
	{
		Id = "Chaos",
		Glyph = "icon_warning",
		Pattern = "shards", LocaleKey = "egg_chaos", RequiredRebirth = 10, Price = 2e18,
		Color = Color3.fromRGB(22, 14, 34), Accent = Color3.fromRGB(255, 58, 126), HatchTimeHint = 46,
		Weights = { Common = 1000, Rare = 4000, Epic = 15000, Legendary = 35000, Unknown = 35000, LegendMoment = 10000 },
		Geese = { "GooseRift", "GooseEntropy", "GooseDiscord", "GooseCataclysm", "GooseChaosHeart", "GooseEndbringer" },
	},
	{
		Id = "Genesis",
		Glyph = "icon_rebirth",
		Pattern = "rings", LocaleKey = "egg_genesis", RequiredRebirth = 10, Price = 8e18,
		Color = Color3.fromRGB(224, 250, 226), Accent = Color3.fromRGB(255, 220, 108), HatchTimeHint = 50,
		Weights = { Common = 800, Rare = 3200, Epic = 14000, Legendary = 35000, Unknown = 36000, LegendMoment = 11000 },
		Geese = { "GooseSeedling", "GooseFirstLight", "GooseCreation", "GooseEden", "GoosePrimordial", "GooseArchitect" },
	},
}

local RARITY_BY_INDEX = { "Common", "Rare", "Epic", "Legendary", "Unknown", "LegendMoment" }
for _, definition in ipairs(EXPANSION_EGGS) do
	local pools = {}
	for index, gooseId in ipairs(definition.Geese) do
		pools[RARITY_BY_INDEX[index]] = { gooseId }
	end
	EggConfig.Data[definition.Id] = {
		Id = definition.Id,
		Color = definition.Color,
		Accent = definition.Accent,
		RequiredRebirth = definition.RequiredRebirth,
		LocaleKey = definition.LocaleKey,
		ModelName = definition.Id .. "Egg",
		Price = definition.Price,
		Currency = "Cash",
		Icon = "icon_egg",
		IsNew = true,
		HatchTimeHint = definition.HatchTimeHint,
		RarityWeights = definition.Weights,
		Geese = pools,
	}
end

-- 좋은 등급이 지나치게 자주 나오지 않도록 전체 알 확률을 일괄 재조정한다.
-- 각 알에서 실제로 존재하는 가장 낮은 등급을 기본 보상으로 두고,
-- 그보다 높은 등급은 단계가 오를수록 수천~수백만 배씩 더 희귀해진다.
local SEVERE_DROP_WEIGHTS = {
	1000000000, -- 각 알의 기본 등급
	100000,     -- 한 단계 위: 약 0.01%
	100,        -- 두 단계 위: 약 0.00001%
	0.1,        -- 세 단계 위
	0.0001,     -- 네 단계 위
	0.0000001,  -- 다섯 단계 위
}

for _, egg in pairs(EggConfig.Data) do
	egg.RarityWeights = egg.RarityWeights or {}
	local firstPoolIndex = nil

	for index, rarityId in ipairs(RARITY_BY_INDEX) do
		local pool = egg.Geese and egg.Geese[rarityId]
		if pool and #pool > 0 then
			firstPoolIndex = index
			break
		end
	end

	if firstPoolIndex then
		for index, rarityId in ipairs(RARITY_BY_INDEX) do
			local pool = egg.Geese and egg.Geese[rarityId]
			if pool and #pool > 0 and index >= firstPoolIndex then
				local distance = index - firstPoolIndex + 1
				egg.RarityWeights[rarityId] = SEVERE_DROP_WEIGHTS[distance] or 0
			else
				egg.RarityWeights[rarityId] = 0
			end
		end
	end
end

-- 상점에는 전용 알을 숨기되 도감에는 룰렛 알까지 모두 표시한다.
EggConfig.IndexOrder = table.clone(EggConfig.Order)
table.insert(EggConfig.IndexOrder, "Wheel")

function EggConfig.get(id)
	return EggConfig.Data[id]
end

function EggConfig.weightsFor(id)
	local egg = EggConfig.Data[id]
	if not egg then
		return nil
	end
	if egg.RarityWeights then
		return egg.RarityWeights
	end
	local w = {}
	for rarityId, data in pairs(RarityConfig.Data) do
		w[rarityId] = data.Weight
	end
	return w
end

return EggConfig

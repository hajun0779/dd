--!nonstrict

--[[
	둥지 온기.

	접속해 있는 동안 둥지가 데워진다. 온기는 다섯 단계로 나뉘고,
	단계가 오를수록 거위가 버는 돈이 늘어난다.

	자리를 뜨면 식는다. 다만 잠깐 튕긴 사람까지 벌하면 안 되므로
	나간 뒤 얼마 동안은 그대로 두고, 그 뒤부터 분당 일정량씩 깎는다.

	데워지는 동안 일정 간격으로 내 둥지에 황금알이 떨어진다.
	떨어지기 전에 예고가 뜨고, 떨어진 뒤에는 직접 걸어가서 주워야 한다.
	"조금만 더 있으면 하나 더" 를 만드는 게 이 시스템의 전부다.
]]
local WarmthConfig = {}

WarmthConfig.Max = 100

--[[
	온기가 차오르는 속도. 분당 2면 0에서 100까지 50분이다.

	앞 단계는 촘촘하고 뒤 단계는 성기게 잡았다.
	첫 승급이 5분이라 접속하자마자 오르는 게 눈에 보이고,
	마지막 단계는 50분이라 한 번 앉으면 쉽게 일어나지 못한다.
]]
WarmthConfig.FillPerMinute = 2.0

--[[
	Threshold 는 이 단계에 들어가는 온기 값이다. 반드시 오름차순이어야 한다.
	Multiplier 는 거위 수입에 그대로 곱한다.
]]
WarmthConfig.Tiers = {
	{
		Id = "cold",
		Threshold = 0,
		Multiplier = 1.00,
		Palette = "gray",
		Icon = "icon_goose",
		LocaleKey = "warmth_tier_cold",
	},
	{
		Id = "ember",
		Threshold = 10,
		Multiplier = 1.12,
		Palette = "orange",
		Icon = "icon_fire",
		LocaleKey = "warmth_tier_ember",
	},
	{
		Id = "warm",
		Threshold = 28,
		Multiplier = 1.28,
		Palette = "yellow",
		Icon = "icon_fire",
		LocaleKey = "warmth_tier_warm",
	},
	{
		Id = "hot",
		Threshold = 55,
		Multiplier = 1.50,
		Palette = "red",
		Icon = "icon_fire",
		LocaleKey = "warmth_tier_hot",
	},
	{
		Id = "blaze",
		Threshold = 100,
		Multiplier = 1.80,
		Palette = "purple",
		Icon = "icon_crown2",
		LocaleKey = "warmth_tier_blaze",
	},
}

--[[
	식는 규칙.

	나간 뒤 GraceSeconds 동안은 손대지 않는다. 5분이면 잠깐 튕겼다 들어오거나
	서버를 옮기는 정도는 전부 덮는다. 그 뒤부터 분당 DecayPerMinute 씩 깎으므로
	가득 찬 온기는 대략 30분이면 바닥이 된다.

	돌아오면 "아직 따뜻하다" 를 알려 준다. 이게 재접속을 앞당긴다.
]]
WarmthConfig.GraceSeconds = 5 * 60
WarmthConfig.DecayPerMinute = 4

--[[
	가만히 서 있기만 하는 사람에게 배율을 주면 이 시스템은 방치 보상이 된다.

	IdleSeconds 동안 IdleMoveStuds 보다 덜 움직였으면 온기가 멈춘다.
	깎지는 않는다 — 잠깐 화면을 떠난 걸 벌할 이유는 없다.
	움직이면 그 즉시 다시 차오른다.
]]
WarmthConfig.IdleSeconds = 300
WarmthConfig.IdleMoveStuds = 6

WarmthConfig.Drop = {
	--[[
		첫 황금알은 3분. 접속하자마자 한 번 받아 봐야 다음 것도 기다린다.
		그 뒤로는 6분 간격이되, 단계가 오를수록 30초씩 짧아진다.
		오래 앉아 있을수록 보상이 촘촘해지는 쪽이 앉아 있게 만든다.
	]]
	FirstSeconds = 180,
	IntervalSeconds = 360,
	IntervalPerTier = -30,
	MinIntervalSeconds = 210,

	-- 떨어지기 몇 초 전에 예고할지
	WarnSeconds = 30,

	-- 떨어진 뒤 주울 수 있는 시간. 지나면 사라진다.
	LifetimeSeconds = 90,

	-- 기지 스폰 지점 위 이 높이에 뜬다
	HoverHeight = 5,
	CollectRadius = 9,

	--[[
		보상은 두 값 중 큰 쪽이다.

		  · FlatCash — 거위가 아직 없는 초반용 고정액
		  · SecondsOfIncome — 현재 초당 수입 × 이 초수

		뒤쪽 덕분에 환생을 아무리 많이 해도 보상이 초라해지지 않는다.
		최고 단계에서 9분치 수입이 한 번에 들어온다.
	]]
	FlatCash = { 2500, 8000, 25000, 80000, 250000 },
	SecondsOfIncome = { 90, 150, 240, 360, 540 },

	-- 단계별 룰렛 기회 / 알 추가 지급 확률
	SpinChance = { 0, 0.02, 0.05, 0.10, 0.18 },
	EggChance = { 0.05, 0.08, 0.12, 0.18, 0.28 },
	EggPool = {
		Basic = 60,
		Forest = 25,
		Frost = 10,
		Wheel = 4,
		Exclusive = 1,
	},

	-- 가방이 가득 차 알을 못 받았을 때 대신 얹어 주는 현금 비율
	EggFallbackRatio = 0.5,

	-- 이 단계부터는 서버 전체에 알린다. 남의 황금알이 부러워야 나도 남는다.
	AnnounceFromTier = 5,
}

function WarmthConfig.tierIndexFor(value: number): number
	value = tonumber(value) or 0
	local index = 1
	for i, tier in ipairs(WarmthConfig.Tiers) do
		if value >= tier.Threshold then
			index = i
		else
			break
		end
	end
	return index
end

function WarmthConfig.tier(index: number)
	return WarmthConfig.Tiers[math.clamp(math.floor(index or 1), 1, #WarmthConfig.Tiers)]
end

function WarmthConfig.tierFor(value: number)
	return WarmthConfig.tier(WarmthConfig.tierIndexFor(value))
end

function WarmthConfig.multiplierFor(value: number): number
	local tier = WarmthConfig.tierFor(value)
	return tier and tier.Multiplier or 1
end

function WarmthConfig.nextTier(index: number)
	return WarmthConfig.Tiers[math.floor(index or 1) + 1]
end

--- 다음 단계까지 남은 초. 이미 최고 단계면 nil.
function WarmthConfig.secondsToNextTier(value: number): number?
	local nextTier = WarmthConfig.nextTier(WarmthConfig.tierIndexFor(value))
	if not nextTier then
		return nil
	end
	local perMinute = math.max(WarmthConfig.FillPerMinute, 0.01)
	return math.max(0, (nextTier.Threshold - (tonumber(value) or 0)) / perMinute * 60)
end

function WarmthConfig.dropInterval(tierIndex: number): number
	local D = WarmthConfig.Drop
	local steps = math.max(math.floor(tierIndex or 1) - 1, 0)
	return math.max(D.IntervalSeconds + D.IntervalPerTier * steps, D.MinIntervalSeconds)
end

function WarmthConfig.dropCash(tierIndex: number, incomeRate: number): number
	local D = WarmthConfig.Drop
	local index = math.clamp(math.floor(tierIndex or 1), 1, #WarmthConfig.Tiers)
	local flat = D.FlatCash[index] or D.FlatCash[#D.FlatCash] or 0
	local seconds = D.SecondsOfIncome[index] or D.SecondsOfIncome[#D.SecondsOfIncome] or 0
	local earned = math.max(tonumber(incomeRate) or 0, 0) * seconds
	return math.floor(math.max(flat, earned))
end

function WarmthConfig.dropChance(list: { number }, tierIndex: number): number
	local index = math.clamp(math.floor(tierIndex or 1), 1, #WarmthConfig.Tiers)
	return math.clamp(tonumber(list[index]) or 0, 0, 1)
end

return WarmthConfig

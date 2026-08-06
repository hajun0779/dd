--!nonstrict

--[[
	거대한 눈 이벤트.

	땅속에서 거대한 구체가 솟아올라, 눈에서 레이저를 쏴
	기지 여덟 곳을 하나씩 훑는다. 레이저를 맞은 기지의 주인은 축복을 받는다.

	하늘과 안개까지 통째로 주황색으로 물들여서
	"뭔가 일어나고 있다" 는 걸 맵 어디서든 알 수 있게 한다.

	필요한 것 (스튜디오에서 직접 배치)
	  ServerStorage > Events > Ball      구체 모델 (안에 Eyes 파트)
	  Workspace     > Events > Ball      구체가 솟아오를 자리를 표시하는 파트
]]
local BallEventConfig = {}

BallEventConfig.FolderName = "Events"
BallEventConfig.BallName = "Ball"

--- 구체가 최종적으로 올라올 자리
BallEventConfig.BallTopName = "Ball2"
BallEventConfig.EyeName = "Eyes"

--[[
	불이 날 자리를 표시하는 고리.

	Workspace > Events 안에 두면 그 고리를 따라 불이 난다.
	  모델이면  → 안에 있는 파트 하나하나가 곧 불자리 (제일 정확하다)
	  파트면    → 크기에서 반지름을 재서 그 위에 빙 둘러 놓는다
	없으면 구체 자리를 중심으로 원을 그려서 대신한다.
]]
BallEventConfig.RingName = "12345"

BallEventConfig.Timing = {
	--- 땅속에서 올라오는 데 걸리는 시간
	RiseSeconds = 6,
	--- 다 올라온 뒤 레이저를 쏘기까지 뜸을 들이는 시간
	ChargeSeconds = 2.5,
	--- 기지 하나를 조준하고 있는 시간
	BeamSeconds = 1.6,
	--- 다음 기지로 옮겨 가는 시간
	SweepSeconds = 0.5,
	--- 다 쏘고 나서 가라앉기까지
	LingerSeconds = 3,
	SinkSeconds = 4,
}

--- Ball2 가 없을 때만 쓰는 값. 있으면 그 자리까지 올라온다.
BallEventConfig.RiseDepth = 90

--[[
	불바다.

	맵 가장자리를 빙 둘러 불덩이를 피워 올려서 지평선이 타는 것처럼 만든다.
	로블록스 기본 Fire 는 촛불 크기라 이런 그림이 안 나온다.
	직접 구운 flame 텍스처를 큰 덩어리로 겹쳐 쓴다.
]]
BallEventConfig.Fire = {
	--- 고리가 없을 때만 쓰는 반지름
	Radius = 300,
	--- 원을 몇 등분해서 불을 놓을지
	Points = 18,

	--[[
		고리 파트의 겉지름 대비 어디에 불을 놓을지.

		가운데가 뚫린 고리라서 겉지름 그대로 쓰면 불이 바깥으로 밀린다.
		고리 두께의 한가운데쯤에 놓이도록 조금 안쪽으로 당긴다.
	]]
	RingScale = 0.86,

	--[[
		불은 바닥에서 나야 한다.

		구체는 공중에 뜨므로 그 높이를 따라가면 불이 하늘에 뜬다.
		지점마다 아래로 광선을 쏴서 실제 땅을 찾고, 거기서 이만큼 내려 붙인다.
		살짝 묻어야 땅에서 솟아오르는 것처럼 보인다.
	]]
	GroundOffset = -8,
	--- 땅을 찾을 때 위에서부터 훑는 높이
	GroundProbe = 400,

	Rate = 9,
	--[[
		불덩이 크기.

		멀리서 지평선을 채우는 게 목적이라 크게 잡되, 너무 키우면
		가까이 갔을 때 화면이 통째로 덮인다. 40 정도가 한계다.
	]]
	Size = 40,
	Lifetime = 5.5,
	Speed = 26,
}

BallEventConfig.Color = {
	Main = Color3.fromRGB(255, 138, 30),
	Hot = Color3.fromRGB(255, 208, 120),
	Fog = Color3.fromRGB(120, 46, 8),
	Ambient = Color3.fromRGB(90, 40, 12),
}

--[[
	이벤트 동안의 하늘.

	너무 세게 걸면 화면이 통째로 뭉개진다.
	분위기만 바꾸고 형체는 남아 있어야 한다.
]]
BallEventConfig.Lighting = {
	FogStart = 120,
	FogEnd = 900,
	--- 화면이 너무 밝다는 말이 많아 낮췄다. 기준값은 ShowConfig.BaseLighting 에 있다.
	Brightness = 1.0,
	ExposureCompensation = -0.2,
	--- 해가 낮게 걸린 저녁. 한밤중(0)으로 만들면 아무것도 안 보인다.
	ClockTime = 17.2,
	FadeSeconds = 3,
}

--- 화면 보정. 숫자를 키우면 금방 색이 뒤집힌다.
BallEventConfig.Grade = {
	--- 블룸이 세면 밝은 곳이 전부 하얗게 뭉개진다. 0.7 은 과했다.
	Bloom = 0.34,
	Contrast = 0.08,
	Saturation = 0.1,
}

BallEventConfig.Laser = {
	Width = 3.2,
	Transparency = 0.15,
	--[[
		눈에서 하늘로 뻗는 기둥.

		구체 한가운데에서 시작하면 구체를 먹어 버린다.
		위로 이만큼 띄워서 구체 "위" 로만 뻗게 한다.
	]]
	PillarWidth = 6,
	PillarHeight = 300,
	PillarLift = 40,
}

--[[
	레이저를 맞은 기지의 주인이 받는 것.

	잠깐이라도 확실히 좋아야 사람들이 이벤트를 기다린다.
]]
BallEventConfig.Blessing = {
	Seconds = 180,
	Income = 3,
	Cash = 5000,
}

return BallEventConfig

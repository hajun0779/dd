--!nonstrict

local GameConfig = {}

GameConfig.Player = {
	WalkSpeed = 30,
	JumpPower = 50,
}

GameConfig.Base = {
	--[[
		슬롯.

		SlotCount 는 "있을 수 있는 최대" 다. GroundSlotCount 까지가 1층이고,
		나머지는 2층이 열려야 쓸 수 있다.

		맵에는 Slot 폴더 아래에 1~16 을 다 만들어 두면 된다.
		9~16 은 2층에 놓는다. 만들지 않은 번호는 그냥 없는 것으로 친다.
	]]
	SlotCount = 16,
	GroundSlotCount = 8,
	--- 2층이 열렸는지 기지 모델에 적어 두는 속성. FloorService 가 쓴다.
	FloorTwoAttribute = "FloorTwo",

	SlotFolderName = "Slot",
	HandleName = "Handle",
	LockPartName = "LockPart",
	FriendPartName = "FriendPart",
	DoorName = "Door",
	SignPartName = "Sign",
	SpawnPartName = "SpawnPart",
	NameGuiName = "Name",
	SignFace = Enum.NormalId.Front,
	BasesFolderName = "Bases",

	OwnerAttribute = "OwnerUserId",
	OwnerNameAttribute = "OwnerName",
	FriendAllowAttribute = "AllowFriends",
	LockedAttribute = "DoorLocked",

	ModelYOffset = 0.15,

		DoorCollisionGroupPrefix = "RadBaseDoor_",
	MaxDoorGroups = 24,

	DoorOpenInterval = 60,
	DoorIntervalPerRebirth = 10,

	-- 강제 열기 프롬프트는 문 전체의 바닥에서 이 높이에 고정한다.
	DoorPurchasePromptHeight = 2.6,
	DoorPurchasePromptScreenYOffset = 30,
}

GameConfig.Rebirth = {
	Max = 10,

	-- 현재 환생 수 n에서 n+1로 갈 때 Costs[n+1]을 사용한다.
	-- 단순 배수 대신 구간별 가격을 써서 초반은 진입 가능하고 후반은 확실히 오래 걸리게 한다.
	Costs = {
		5e5,   -- 0 -> 1: 500K
		8e6,   -- 1 -> 2: 8M
		1.5e8, -- 2 -> 3: 150M
		3e9,   -- 3 -> 4: 3B
		6e10,  -- 4 -> 5: 60B
		1.5e11,-- 5 -> 6: 150B
		1e12,  -- 6 -> 7: 1T
		5e13,  -- 7 -> 8: 50T
		3e15,  -- 8 -> 9: 3Qa
		2e17,  -- 9 -> 10: 200Qa
	},
	-- Costs가 비어 있을 때만 쓰는 안전용 계산식.
	BaseCost = 500000,
	CostMultiplier = 12,

	-- 환생하면 알과 거위를 전부 잃고, 갖고 있던 돈의 5%만 남는다.
	ResetInventory = true,
	CashKeepRatio = 0.05,

	-- 기존 +50%에서 +35%로 낮춰 10환생의 총 배율이 4.5배를 넘지 않게 한다.
	IncomePerRebirth = 0.35,
}

GameConfig.Steal = {
	HoldDuration = 4.0,
	PromptMaxDistance = 10,
	PromptKeyCode = Enum.KeyCode.E,

	CarrySpeed = 20,
	CarryJumpPower = 45,
	CarryRotation = CFrame.Angles(0, 0, math.rad(90)),
	CarryOffset = Vector3.new(0, 0, -1.6),

	CarryAnimationId = "rbxassetid://132418528681408",
-- 스크립트 ㄹㅇ 
		DepositDoorRadius = 5,
	DepositRadius = 18,

	SirenDuration = 6,
	AlertDuration = 5,
}

GameConfig.Sell = {
	HoldDuration = 1.0,
	KeyCode = Enum.KeyCode.Q,
	PromptMaxDistance = 10,
	PayoutRatio = 0.8,
}

GameConfig.Income = {
	TickInterval = 1,
	RewardPartName = "Reward",
	CollectDebounce = 0.5,
	CollectSoundId = "rbxasset://sounds/electronicpingshort.wav",
	CollectSoundVolume = 0.65,
	OfflineRatio = 0.03,
	OfflineMaxSeconds = 3 * 24 * 60 * 60,
	OfflineHardCutoff = false,
	MinOfflineSeconds = 60,
}

GameConfig.Hatch = {
	PromptHoldDuration = 0.5,
	PromptMaxDistance = 12,

	HitWindowDegrees = 26,
	RequiredHits = 5,
	MaxMisses = 4,
	BaseSpeed = 150,
	SpeedGainPerHit = 28,
	MaxSpeed = 420,
	SessionTimeout = 60,
	LatencyToleranceDegrees = 14,
	MinTapInterval = 0.10,
}

GameConfig.Inventory = {
	HotbarSlots = 10,
	MaxSlots = 60,
	SaveDebounce = 0.5,
}

GameConfig.Bat = {
	Cooldown = 0.75,
	-- 휘두르는 애니메이션과 실제 판정이 어긋나 보이지 않도록 넉넉하게 잡는다.
	HitRadius = 8,
	HitAngleDegrees = 145,
	VerticalTolerance = 8,
	LineOfSight = true,

	RagdollDuration = 3.0,
	FlingPower = 45,
	FlingUp = 30,
	StunAfterRagdoll = 0.6,
}

GameConfig.Shame = {
	DisplaySeconds = 10,
}

GameConfig.Debug = {
	Verbose = false,
}

return GameConfig

--!nonstrict

--[[
	2층.

	도감을 일정 개수 채우면 기지의 2층이 열린다.
	열리면 슬롯이 여덟 칸 늘어난다.

	막고 있는 것은 기지 안에 둔 Two 라는 파트 하나다.
	열리면 그 파트가 투명해지고 통과할 수 있게 된다 — 문을 여는 게 아니라
	막고 있던 판을 치우는 방식이라, 맵에는 파트 하나만 놓으면 된다.
]]
local FloorConfig = {}

--- 도감(거위 + 알)에서 이만큼 발견하면 열린다
FloorConfig.Required = 30

--[[
	기지 안에서 찾을 파트 이름.

	기지 모델 아래라면 어디에 있어도 찾는다(하위 폴더 포함).
	모델이면 그 안의 파트를 전부 치운다.
]]
FloorConfig.PartName = "Two"

--- 열렸을 때 그 파트에 적용할 값
FloorConfig.Open = {
	Transparency = 1,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
}

--- 2층에서 늘어나는 슬롯 수 (GameConfig.Base.GroundSlotCount 에 더해진다)
FloorConfig.ExtraSlots = 8

--[[
	안내.

	열린 직후 잠깐 동안만 길을 그려 준다.
	계속 띄워 두면 화면을 가리는 장식이 되고, 안 띄우면 열린 걸 모른다.
]]
FloorConfig.Guide = {
	Seconds = 60,
	Color = Color3.fromRGB(255, 214, 92),
	BeamWidth = 1.6,
	BeamTexture = "rbxasset://textures/particles/sparkles_main.dds",
	BillboardHeight = 6,
}

--[[
	환영 표시를 띄우는 높이.

	Two 파트 윗면에서 이만큼 위로 올라가면 "2층에 올라왔다" 로 본다.
	너무 작게 잡으면 파트 옆을 스칠 때도 뜬다.
]]
FloorConfig.WelcomeHeight = 8

--- 올라왔는지 확인하는 주기(초)
FloorConfig.CheckInterval = 1

return FloorConfig

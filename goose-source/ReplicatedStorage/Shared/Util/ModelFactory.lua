--!nonstrict

--[[
	모델이 없을 때 대신 만들어 준다.

	알과 거위 전용 모델을 전부 직접 만들려면 시간이 오래 걸린다.
	그동안 게임이 멈춰 있으면 안 되니, 없는 것은 여기서 파트로 조립한다.

	진짜 모델을 Assets 폴더에 넣으면 그쪽이 우선이다.
	이건 어디까지나 빈자리를 메우는 용도다.
]]
local GooseVfxConfig = require(script.Parent.Parent.Config.GooseVfxConfig)
local EggConfig = require(script.Parent.Parent.Config.EggConfig)
local GooseConfig = require(script.Parent.Parent.Config.GooseConfig)

local ModelFactory = {}

local DEFAULT_BODY = Color3.fromRGB(248, 248, 246)
local DEFAULT_BEAK = Color3.fromRGB(255, 168, 40)
local EYE_COLOR = Color3.new(0, 0, 0)

local function newPart(name: string, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Shape = shape or Enum.PartType.Block
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	return part
end

local function joint(name: string, part0: BasePart, part1: BasePart, offset: CFrame)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = offset
	motor.C1 = CFrame.new()
	motor.Parent = part0
end

--[[
	거위 뼈대.

	이름은 사용자가 만든 GooseWhite 와 맞춘다.
	그래야 나중에 진짜 모델로 갈아 끼워도 애니메이션이 그대로 돌아간다.

	  name    파트 이름
	  size    크기
	  parent  붙을 부모 파트
	  at      부모 기준 위치
	  role    색을 고를 때 쓰는 부위
]]
local GOOSE_BONES = {
	{ name = "Torso", size = Vector3.new(1.7, 1.5, 2.6), parent = "HumanoidRootPart", at = Vector3.new(0, 0, 0), role = "Body" },
	{ name = "Torso2", size = Vector3.new(1.1, 1.1, 1.1), parent = "Torso", at = Vector3.new(0, 0.85, -0.9), role = "Body" },
	{ name = "Torso3", size = Vector3.new(0.75, 1.1, 0.75), parent = "Torso2", at = Vector3.new(0, 0.95, -0.1), role = "Body" },
	{ name = "Head", size = Vector3.new(0.95, 0.95, 1.2), parent = "Torso3", at = Vector3.new(0, 0.9, -0.15), role = "Head" },
	{ name = "Beak", size = Vector3.new(0.42, 0.34, 0.8), parent = "Head", at = Vector3.new(0, -0.08, -0.9), role = "Beak" },
	{ name = "LeftEye", size = Vector3.new(0.16, 0.22, 0.22), parent = "Head", at = Vector3.new(-0.4, 0.2, -0.45), role = "Eye" },
	{ name = "RightEye", size = Vector3.new(0.16, 0.22, 0.22), parent = "Head", at = Vector3.new(0.4, 0.2, -0.45), role = "Eye" },
	{ name = "LeftWing", size = Vector3.new(0.3, 0.85, 1.7), parent = "Torso", at = Vector3.new(-1.0, 0.15, 0.1), role = "Wing" },
	{ name = "RightWing", size = Vector3.new(0.3, 0.85, 1.7), parent = "Torso", at = Vector3.new(1.0, 0.15, 0.1), role = "Wing" },
	{ name = "LeftWing2", size = Vector3.new(0.24, 0.6, 0.9), parent = "LeftWing", at = Vector3.new(-0.05, -0.1, 1.2), role = "Wing" },
	{ name = "RightWing2", size = Vector3.new(0.24, 0.6, 0.9), parent = "RightWing", at = Vector3.new(0.05, -0.1, 1.2), role = "Wing" },
	{ name = "Tail", size = Vector3.new(0.8, 0.55, 0.9), parent = "Torso", at = Vector3.new(0, 0.35, 1.6), role = "Body" },
	{ name = "LeftFoot", size = Vector3.new(0.5, 0.24, 0.8), parent = "Torso", at = Vector3.new(-0.45, -0.85, -0.3), role = "Beak" },
	{ name = "RightFoot", size = Vector3.new(0.5, 0.24, 0.8), parent = "Torso", at = Vector3.new(0.45, -0.85, -0.3), role = "Beak" },
}

local function gooseLook(gooseId: string)
	local entry = GooseVfxConfig.Geese[gooseId]
	local cfg = GooseConfig.get(gooseId)
	local procedural = cfg and cfg.Look
	local look = entry or procedural
	if not look then
		return {
			Body = DEFAULT_BODY, Wing = DEFAULT_BODY, Head = DEFAULT_BODY,
			Beak = DEFAULT_BEAK, Eye = EYE_COLOR,
		}
	end
	return {
		Body = look.Body or DEFAULT_BODY,
		Wing = look.Wing or look.Body or DEFAULT_BODY,
		Head = look.Head or look.Body or DEFAULT_BODY,
		Beak = look.Beak or DEFAULT_BEAK,
		Eye = EYE_COLOR,
		Glow = look.Glow or look.Head or look.Body or DEFAULT_BODY,
		Material = look.Material,
		Reflectance = look.Reflectance,
		Style = look.Style,
		Tier = look.Tier,
		Procedural = procedural ~= nil,
	}
end

local function decoration(
	model: Model,
	anchor: BasePart,
	name: string,
	size: Vector3,
	color: Color3,
	offset: CFrame,
	shape: Enum.PartType?,
	material: Enum.Material?
): BasePart
	local part = newPart(name, size, color, shape)
	part.Material = material or Enum.Material.SmoothPlastic
	part:SetAttribute("PreserveColor", true)
	part.CFrame = anchor.CFrame * offset
	part.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function decorateGoose(model: Model, parts, look)
	local head = parts.Head
	local torso = parts.Torso
	if not head or not torso or not look.Style then
		return
	end

	if look.Style == "Clover" then
		local green = Color3.fromRGB(74, 190, 76)
		for i = 1, 4 do
			local a = (i - 1) * math.pi / 2
			decoration(model, head, "CloverLeaf" .. i, Vector3.new(0.42, 0.20, 0.48), green,
				CFrame.new(math.cos(a) * 0.30, 0.68, math.sin(a) * 0.30), Enum.PartType.Ball)
		end
		decoration(model, head, "CloverStem", Vector3.new(0.10, 0.42, 0.10), Color3.fromRGB(50, 140, 58),
			CFrame.new(0, 0.82, 0) * CFrame.Angles(0, 0, math.rad(-18)))
	elseif look.Style == "Halo" then
		for i = 1, 10 do
			local a = (i - 1) * math.pi * 2 / 10
			decoration(model, head, "HaloLight" .. i, Vector3.new(0.18, 0.18, 0.18), look.Glow,
				CFrame.new(math.cos(a) * 0.78, 0.90, math.sin(a) * 0.78), Enum.PartType.Ball, Enum.Material.Neon)
		end
	elseif look.Style == "Ruby" then
		for i = -1, 1 do
			decoration(model, head, "RubyCrystal" .. tostring(i + 2), Vector3.new(0.28, 0.74 + math.abs(i) * 0.12, 0.28),
				Color3.fromRGB(255, 54, 94),
				CFrame.new(i * 0.30, 0.84, 0) * CFrame.Angles(0, 0, math.rad(45)),
				Enum.PartType.Block, Enum.Material.Glass)
		end
	elseif look.Style == "Crown" then
		decoration(model, head, "CrownBand", Vector3.new(1.12, 0.22, 1.12), Color3.fromRGB(255, 198, 42),
			CFrame.new(0, 0.58, 0), Enum.PartType.Block, Enum.Material.Metal)
		for i = -1, 1 do
			decoration(model, head, "CrownPoint" .. tostring(i + 2), Vector3.new(0.22, 0.72 - math.abs(i) * 0.12, 0.22),
				Color3.fromRGB(255, 222, 82), CFrame.new(i * 0.36, 0.94, -0.05),
				Enum.PartType.Block, Enum.Material.Neon)
		end
	elseif look.Style == "Prism" then
		for i = 1, 8 do
			local a = (i - 1) * math.pi * 2 / 8
			decoration(model, torso, "PrismShard" .. i, Vector3.new(0.20, 0.62, 0.20),
				Color3.fromHSV((i - 1) / 8, 0.75, 1),
				CFrame.new(math.cos(a) * 1.35, 0.75 + (i % 2) * 0.22, math.sin(a) * 1.35)
					* CFrame.Angles(0, -a, math.rad(35)),
				Enum.PartType.Block, Enum.Material.Neon)
		end
	elseif look.Style == "Eclipse" then
		decoration(model, head, "EclipseCore", Vector3.new(0.72, 0.72, 0.72), Color3.fromRGB(8, 6, 14),
			CFrame.new(0, 1.28, 0), Enum.PartType.Ball, Enum.Material.SmoothPlastic)
		for i = 1, 12 do
			local a = (i - 1) * math.pi * 2 / 12
			decoration(model, head, "EclipseRay" .. i, Vector3.new(0.18, 0.18, 0.18), look.Glow,
				CFrame.new(math.cos(a) * 0.66, 1.28, math.sin(a) * 0.66), Enum.PartType.Ball, Enum.Material.Neon)
		end
	elseif look.Style == "Bloom" then
		decoration(model, head, "BloomCore", Vector3.new(0.38, 0.28, 0.38), look.Glow,
			CFrame.new(0, 0.78, 0), Enum.PartType.Ball, Enum.Material.Neon)
		for i = 1, 7 do
			local a = (i - 1) * math.pi * 2 / 7
			decoration(model, head, "BloomPetal" .. i, Vector3.new(0.22, 0.12, 0.50), look.Head,
				CFrame.new(math.cos(a) * 0.38, 0.74, math.sin(a) * 0.38) * CFrame.Angles(0, -a, math.rad(28)),
				Enum.PartType.Ball)
		end
	elseif look.Style == "Antenna" then
		for side = -1, 1, 2 do
			decoration(model, head, "AntennaStem" .. side, Vector3.new(0.10, 0.70, 0.10), look.Wing,
				CFrame.new(side * 0.26, 0.88, 0) * CFrame.Angles(0, 0, math.rad(side * -18)))
			decoration(model, head, "AntennaGlow" .. side, Vector3.new(0.24, 0.24, 0.24), look.Glow,
				CFrame.new(side * 0.38, 1.22, 0), Enum.PartType.Ball, Enum.Material.Neon)
		end
	elseif look.Style == "Antler" then
		for side = -1, 1, 2 do
			decoration(model, head, "AntlerMain" .. side, Vector3.new(0.14, 1.05, 0.14), look.Beak,
				CFrame.new(side * 0.48, 0.92, 0.08) * CFrame.Angles(0, 0, math.rad(side * -24)), nil, Enum.Material.Wood)
			for branch = 1, 2 do
				decoration(model, head, "AntlerBranch" .. side .. branch, Vector3.new(0.12, 0.48, 0.12), look.Glow,
					CFrame.new(side * (0.54 + branch * 0.12), 0.84 + branch * 0.28, 0.08)
						* CFrame.Angles(0, 0, math.rad(side * -55)), nil, Enum.Material.Neon)
			end
		end
	elseif look.Style == "Coral" then
		for i = 1, 8 do
			local a = (i - 1) * math.pi * 2 / 8
			decoration(model, torso, "CoralBranch" .. i, Vector3.new(0.16, 0.72 + (i % 3) * 0.18, 0.16),
				i % 2 == 0 and look.Glow or look.Head,
				CFrame.new(math.cos(a) * 1.02, 0.58, math.sin(a) * 1.20)
					* CFrame.Angles(math.rad(18), -a, math.rad(math.cos(a) * 32)), nil, Enum.Material.Neon)
		end
	elseif look.Style == "Abyss" then
		for i = 1, 10 do
			local a = (i - 1) * math.pi * 2 / 10
			decoration(model, torso, "AbyssSpike" .. i, Vector3.new(0.18, 0.18, 0.92), look.Glow,
				CFrame.new(math.cos(a) * 1.10, 0.22 + (i % 2) * 0.5, math.sin(a) * 1.45)
					* CFrame.Angles(0, -a, math.rad(34)), nil, Enum.Material.Neon)
		end
		decoration(model, head, "AbyssEye", Vector3.new(0.34, 0.34, 0.34), look.Glow,
			CFrame.new(0, 0.14, -0.62), Enum.PartType.Ball, Enum.Material.Neon)
	elseif look.Style == "Scarab" then
		for side = -1, 1, 2 do
			decoration(model, torso, "ScarabShell" .. side, Vector3.new(0.66, 1.05, 1.58), look.Wing,
				CFrame.new(side * 0.58, 0.42, 0.12) * CFrame.Angles(0, 0, math.rad(side * 16)),
				Enum.PartType.Ball, Enum.Material.Metal)
		end
		decoration(model, torso, "ScarabGem", Vector3.new(0.36, 0.52, 0.36), look.Glow,
			CFrame.new(0, 0.92, -0.58) * CFrame.Angles(0, 0, math.rad(45)), nil, Enum.Material.Neon)
	elseif look.Style == "Pharaoh" then
		decoration(model, head, "PharaohBand", Vector3.new(1.36, 0.28, 1.26), look.Glow,
			CFrame.new(0, 0.54, 0), nil, Enum.Material.Metal)
		for side = -1, 1, 2 do
			for row = 1, 3 do
				decoration(model, head, "PharaohFan" .. side .. row, Vector3.new(0.22, 0.82, 0.34),
					row % 2 == 0 and look.Glow or look.Wing,
					CFrame.new(side * (0.52 + row * 0.14), 0.48 - row * 0.08, 0.08)
						* CFrame.Angles(0, 0, math.rad(side * 18)), nil, Enum.Material.Metal)
			end
		end
	elseif look.Style == "Aurora" then
		for i = 1, 14 do
			local t = (i - 1) / 13
			local a = math.pi * t
			decoration(model, torso, "AuroraArc" .. i, Vector3.new(0.20, 0.20, 0.20),
				Color3.fromHSV(0.38 + t * 0.32, 0.62, 1),
				CFrame.new(math.cos(a) * 1.35, 0.52 + math.sin(a) * 1.15, 0.25), Enum.PartType.Ball, Enum.Material.Neon)
		end
	elseif look.Style == "Comet" then
		for i = 1, 7 do
			decoration(model, torso, "CometTail" .. i, Vector3.new(0.18 + i * 0.025, 0.18 + i * 0.025, 0.55 + i * 0.18),
				i % 2 == 0 and look.Glow or look.Head,
				CFrame.new((i - 4) * 0.16, 0.42 + (i % 2) * 0.22, 1.55 + i * 0.13)
					* CFrame.Angles(math.rad(-18), 0, math.rad((i - 4) * 6)), nil, Enum.Material.Neon)
		end
	elseif look.Style == "Gear" then
		for i = 1, 12 do
			local a = (i - 1) * math.pi * 2 / 12
			decoration(model, torso, "GearTooth" .. i, Vector3.new(0.22, 0.36, 0.48),
				i % 3 == 0 and look.Glow or look.Beak,
				CFrame.new(math.cos(a) * 1.22, 0.60, math.sin(a) * 1.22) * CFrame.Angles(0, -a, 0), nil, Enum.Material.Metal)
		end
		decoration(model, torso, "GearCore", Vector3.new(0.54, 0.54, 0.54), look.Glow,
			CFrame.new(0, 0.62, -1.28), Enum.PartType.Ball, Enum.Material.Neon)
	elseif look.Style == "Hourglass" then
		decoration(model, head, "HourglassTop", Vector3.new(0.82, 0.18, 0.82), look.Beak,
			CFrame.new(0, 1.30, 0), nil, Enum.Material.Metal)
		decoration(model, head, "HourglassBottom", Vector3.new(0.82, 0.18, 0.82), look.Beak,
			CFrame.new(0, 0.62, 0), nil, Enum.Material.Metal)
		for i = -1, 1, 2 do
			decoration(model, head, "HourglassSide" .. i, Vector3.new(0.13, 0.76, 0.13), look.Glow,
				CFrame.new(i * 0.34, 0.96, 0), nil, Enum.Material.Neon)
		end
		decoration(model, head, "HourglassSand", Vector3.new(0.34, 0.34, 0.34), look.Glow,
			CFrame.new(0, 0.92, 0), Enum.PartType.Ball, Enum.Material.Neon)
	elseif look.Style == "Flame" then
		for i = -2, 2 do
			local height = 0.72 + (3 - math.abs(i)) * 0.22
			decoration(model, torso, "FlamePlume" .. tostring(i + 3), Vector3.new(0.24, height, 0.24),
				i % 2 == 0 and look.Glow or look.Beak,
				CFrame.new(i * 0.30, 0.68 + height * 0.35, 0.66 + math.abs(i) * 0.12)
					* CFrame.Angles(math.rad(-18), 0, math.rad(i * 11)), nil, Enum.Material.Neon)
		end
		for side = -1, 1, 2 do
			decoration(model, head, "FlameHorn" .. side, Vector3.new(0.18, 0.82, 0.18), look.Glow,
				CFrame.new(side * 0.42, 0.84, 0.12) * CFrame.Angles(0, 0, math.rad(side * -26)), nil, Enum.Material.Neon)
		end
	elseif look.Style == "Wings" then
		for side = -1, 1, 2 do
			for feather = 1, 4 do
				decoration(model, torso, "CelestialFeather" .. side .. feather,
					Vector3.new(0.18, 0.52 + feather * 0.18, 0.90 + feather * 0.20),
					feather % 2 == 0 and look.Glow or look.Wing,
					CFrame.new(side * (1.02 + feather * 0.26), 0.40 - feather * 0.08, 0.20 + feather * 0.20)
						* CFrame.Angles(math.rad(-18), 0, math.rad(side * (24 + feather * 5))),
					nil, feather >= 3 and Enum.Material.Neon or Enum.Material.Glass)
			end
		end
	elseif look.Style == "Dream" then
		for i = 1, 7 do
			local a = (i - 1) * math.pi * 2 / 7
			decoration(model, torso, "DreamCloud" .. i,
				Vector3.new(0.42 + (i % 3) * 0.12, 0.32 + (i % 2) * 0.12, 0.48 + (i % 3) * 0.10),
				i % 2 == 0 and look.Head or look.Glow,
				CFrame.new(math.cos(a) * 1.16, 0.72 + math.sin(a * 2) * 0.22, math.sin(a) * 1.20),
				Enum.PartType.Ball, i % 2 == 0 and Enum.Material.Glass or Enum.Material.Neon)
		end
		decoration(model, head, "DreamMoon", Vector3.new(0.52, 0.78, 0.20), look.Glow,
			CFrame.new(0, 1.08, 0.08) * CFrame.Angles(0, 0, math.rad(22)), nil, Enum.Material.Neon)
	elseif look.Style == "Sakura" then
		decoration(model, head, "SakuraCore", Vector3.new(0.32, 0.24, 0.32), look.Beak,
			CFrame.new(0, 0.82, 0), Enum.PartType.Ball, Enum.Material.Neon)
		for i = 1, 10 do
			local a = (i - 1) * math.pi * 2 / 10
			local layer = i % 2 == 0 and 0.42 or 0.62
			decoration(model, head, "SakuraPetal" .. i, Vector3.new(0.24, 0.11, 0.52),
				i % 2 == 0 and look.Glow or look.Head,
				CFrame.new(math.cos(a) * layer, 0.80 + (i % 2) * 0.14, math.sin(a) * layer)
					* CFrame.Angles(math.rad(18), -a, math.rad(34)), Enum.PartType.Ball,
				i % 3 == 0 and Enum.Material.Neon or Enum.Material.SmoothPlastic)
		end
	elseif look.Style == "Rune" then
		for i = 1, 12 do
			local a = (i - 1) * math.pi * 2 / 12
			decoration(model, torso, "RuneGlyph" .. i, Vector3.new(0.20, 0.42, 0.12),
				i % 3 == 0 and look.Beak or look.Glow,
				CFrame.new(math.cos(a) * 1.34, 0.58 + math.sin(a * 2) * 0.22, math.sin(a) * 1.34)
					* CFrame.Angles(0, -a, math.rad((i % 2 == 0 and 1 or -1) * 45)), nil, Enum.Material.Neon)
		end
		decoration(model, head, "RuneFocus", Vector3.new(0.44, 0.62, 0.22), look.Glow,
			CFrame.new(0, 0.92, -0.30) * CFrame.Angles(0, 0, math.rad(45)), nil, Enum.Material.Glass)
	elseif look.Style == "Cyber" then
		decoration(model, head, "CyberVisor", Vector3.new(1.12, 0.28, 0.22), look.Glow,
			CFrame.new(0, 0.20, -0.58), nil, Enum.Material.Neon)
		for side = -1, 1, 2 do
			decoration(model, head, "CyberAntenna" .. side, Vector3.new(0.10, 0.78, 0.10), look.Wing,
				CFrame.new(side * 0.38, 0.84, 0.12) * CFrame.Angles(0, 0, math.rad(side * -20)), nil, Enum.Material.Metal)
			decoration(model, head, "CyberNode" .. side, Vector3.new(0.24, 0.24, 0.24), look.Glow,
				CFrame.new(side * 0.52, 1.20, 0.12), Enum.PartType.Ball, Enum.Material.Neon)
		end
		for row = 1, 3 do
			decoration(model, torso, "CircuitPlate" .. row, Vector3.new(0.58 + row * 0.16, 0.10, 0.26), look.Glow,
				CFrame.new(0, 0.24 + row * 0.28, -1.28), nil, Enum.Material.Neon)
		end
	elseif look.Style == "Dragon" then
		for side = -1, 1, 2 do
			decoration(model, head, "DragonHorn" .. side, Vector3.new(0.20, 1.02, 0.20), look.Beak,
				CFrame.new(side * 0.42, 0.92, 0.20) * CFrame.Angles(math.rad(-18), 0, math.rad(side * -30)), nil, Enum.Material.Neon)
		end
		for i = 1, 6 do
			decoration(model, torso, "DragonSpine" .. i, Vector3.new(0.16, 0.72 + i * 0.08, 0.34),
				i % 2 == 0 and look.Glow or look.Beak,
				CFrame.new(0, 0.76 + (i % 2) * 0.12, -0.82 + i * 0.48)
					* CFrame.Angles(math.rad(12), 0, math.rad(45)), nil, Enum.Material.Neon)
		end
		for side = -1, 1, 2 do
			decoration(model, torso, "DragonTailFin" .. side, Vector3.new(0.14, 0.72, 0.90), look.Glow,
				CFrame.new(side * 0.42, 0.44, 1.88) * CFrame.Angles(math.rad(-14), 0, math.rad(side * 36)), nil, Enum.Material.Neon)
		end
	elseif look.Style == "Rift" then
		for i = 1, 11 do
			local a = (i - 1) * math.pi * 2 / 11
			local height = 0.44 + (i % 4) * 0.22
			decoration(model, torso, "RiftShard" .. i, Vector3.new(0.16, height, 0.20),
				i % 2 == 0 and look.Glow or look.Head,
				CFrame.new(math.cos(a) * (1.05 + (i % 3) * 0.20), 0.42 + math.sin(a * 2) * 0.54, math.sin(a) * 1.34)
					* CFrame.Angles(a * 0.5, -a, math.rad(35 + i * 7)), nil,
				i % 3 == 0 and Enum.Material.ForceField or Enum.Material.Neon)
		end
		decoration(model, torso, "RiftCore", Vector3.new(0.46, 0.72, 0.28), Color3.fromRGB(8, 5, 18),
			CFrame.new(0, 0.48, -1.34), nil, Enum.Material.Glass)
	elseif look.Style == "Genesis" then
		decoration(model, head, "GenesisStem", Vector3.new(0.12, 0.76, 0.12), look.Beak,
			CFrame.new(0, 0.94, 0) * CFrame.Angles(0, 0, math.rad(-12)), nil, Enum.Material.Neon)
		for side = -1, 1, 2 do
			decoration(model, head, "GenesisLeaf" .. side, Vector3.new(0.18, 0.28, 0.58),
				side == -1 and look.Glow or look.Wing,
				CFrame.new(side * 0.28, 1.20, 0) * CFrame.Angles(0, 0, math.rad(side * 42)), Enum.PartType.Ball, Enum.Material.Neon)
		end
		for i = 1, 10 do
			local a = (i - 1) * math.pi * 2 / 10
			decoration(model, torso, "GenesisStar" .. i, Vector3.new(0.18, 0.18, 0.18),
				Color3.fromHSV((i - 1) / 10, 0.48, 1),
				CFrame.new(math.cos(a) * 1.25, 0.64 + math.sin(a * 3) * 0.30, math.sin(a) * 1.25),
				Enum.PartType.Ball, Enum.Material.Neon)
		end
	end
end

local function addProceduralAura(root: BasePart, look)
	if not look.Procedural or not look.Glow then
		return
	end
	local tier = look.Tier or "Soft"
	local rates = { Soft = 3, Bright = 7, Royal = 11, Unknown = 16, Myth = 24 }
	local brightness = { Soft = 0, Bright = 0.8, Royal = 1.5, Unknown = 2.4, Myth = 3.4 }
	local rate = rates[tier] or 3
	local lightPower = brightness[tier] or 0

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "ProceduralAura"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(look.Glow)
	emitter.LightEmission = 1
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.7, 1.4)
	emitter.Speed = NumberRange.new(0.25, 0.8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.36),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = root

	if lightPower > 0 then
		local light = Instance.new("PointLight")
		light.Name = "ProceduralGlow"
		light.Color = look.Glow
		light.Brightness = lightPower
		light.Range = 8 + lightPower * 4
		light.Shadows = false
		light.Parent = root
	end
end

function ModelFactory.buildGoose(gooseId: string, modelName: string): Model
	local look = gooseLook(gooseId)

	local model = Instance.new("Model")
	model.Name = modelName

	local root = newPart("HumanoidRootPart", Vector3.new(1.7, 1.5, 2.6), look.Body)
	root.Transparency = 1
	root.Parent = model
	model.PrimaryPart = root

	local parts: { [string]: BasePart } = { HumanoidRootPart = root }

	for _, bone in ipairs(GOOSE_BONES) do
		local part = newPart(bone.name, bone.size, look[bone.role] or look.Body)
		if bone.role ~= "Eye" and look.Material then
			part.Material = look.Material
		end
		if bone.role ~= "Eye" and look.Reflectance then
			part.Reflectance = look.Reflectance
		end
		part.Parent = model
		parts[bone.name] = part

		local parent = parts[bone.parent]
		joint(bone.name == "Torso" and "RootJoint" or bone.name, parent, part, CFrame.new(bone.at))
	end

	--[[
		관절이 자리를 잡기 전에 파트를 제 위치로 옮겨 둔다.

		이걸 안 하면 모델이 복제된 직후 한 프레임 동안 모든 파트가
		원점에 겹쳐 있고, 그 순간 크기를 재면 엉뚱한 값이 나온다.
	]]
	local function place(name: string, at: CFrame)
		parts[name].CFrame = at
		for _, bone in ipairs(GOOSE_BONES) do
			if bone.parent == name then
				place(bone.name, at * CFrame.new(bone.at))
			end
		end
	end
	place("HumanoidRootPart", CFrame.new())

	decorateGoose(model, parts, look)
	-- 프로필별 클라이언트 VFX가 연출을 담당한다. 같은 서버 파티클을 중복으로 달지 않는다.

	local controller = Instance.new("AnimationController")
	controller.Name = "AnimationController"
	controller.Parent = model

	local animator = Instance.new("Animator")
	animator.Parent = controller

	return model
end

function ModelFactory.buildEgg(eggId: string, modelName: string): Model
	local cfg = EggConfig.get(eggId)
	local shell = (cfg and cfg.Color) or Color3.fromRGB(245, 240, 228)
	local accent = (cfg and cfg.Accent) or Color3.fromRGB(214, 200, 176)

	local model = Instance.new("Model")
	model.Name = modelName

	--[[
		부화 연출이 EggMesh1 을 위로 들어올리고 EggMesh2 에서 거위가 나온다.
		이름을 반드시 이렇게 맞춰야 한다.
	]]
	local bottom = newPart("EggMesh2", Vector3.new(2.3, 2.3, 2.3), shell, Enum.PartType.Ball)
	bottom.CFrame = CFrame.new()
	bottom.Parent = model
	model.PrimaryPart = bottom

	local bottomMesh = Instance.new("SpecialMesh")
	bottomMesh.MeshType = Enum.MeshType.Sphere
	bottomMesh.Scale = Vector3.new(1, 1.05, 1)
	bottomMesh.Parent = bottom

	local top = newPart("EggMesh1", Vector3.new(1.75, 1.75, 1.75), accent, Enum.PartType.Ball)
	top.CFrame = CFrame.new(0, 1.0, 0)
	top.Parent = model

	local topMesh = Instance.new("SpecialMesh")
	topMesh.MeshType = Enum.MeshType.Sphere
	topMesh.Scale = Vector3.new(1, 1.15, 1)
	topMesh.Parent = top

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bottom
	weld.Part1 = top
	weld.Parent = bottom

	--[[
		껍데기 무늬.

		예전에는 어느 알이든 점 다섯 개였다. 색이 비슷한 알끼리는
		손에 들었을 때 구분이 안 됐다. 이제 종류마다 새기는 방식이 다르다.
	]]
	local function attach(part: BasePart)
		part.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = bottom
		weld.Part1 = part
		weld.Parent = part
	end

	-- 같은 알은 언제 만들어도 같은 무늬여야 한다. 이름으로 씨앗을 만든다.
	local seed = 0
	for i = 1, #eggId do
		seed += string.byte(eggId, i) * i
	end
	local rng = Random.new(seed * 7919 + 13)
	local pattern = (cfg and cfg.Pattern) or "spots"

	if pattern == "stripes" then
		for i = 1, 4 do
			local band = newPart("Stripe" .. i, Vector3.new(2.34, 0.22, 2.34), accent, Enum.PartType.Ball)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = Vector3.new(1.005, 0.1, 1.005)
			mesh.Parent = band
			band.CFrame = bottom.CFrame * CFrame.new(0, -0.72 + i * 0.36, 0)
			attach(band)
		end

	elseif pattern == "rings" then
		for i = 1, 3 do
			local ring = newPart("Ring" .. i, Vector3.new(2.42, 2.42, 2.42), accent, Enum.PartType.Ball)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = Vector3.new(1.01, 0.06, 1.01)
			mesh.Parent = ring
			ring.CFrame = bottom.CFrame
				* CFrame.Angles(math.rad(i * 34), math.rad(i * 55), 0)
			attach(ring)
		end

	elseif pattern == "shards" then
		for i = 1, 7 do
			local shard = newPart("Shard" .. i, Vector3.new(0.18, 0.72, 0.14), accent)
			shard.Material = Enum.Material.Neon
			shard.CFrame = bottom.CFrame
				* CFrame.Angles(rng:NextNumber(-0.9, 0.9), rng:NextNumber(0, math.pi * 2), 0)
				* CFrame.new(0, 0, -1.08)
				* CFrame.Angles(0, 0, rng:NextNumber(-1, 1))
			attach(shard)
		end

	elseif pattern == "swirl" then
		for i = 1, 12 do
			local t = i / 12
			local dot = newPart("Swirl" .. i, Vector3.new(0.3, 0.3, 0.3), accent, Enum.PartType.Ball)
			dot.Material = Enum.Material.Neon
			dot.CFrame = bottom.CFrame
				* CFrame.Angles(math.rad(-70 + t * 140), math.rad(t * 540), 0)
				* CFrame.new(0, 0, -1.06)
			attach(dot)
		end

	elseif pattern == "crown" then
		local band = newPart("CrownBand", Vector3.new(2.36, 0.26, 2.36), accent, Enum.PartType.Ball)
		local bandMesh = Instance.new("SpecialMesh")
		bandMesh.MeshType = Enum.MeshType.Sphere
		bandMesh.Scale = Vector3.new(1.01, 0.12, 1.01)
		bandMesh.Parent = band
		band.Material = Enum.Material.Metal
		band.CFrame = bottom.CFrame * CFrame.new(0, 0.62, 0)
		attach(band)

		for i = 1, 6 do
			local yaw = (i - 1) * math.pi * 2 / 6
			local spike = newPart("CrownSpike" .. i, Vector3.new(0.16, 0.44, 0.16), accent)
			spike.Material = Enum.Material.Neon
			spike.CFrame = bottom.CFrame
				* CFrame.Angles(0, yaw, 0)
				* CFrame.new(0, 0.86, -0.78)
			attach(spike)
		end

	else
		for i = 1, 6 do
			local spot = newPart("Spot" .. i, Vector3.new(0.46, 0.46, 0.46), accent, Enum.PartType.Ball)
			spot.CFrame = bottom.CFrame
				* CFrame.Angles(rng:NextNumber(-0.7, 0.7), rng:NextNumber(0, math.pi * 2), 0)
				* CFrame.new(0, 0, -1.05)
			attach(spot)
		end
	end

	-- 룰렛 알은 금빛 궤도와 빛을 더해 일반 알과 확실히 구분한다.
	if eggId == "Wheel" then
		for i = 1, 12 do
			local yaw = (i - 1) * math.pi * 2 / 12
			local gem = newPart("WheelGem" .. i, Vector3.new(0.18, 0.18, 0.18), accent, Enum.PartType.Ball)
			gem.Material = Enum.Material.Neon
			gem.CFrame = bottom.CFrame * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, -1.34)
			gem.Parent = model
			local gemWeld = Instance.new("WeldConstraint")
			gemWeld.Part0 = bottom
			gemWeld.Part1 = gem
			gemWeld.Parent = gem
		end
		local light = Instance.new("PointLight")
		light.Name = "WheelGlow"
		light.Color = accent
		light.Brightness = 1.8
		light.Range = 9
		light.Parent = bottom
	end

	return model
end

return ModelFactory

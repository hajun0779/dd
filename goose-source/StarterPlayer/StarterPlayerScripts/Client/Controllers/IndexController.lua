--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local UI = require(Shared.UI.UIBuilder)
local Theme = require(Shared.UI.Theme)
local Atlas = require(Shared.UI.Atlas)
local EggVisual = require(Shared.UI.EggVisual)
local EggConfig = require(Shared.Config.EggConfig)
local GooseConfig = require(Shared.Config.GooseConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local VariantConfig = require(Shared.Config.VariantConfig)
local FloorConfig = require(Shared.Config.FloorConfig)
local GooseStats = require(Shared.Util.GooseStats)
local ModelFactory = require(Shared.Util.ModelFactory)
local Format = require(Shared.Util.Format)
local Localization = require(Shared.Locale.Localization)
local NetClient = require(Shared.Net.NetClient)

local IndexController = {}

local window
local dimmer: Frame
local pages: { [string]: ScrollingFrame } = {}
local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
assetsFolder = assetsFolder and assetsFolder:FindFirstChild("Geese")
local progressLabel: TextLabel
local currentTab = "geese"

--[[
	2층 퀘스트.

	도감을 FloorConfig.Required 개 채우면 기지 2층이 열린다.
	목표가 화면에 없으면 아무도 그게 조건인 줄 모른다.
]]
local questRoot: ImageLabel
local questTitle: TextLabel
local questCount: TextLabel
local questDone: TextLabel
local questBar

--- 서버가 세어 준 발견 수. 해금 판정과 같은 값을 봐야 한다.
local serverFound = nil

local discovered = { geese = {}, eggs = {} }

local TABS = {
	{ id = "geese", icon = "icon_goose", palette = "cyan" },
	{ id = "eggs", icon = "icon_egg", palette = "yellow" },
}

local GOOSE_ORDER = GooseConfig.Order or {}
if #GOOSE_ORDER == 0 then
	for gooseId in pairs(GooseConfig.Data) do
		table.insert(GOOSE_ORDER, gooseId)
	end
	table.sort(GOOSE_ORDER)
end

local function clear(frame: Instance)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

--[[
	칸에 마우스를 올리면 그 거위가 3D 로 돌아간다.

	미리 다 만들어 두면 도감 한 장에 뷰포트 수십 개가 돌아가서 무겁다.
	올렸을 때 만들고, 떼면 버린다.
]]
local function attachPreview(card: ImageLabel, gooseId: string)
	local viewport: ViewportFrame? = nil
	local spin: RBXScriptConnection? = nil

	local function stop()
		if spin then
			spin:Disconnect()
			spin = nil
		end
		if viewport then
			viewport:Destroy()
			viewport = nil
		end
	end

	local function build()
		if viewport then
			return
		end

		local template = assetsFolder and assetsFolder:FindFirstChild(gooseId)
		local model = template and template:Clone() or ModelFactory.buildGoose(gooseId, gooseId)
		if not model then
			return
		end

		viewport = UI.create("ViewportFrame", {
			Name = "Preview",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(76, 76),
			Position = UDim2.new(0.5, 0, 0, 8),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = card.ZIndex + 3,
			Parent = card,
		})

		local camera = Instance.new("Camera")
		camera.Parent = viewport
		viewport.CurrentCamera = camera

		model.Parent = viewport

		local _, size = model:GetBoundingBox()
		local distance = math.max(size.X, size.Y, size.Z) * 2.1
		local height = size.Y * 0.35
		local angle = 0

		spin = RunService.RenderStepped:Connect(function(dt)
			if not viewport or not model.Parent then
				return
			end
			angle += dt * 1.1
			local center = model:GetBoundingBox().Position
			camera.CFrame = CFrame.new(
				center + Vector3.new(math.sin(angle) * distance, height, math.cos(angle) * distance),
				center
			)
		end)
	end

	card.MouseEnter:Connect(build)
	card.MouseLeave:Connect(stop)
	card.Destroying:Once(stop)

	--[[
		휴대폰에는 마우스가 없다. 손가락을 대고 있는 동안 보여 준다.
	]]
	card.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			build()
		end
	end)
	card.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			task.delay(1.5, stop)
		end
	end)
end

local function buildEntry(parent: ScrollingFrame, order: number, options)
	local found = options.entry ~= nil
	local rarity = RarityConfig.get(options.rarity or "Common")

	local card = Atlas.new("ImageLabel", found and "panel_white" or "panel_dark", {
		Name = options.id,
		Size = UDim2.fromOffset(132, 156),
		LayoutOrder = order,
		ZIndex = parent.ZIndex + 1,
		Parent = parent,
	})

	Atlas.new("ImageLabel", Atlas.rarityFrame(options.rarity or "Common"), {
		Name = "Frame",
		Size = UDim2.fromScale(1, 1),
		transparency = found and 0 or 0.55,
		ZIndex = card.ZIndex + 4,
		Parent = card,
	})

	local icon = Atlas.icon(options.icon, {
		Name = "Icon",
		Size = UDim2.fromOffset(60, 60),
		Position = UDim2.new(0.5, 0, 0, 16),
		AnchorPoint = Vector2.new(0.5, 0),
		color = found and rarity.Glow or Color3.fromRGB(70, 76, 92),
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})

	-- 알 칸은 그 알의 색과 기호로 그린다. 등급 색만 쓰면 스물여섯이 여섯으로 뭉친다.
	if options.eggId then
		EggVisual.applyIcon(icon, options.eggId, { dim = not found })
	end

	if not found then
		UI.text({
			Name = "Unknown",
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.new(0.5, 0, 0, 16),
			AnchorPoint = Vector2.new(0.5, 0),
			text = "?",
			font = Theme.Font.Number,
			textColor = Color3.fromRGB(160, 170, 190),
			stroke = false,
			maxTextSize = 44,
			ZIndex = card.ZIndex + 3,
			Parent = card,
		})
	end

	UI.text({
		Name = "Name",
		Size = UDim2.new(0.92, 0, 0, 32),
		Position = UDim2.new(0.5, 0, 0, 82),
		AnchorPoint = Vector2.new(0.5, 0),
		text = found and options.name or "???",
		font = Theme.Font.Heading,
		textColor = found and Theme.Color.Text or Color3.fromRGB(150, 158, 176),
		stroke = false,
		maxTextSize = 15,
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})

	UI.text({
		Name = "Detail",
		Size = UDim2.new(0.92, 0, 0, 20),
		Position = UDim2.new(0.5, 0, 0, 116),
		AnchorPoint = Vector2.new(0.5, 0),
		text = found and options.detail or "",
		font = Theme.Font.Number,
		textColor = found and Theme.Color.Green or Theme.Color.TextMuted,
		stroke = false,
		maxTextSize = 14,
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})

	-- 발견한 거위만 미리보기를 붙인다. 못 본 것은 실루엣으로 남겨 둔다.
	if found and options.kind == "Goose" then
		attachPreview(card, options.id)
	end

	if found and options.entry.count and options.entry.count > 1 then
		UI.text({
			Name = "Count",
			Size = UDim2.new(0.9, 0, 0, 18),
			Position = UDim2.new(0.5, 0, 0, 136),
			AnchorPoint = Vector2.new(0.5, 0),
			text = "x" .. tostring(options.entry.count),
			font = Theme.Font.Number,
			textColor = Theme.Color.TextMuted,
			stroke = false,
			maxTextSize = 13,
			ZIndex = card.ZIndex + 2,
			Parent = card,
		})
	end

	return card
end

local function rebuild()
	local geesePage = pages.geese
	local eggsPage = pages.eggs
	if not geesePage or not eggsPage then
		return
	end

	clear(geesePage)
	clear(eggsPage)

	local foundCount, totalCount = 0, 0

	for order, gooseId in ipairs(GOOSE_ORDER) do
		local config = GooseConfig.get(gooseId)
		if config then
			totalCount += 1
			local entry = discovered.geese[gooseId]
			if entry then
				foundCount += 1
			end

			local detail = ""
			if entry then
				local sample = { kind = "Goose", gooseId = gooseId, rarity = entry.rarity or "Common", variant = "Normal", level = 1 }
				detail = Format.rate(GooseStats.gooseIncome(sample))
			end

			buildEntry(geesePage, order, {
				id = gooseId,
				kind = "Goose",
				icon = "icon_goose",
				name = Localization.t(config.LocaleKey),
				detail = detail,
				rarity = entry and entry.rarity or "Common",
				entry = entry,
			})
		end
	end

	for order, eggId in ipairs(EggConfig.IndexOrder or EggConfig.Order) do
		local config = EggConfig.get(eggId)
		if config then
			totalCount += 1
			local entry = discovered.eggs[eggId]
			if entry then
				foundCount += 1
			end

			local detail
			if config.Currency == "Cash" then
				detail = Format.money(config.Price)
			elseif config.Currency == "Robux" then
				detail = tostring(config.Price) .. " R$"
			else
				detail = Localization.t("egg_source_roulette")
			end

			buildEntry(eggsPage, order, {
				id = eggId,
				eggId = eggId,
				icon = "icon_egg",
				name = Localization.t(config.LocaleKey),
				detail = detail,
				rarity = "Common",
				entry = entry,
			})
		end
	end

	if progressLabel then
		progressLabel.Text = Localization.t("index_progress", foundCount, totalCount)
	end

	--[[
		퀘스트 줄.

		세는 값은 서버가 보내 준 것을 먼저 쓴다. 2층 해금이 그 값을 보고 판단하므로,
		화면만 따로 세면 30/30 인데 2층은 안 열리는 일이 생긴다.
	]]
	if questBar then
		local count = math.min(serverFound or foundCount, FloorConfig.Required)
		local done = count >= FloorConfig.Required

		questBar.set(count / math.max(FloorConfig.Required, 1))
		questCount.Text = string.format("%d / %d", count, FloorConfig.Required)
		Atlas.apply(questRoot, done and "panel_green" or "panel_cyan")
		questDone.Visible = done
		questCount.Visible = not done
		UI.setTextColor(questTitle, Theme.Color.TextInverse)
	end
end

function IndexController.setTab(id: string)
	currentTab = id
	for pageId, page in pairs(pages) do
		page.Visible = pageId == id
	end
	if window then
		window.setTabActive(id)
	end
end

--[[
	퀘스트 줄.

	진행 막대 하나에 숫자 하나. 다 채우면 숫자 자리에 DONE 이 들어서고
	줄 전체가 초록으로 바뀐다. 다 했는지를 색으로 먼저 알 수 있어야 한다.
]]
local function buildQuest(parent: Frame)
	questRoot = Atlas.new("ImageLabel", "panel_cyan", {
		Name = "Quest",
		Size = UDim2.new(1, 0, 0, 52),
		Position = UDim2.fromOffset(0, 28),
		ZIndex = parent.ZIndex + 2,
		Parent = parent,
	})

	Atlas.icon("icon_home", {
		Name = "Icon",
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromOffset(14, 12),
		color = Theme.Color.TextInverse,
		ZIndex = questRoot.ZIndex + 1,
		Parent = questRoot,
	})

	questTitle = UI.text({
		Name = "Title",
		Size = UDim2.fromOffset(230, 28),
		Position = UDim2.fromOffset(50, 12),
		localeKey = "index_quest_title",
		localeArgs = { FloorConfig.Required },
		font = Theme.Font.Heading,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = questRoot.ZIndex + 1,
		Parent = questRoot,
	})

	questBar = UI.bar({
		Name = "Bar",
		Size = UDim2.new(1, -400, 0, 20),
		Position = UDim2.fromOffset(288, 16),
		ZIndex = questRoot.ZIndex + 1,
		value = 0,
		Parent = questRoot,
	})

	questCount = UI.text({
		Name = "Count",
		Size = UDim2.fromOffset(96, 28),
		Position = UDim2.new(1, -14, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		text = "0 / " .. tostring(FloorConfig.Required),
		font = Theme.Font.Number,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = questRoot.ZIndex + 1,
		Parent = questRoot,
	})

	questDone = UI.text({
		Name = "Done",
		Size = UDim2.fromOffset(110, 30),
		Position = UDim2.new(1, -14, 0, 11),
		AnchorPoint = Vector2.new(1, 0),
		localeKey = "index_quest_done",
		font = Theme.Font.Number,
		textColor = Theme.Color.TextInverse,
		strokeColor = Theme.Color.Dark,
		stroke = 3,
		maxTextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		ZIndex = questRoot.ZIndex + 2,
		Parent = questRoot,
	})

	return questRoot
end

local function makePage(parent: Frame, id: string)
	local page = UI.create("ScrollingFrame", {
		Name = id,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -88),
		Position = UDim2.fromOffset(0, 88),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Color.Cyan,
		Visible = false,
		ZIndex = parent.ZIndex + 1,
		Parent = parent,
	})
	UI.grid({
		CellSize = UDim2.fromOffset(132, 156),
		CellPadding = UDim2.fromOffset(10, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, page)
	UI.padding(6, page)
	pages[id] = page
	return page
end

function IndexController.start(playerGui: PlayerGui)
	local screen = UI.create("ScreenGui", {
		Name = "RadIndex",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = Theme.Z.Panel,
		Parent = playerGui,
	})

	dimmer = UI.dimmer({ Parent = screen })

	window = UI.window({
		Name = "IndexWindow",
		localeKey = "menu_index",
		icon = "icon_index",
		Size = UDim2.fromOffset(760, 480),
		tabs = TABS,
		Parent = screen,
		onTab = function(id)
			IndexController.setTab(id)
		end,
		onClose = function()
			IndexController.close()
		end,
	})

	progressLabel = UI.text({
		Name = "Progress",
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 0),
		text = "",
		font = Theme.Font.Heading,
		textColor = Theme.Color.Text,
		stroke = false,
		maxTextSize = 20,
		ZIndex = window.content.ZIndex + 2,
		Parent = window.content,
	})

	buildQuest(window.content)

	makePage(window.content, "geese")
	makePage(window.content, "eggs")

	NetClient.on("IndexSync", function(data)
		if type(data) ~= "table" then
			return
		end
		discovered.geese = data.geese or {}
		discovered.eggs = data.eggs or {}
		if type(data.found) == "number" then
			serverFound = data.found
		end
		rebuild()
	end)

	Localization.Changed:Connect(rebuild)

	IndexController.setTab("geese")
	rebuild()

	IndexController.screen = screen
	return screen
end

function IndexController.open()
	if not window then
		return
	end
	dimmer.Visible = true
	window.open()
	IndexController.setTab(currentTab)
	rebuild()
end

function IndexController.close()
	if not window then
		return
	end
	dimmer.Visible = false
	window.close()
end

function IndexController.toggle()
	if window and window.root.Visible then
		IndexController.close()
	else
		IndexController.open()
	end
end

return IndexController

--!nonstrict

-- 새 LocalScript로 StarterPlayerScripts에 넣는다.
-- 기존 상점은 그대로 두고 룰렛 탭과 알 정보 버튼만 추가한다.
-- 화면에 보이는 룰렛 패널/버튼/아이콘/링은 모두 기존 RadAtlas를 사용한다.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(Shared.UI.UIBuilder)
local Theme = require(Shared.UI.Theme)
local Atlas = require(Shared.UI.Atlas)
local EggVisual = require(Shared.UI.EggVisual)
local EggConfig = require(Shared.Config.EggConfig)
local GooseConfig = require(Shared.Config.GooseConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local RouletteConfig = require(Shared.Config.RouletteConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Format = require(Shared.Util.Format)
local Localization = require(Shared.Locale.Localization)
local NetClient = require(Shared.Net.NetClient)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local clientRoot = script.Parent:WaitForChild("Client")
local NotifyController = require(clientRoot.Controllers.NotifyController)
local ShopController = require(clientRoot.Controllers.ShopController)

local screen: ScreenGui
local dimmer: Frame
local wheelWindow
local oddsWindow
local wheelDisc: Frame
local spinButton: ImageButton
local timerLabel: TextLabel
local paidLabel: TextLabel
local rewardList: ScrollingFrame
local oddsList: ScrollingFrame
local oddsLuck: TextLabel
local buyOneButton: ImageButton
local buyThreeButton: ImageButton

local rewardGlows = {}
local state = nil
local stateAt = 0
local secondsAt = 0
local spinning = false
local fetchingState = false
local lastStateFetch = 0
local lastPurchasePrompt = 0

local currentOddsEggId = nil
local currentOddsData = nil
local oddsFailed = false
local oddsRequestId = 0

local closing = {}
local queuedOpen = {}

local function setButtonText(button: GuiButton?, text: string)
	if not button then
		return
	end
	local label = button:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function rewardName(reward): string
	if not reward then
		return "?"
	end
	if reward.kind == "Cash" or reward.Kind == "Cash" then
		return Format.money(reward.amount or reward.Amount or 0)
	end
	local eggId = reward.eggId or reward.EggId
	local egg = eggId and EggConfig.get(eggId)
	local name = egg and Localization.t(egg.LocaleKey) or tostring(eggId or "?")
	local amount = reward.amount or reward.Amount or 1
	return amount > 1 and (name .. " x" .. tostring(amount)) or name
end

local function formatDuration(seconds: number): string
	seconds = math.max(math.floor(seconds), 0)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	local secs = seconds % 60
	return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

local function percentText(value: number): string
	if value >= 1 then
		return string.format("%.2f%%", value)
	elseif value >= 0.01 then
		return string.format("%.3f%%", value)
	end
	return string.format("%.5f%%", value)
end

local function clearGuiRows(frame: Instance)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- UI.window.close()는 애니메이션이 끝난 뒤에 Visible=false로 바꾼다.
-- 따라서 닫기 버튼을 누른 순간이 아니라 실제 Visible 상태를 기준으로 디머를 관리한다.
local function refreshDimmer()
	if not dimmer then
		return
	end
	local wheelVisible = wheelWindow and wheelWindow.root and wheelWindow.root.Visible
	local oddsVisible = oddsWindow and oddsWindow.root and oddsWindow.root.Visible
	local visible = wheelVisible == true or oddsVisible == true
	dimmer.Visible = visible
	dimmer.Active = visible
end

local function openModal(api)
	if not api or not api.root or not api.root.Parent then
		return
	end
	if closing[api] then
		queuedOpen[api] = true
		return
	end
	dimmer.Visible = true
	dimmer.Active = true
	api.open()
	task.defer(refreshDimmer)
end

local function closeModal(api)
	if not api or not api.root or not api.root.Parent then
		refreshDimmer()
		return
	end
	if closing[api] or not api.root.Visible then
		refreshDimmer()
		return
	end

	closing[api] = true
	api.close()

	-- 공통 닫기 트윈(0.12초)보다 조금 뒤에 상태를 정리한다.
	task.delay(0.22, function()
		closing[api] = nil
		refreshDimmer()
		if queuedOpen[api] then
			queuedOpen[api] = nil
			openModal(api)
		end
	end)
end

local function closeOdds()
	oddsRequestId += 1
	closeModal(oddsWindow)
end

local function remainingSeconds(): number
	if not state then
		return 0
	end
	return math.max(secondsAt - (os.clock() - stateAt), 0)
end

local function refreshStateText()
	if not timerLabel or not paidLabel or not spinButton then
		return
	end

	if not state then
		timerLabel.Text = Localization.t("common_loading")
		paidLabel.Text = ""
		setButtonText(spinButton, Localization.t("common_loading"))
		spinButton.Active = false
		spinButton.Selectable = false
		Atlas.apply(spinButton, "btn_gray")
		return
	end

	if (state.freeSpins or 0) > 0 then
		timerLabel.Text = Localization.t("roulette_free_ready", state.freeSpins)
	elseif state.dailyMode then
		timerLabel.Text = Localization.t("roulette_daily_return")
	else
		timerLabel.Text = Localization.t("roulette_next_free", formatDuration(remainingSeconds()))
	end
	paidLabel.Text = Localization.t("roulette_paid_spins", state.paidSpins or 0)

	local hasPending = state.pendingReward ~= nil
	local canSpin = hasPending or (state.availableSpins or 0) > 0
	if spinning then
		setButtonText(spinButton, "...")
	elseif hasPending then
		setButtonText(spinButton, Localization.t("roulette_claim"))
	else
		setButtonText(spinButton, Localization.t("roulette_spin", state.availableSpins or 0))
	end

	spinButton.Active = canSpin and not spinning
	spinButton.Selectable = canSpin and not spinning
	Atlas.apply(spinButton, canSpin and not spinning and "btn_purple" or "btn_gray")
end

local function applyState(newState)
	if type(newState) ~= "table" or not newState.ok then
		return
	end
	state = newState
	stateAt = os.clock()
	secondsAt = math.max(tonumber(newState.secondsToFree) or 0, 0)
	refreshStateText()
end

local function fetchState()
	if fetchingState then
		return
	end
	fetchingState = true
	lastStateFetch = os.clock()
	task.spawn(function()
		local result = NetClient.invoke("RouletteGetState", 8)
		fetchingState = false
		if screen and screen.Parent then
			applyState(result)
		end
	end)
end

local function makeAtlasIconButton(props)
	local button = UI.menuButton({
		Name = props.Name,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		icon = props.icon,
		palette = props.palette or "cyan",
		text = "",
		ZIndex = props.ZIndex,
		Parent = props.Parent,
		onClick = props.onClick,
	})
	local label = button:FindFirstChild("Label")
	if label then
		label:Destroy()
	end
	local icon = button:FindFirstChild("Icon")
	if icon then
		icon.Size = UDim2.fromScale(0.58, 0.58)
		icon.Position = UDim2.fromScale(0.5, 0.5)
	end
	return button
end

local function renderRewardList()
	if not rewardList then
		return
	end
	clearGuiRows(rewardList)

	local total = math.max(RouletteConfig.totalWeight(), 1)
	for order, reward in ipairs(RouletteConfig.Rewards) do
		local palette = reward.Palette or "cyan"
		local row = Atlas.new("ImageLabel", "panel_" .. palette, {
			Name = reward.Id,
			Size = UDim2.new(1, -4, 0, 34),
			LayoutOrder = order,
			ZIndex = rewardList.ZIndex + 1,
			Parent = rewardList,
		})
		local textColor = Theme.PaletteTextColor[palette] or Theme.Color.TextInverse

		local rowIcon = Atlas.icon(reward.Icon or "icon_star", {
			Name = "Icon",
			Size = UDim2.fromOffset(25, 25),
			Position = UDim2.fromOffset(7, 4),
			color = textColor,
			ZIndex = row.ZIndex + 1,
			Parent = row,
		})
		-- 알 보상은 그 알의 색과 기호로 보여 준다
		if reward.EggId or reward.eggId then
			EggVisual.applyIcon(rowIcon, reward.EggId or reward.eggId)
		end
		UI.text({
			Name = "Reward",
			Size = UDim2.new(1, -112, 1, 0),
			Position = UDim2.fromOffset(38, 0),
			text = tostring(order) .. ". " .. rewardName(reward),
			font = Theme.Font.Heading,
			textColor = textColor,
			stroke = false,
			maxTextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = row.ZIndex + 1,
			Parent = row,
		})
		UI.text({
			Name = "Chance",
			Size = UDim2.fromOffset(70, 28),
			Position = UDim2.new(1, -6, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			text = percentText(reward.Weight / total * 100),
			font = Theme.Font.Number,
			textColor = textColor,
			stroke = false,
			maxTextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = row.ZIndex + 1,
			Parent = row,
		})
	end
end

local function renderOdds(loading: boolean?, failed: boolean?)
	if not oddsList then
		return
	end
	clearGuiRows(oddsList)

	if loading or failed or not currentOddsData then
		local card = Atlas.new("ImageLabel", failed and "panel_red" or "panel_dark", {
			Name = failed and "Failed" or "Loading",
			Size = UDim2.new(1, -8, 0, 58),
			LayoutOrder = 1,
			ZIndex = oddsList.ZIndex + 1,
			Parent = oddsList,
		})
		Atlas.icon(failed and "icon_warning" or "icon_refresh", {
			Size = UDim2.fromOffset(34, 34),
			Position = UDim2.fromOffset(12, 12),
			color = Theme.Color.TextInverse,
			ZIndex = card.ZIndex + 1,
			Parent = card,
		})
		UI.text({
			Size = UDim2.new(1, -62, 1, 0),
			Position = UDim2.fromOffset(54, 0),
			text = Localization.t(failed and "egg_odds_failed" or "common_loading"),
			font = Theme.Font.Heading,
			textColor = Theme.Color.TextInverse,
			maxTextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = card.ZIndex + 1,
			Parent = card,
		})
		return
	end

	for order, entry in ipairs(currentOddsData.entries or {}) do
		local rarity = RarityConfig.get(entry.rarity)
		local goose = GooseConfig.get(entry.gooseId)
		local row = Atlas.new("ImageLabel", "panel_white", {
			Name = entry.gooseId .. "_" .. entry.rarity,
			Size = UDim2.new(1, -8, 0, 54),
			LayoutOrder = order,
			ZIndex = oddsList.ZIndex + 1,
			Parent = oddsList,
		})

		local rarityFrame = Atlas.new("ImageLabel", Atlas.rarityFrame(entry.rarity), {
			Name = "RarityFrame",
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.fromOffset(6, 5),
			ZIndex = row.ZIndex + 1,
			Parent = row,
		})
		Atlas.icon("icon_goose", {
			Size = UDim2.fromScale(0.62, 0.62),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			color = rarity.Glow,
			ZIndex = rarityFrame.ZIndex + 1,
			Parent = rarityFrame,
		})

		UI.text({
			Name = "Name",
			Size = UDim2.new(1, -190, 0, 28),
			Position = UDim2.fromOffset(58, 4),
			text = goose and Localization.t(goose.LocaleKey) or entry.gooseId,
			font = Theme.Font.Heading,
			textColor = Theme.Color.Text,
			stroke = false,
			maxTextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = row.ZIndex + 1,
			Parent = row,
		})
		UI.text({
			Name = "Rarity",
			Size = UDim2.new(1, -190, 0, 20),
			Position = UDim2.fromOffset(58, 30),
			text = Localization.t(rarity.LocaleKey),
			font = Theme.Font.Body,
			textColor = rarity.Color,
			stroke = false,
			maxTextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = row.ZIndex + 1,
			Parent = row,
		})

		local chanceBadge = Atlas.new("ImageLabel", "panel_dark", {
			Name = "ChanceBadge",
			Size = UDim2.fromOffset(118, 38),
			Position = UDim2.new(1, -8, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			ZIndex = row.ZIndex + 1,
			Parent = row,
		})
		UI.text({
			Name = "Chance",
			Size = UDim2.new(1, -10, 1, -4),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			text = percentText(tonumber(entry.percent) or 0),
			font = Theme.Font.Number,
			textColor = rarity.Glow,
			maxTextSize = 18,
			ZIndex = chanceBadge.ZIndex + 1,
			Parent = chanceBadge,
		})
	end
end

local function refreshOddsHeader()
	if not oddsWindow or not oddsWindow.title then
		return
	end
	local egg = currentOddsEggId and EggConfig.get(currentOddsEggId)
	if egg then
		oddsWindow.title.Text = Localization.t("egg_odds_title", Localization.t(egg.LocaleKey))
	end
	if currentOddsData then
		oddsLuck.Text = Localization.t("egg_odds_luck", tonumber(currentOddsData.luck) or 1)
	elseif oddsLuck then
		oddsLuck.Text = oddsFailed and "" or Localization.t("common_loading")
	end
end

local function showOdds(eggId: string)
	local egg = EggConfig.get(eggId)
	if not egg or not oddsWindow then
		return
	end

	currentOddsEggId = eggId
	currentOddsData = nil
	oddsFailed = false
	oddsRequestId += 1
	local requestId = oddsRequestId

	refreshOddsHeader()
	renderOdds(true, false)
	openModal(oddsWindow)

	task.spawn(function()
		local result = NetClient.invoke("EggOddsGet", 8, eggId)
		if requestId ~= oddsRequestId or not screen or not screen.Parent then
			return
		end
		if not result or not result.ok then
			oddsFailed = true
			oddsLuck.Text = ""
			renderOdds(false, true)
			NotifyController.toast({ key = "egg_odds_failed", kind = "error" })
			return
		end

		currentOddsData = result
		oddsFailed = false
		refreshOddsHeader()
		renderOdds(false, false)
	end)
end

local function clearRewardHighlight()
	for _, glow in ipairs(rewardGlows) do
		if glow and glow.Parent then
			glow.Visible = false
		end
	end
end

local function animateWheel(index: number)
	if not wheelDisc then
		return
	end
	clearRewardHighlight()

	local count = math.max(#RouletteConfig.Rewards, 1)
	local step = 360 / count
	local current = wheelDisc.Rotation % 360
	local desired = (360 - (index - 1) * step) % 360
	local extra = (desired - current) % 360
	local target = wheelDisc.Rotation + 5 * 360 + extra

	local ticking = true
	task.spawn(function()
		for i = 1, 16 do
			if not ticking then
				break
			end
			if wheelWindow and wheelWindow.root.Visible then
				UI.playSound(Theme.Sound.Tick, 0.22)
			end
			task.wait(0.07 + i * 0.016)
		end
	end)

	local tween = TweenService:Create(
		wheelDisc,
		TweenInfo.new(4.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Rotation = target }
	)
	tween:Play()
	tween.Completed:Wait()
	ticking = false
	wheelDisc.Rotation %= 360

	local glow = rewardGlows[index]
	if glow and glow.Parent then
		glow.Visible = true
	end
	UI.playSound(Theme.Sound.Success, 0.7)
end

local function handleSpin()
	if spinning or not state then
		return
	end
	local hadPending = state.pendingReward ~= nil
	if not hadPending and (state.availableSpins or 0) <= 0 then
		return
	end

	spinning = true
	refreshStateText()
	local result = NetClient.invoke("RouletteSpin", 15)

	if result and result.reward and result.index and not hadPending then
		animateWheel(result.index)
	end
	if result and result.state then
		applyState(result.state)
	else
		fetchState()
	end

	if result and result.ok then
		NotifyController.toast({
			key = "roulette_reward_received",
			args = { rewardName(result.reward) },
			kind = "success",
			icon = result.reward and result.reward.icon or "icon_star",
			duration = 5,
		})
	else
		local reason = result and result.reason
		local key = "roulette_no_spin"
		if reason == "inventory_full" then
			key = "roulette_inventory_full"
		elseif reason == "save_busy" or reason == "rate_limited" or not result then
			key = "roulette_save_busy"
		elseif result and result.pending then
			key = "roulette_pending"
		end
		NotifyController.toast({
			key = key,
			kind = reason == "inventory_full" and "error" or "warning",
			duration = 6,
		})
	end

	spinning = false
	refreshStateText()
end

local function promptProduct(key: string)
	if os.clock() - lastPurchasePrompt < 1.5 then
		return
	end
	lastPurchasePrompt = os.clock()

	local product = MonetizationConfig.getProduct(key)
	if not product or not product.productId or product.productId == 0 then
		NotifyController.toast({ key = "roulette_product_missing", kind = "error", duration = 5 })
		return
	end

	local ok = pcall(function()
		MarketplaceService:PromptProductPurchase(player, product.productId)
	end)
	if not ok then
		NotifyController.toast({ key = "roulette_product_missing", kind = "error", duration = 5 })
	end
end

local function refreshProductButtons()
	local one = MonetizationConfig.getProduct(RouletteConfig.Products.One)
	local three = MonetizationConfig.getProduct(RouletteConfig.Products.Three)
	setButtonText(
		buyOneButton,
		Localization.t("roulette_buy_1") .. "  ·  " .. tostring(one and one.robux or 49) .. " R$"
	)
	setButtonText(
		buyThreeButton,
		Localization.t("roulette_buy_3") .. "  ·  " .. tostring(three and three.robux or 119) .. " R$"
	)
end

local function buildOddsWindow()
	oddsWindow = UI.window({
		Name = "EggOddsWindow",
		text = "Odds",
		icon = "icon_info",
		Size = UDim2.fromOffset(620, 520),
		ZIndex = Theme.Z.Modal + 12,
		Parent = screen,
		onClose = closeOdds,
	})

	local luckPanel = Atlas.new("ImageLabel", "panel_purple", {
		Name = "LuckPanel",
		Size = UDim2.new(1, -12, 0, 36),
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = oddsWindow.content.ZIndex + 1,
		Parent = oddsWindow.content,
	})
	Atlas.icon("icon_luck", {
		Size = UDim2.fromOffset(27, 27),
		Position = UDim2.fromOffset(9, 4),
		color = Theme.Color.TextInverse,
		ZIndex = luckPanel.ZIndex + 1,
		Parent = luckPanel,
	})
	oddsLuck = UI.text({
		Name = "Luck",
		Size = UDim2.new(1, -52, 1, 0),
		Position = UDim2.fromOffset(42, 0),
		text = "",
		font = Theme.Font.Heading,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = luckPanel.ZIndex + 1,
		Parent = luckPanel,
	})

	local listPanel = Atlas.new("ImageLabel", "panel_gray", {
		Name = "ListPanel",
		Size = UDim2.new(1, -12, 1, -44),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = oddsWindow.content.ZIndex + 1,
		Parent = oddsWindow.content,
	})
	oddsList = UI.create("ScrollingFrame", {
		Name = "OddsList",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -14, 1, -14),
		Position = UDim2.fromOffset(7, 7),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Color.Cyan,
		ZIndex = listPanel.ZIndex + 1,
		Parent = listPanel,
	})
	UI.list({ Padding = UDim.new(0, 6) }, oddsList)
	UI.padding(3, oddsList)
end

local function buildWheelPods(parent: Frame, center: Vector2, radius: number)
	local count = math.max(#RouletteConfig.Rewards, 1)
	for index, reward in ipairs(RouletteConfig.Rewards) do
		local angle = math.rad((index - 1) * (360 / count) - 90)
		local position = center + Vector2.new(math.cos(angle), math.sin(angle)) * radius

		local holder = UI.create("Frame", {
			Name = "Reward" .. index,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(64, 64),
			Position = UDim2.fromOffset(position.X, position.Y),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = parent.ZIndex + 2,
			Parent = parent,
		})
		local glow = Atlas.new("ImageLabel", "glow_soft", {
			Name = "SelectedGlow",
			Size = UDim2.fromOffset(78, 78),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			color = Color3.fromRGB(255, 238, 120),
			Visible = false,
			ZIndex = holder.ZIndex,
			Parent = holder,
		})
		rewardGlows[index] = glow

		local palette = reward.Palette or "cyan"
		local pod = Atlas.new("ImageLabel", "btn_" .. palette, {
			Name = "Pod",
			Size = UDim2.fromOffset(57, 57),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = holder.ZIndex + 1,
			Parent = holder,
		})
		local textColor = Theme.PaletteTextColor[palette] or Theme.Color.TextInverse
		local podIcon = Atlas.icon(reward.Icon or "icon_star", {
			Name = "RewardIcon",
			Size = UDim2.fromScale(0.50, 0.50),
			Position = UDim2.fromScale(0.5, 0.43),
			AnchorPoint = Vector2.new(0.5, 0.5),
			color = textColor,
			ZIndex = pod.ZIndex + 1,
			Parent = pod,
		})
		if reward.EggId or reward.eggId then
			EggVisual.applyIcon(podIcon, reward.EggId or reward.eggId)
		end

		local badge = Atlas.new("ImageLabel", "panel_dark", {
			Name = "Index",
			Size = UDim2.fromOffset(23, 20),
			Position = UDim2.new(1, -2, 1, -2),
			AnchorPoint = Vector2.new(1, 1),
			ZIndex = pod.ZIndex + 2,
			Parent = pod,
		})
		UI.text({
			Size = UDim2.fromScale(1, 1),
			text = tostring(index),
			font = Theme.Font.Number,
			textColor = Theme.Color.TextInverse,
			stroke = false,
			maxTextSize = 12,
			ZIndex = badge.ZIndex + 1,
			Parent = badge,
		})
	end
end

local function buildWheelWindow()
	wheelWindow = UI.window({
		Name = "RouletteWindow",
		localeKey = "roulette_title",
		icon = "icon_spin",
		Size = UDim2.fromOffset(820, 540),
		ZIndex = Theme.Z.Modal + 4,
		Parent = screen,
		onClose = function()
			closeModal(wheelWindow)
		end,
	})

	local banner = Atlas.new("ImageLabel", "panel_purple", {
		Name = "RuleBanner",
		Size = UDim2.new(1, 0, 0, 30),
		ZIndex = wheelWindow.content.ZIndex + 1,
		Parent = wheelWindow.content,
	})
	Atlas.icon("icon_clock", {
		Size = UDim2.fromOffset(23, 23),
		Position = UDim2.fromOffset(10, 3),
		color = Theme.Color.TextInverse,
		ZIndex = banner.ZIndex + 1,
		Parent = banner,
	})
	UI.text({
		Name = "Rule",
		Size = UDim2.new(1, -46, 1, 0),
		Position = UDim2.fromOffset(40, 0),
		localeKey = "roulette_rule",
		font = Theme.Font.Heading,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = banner.ZIndex + 1,
		Parent = banner,
	})

	local wheelPanel = Atlas.new("ImageLabel", "panel_dark", {
		Name = "WheelPanel",
		Size = UDim2.fromOffset(440, 300),
		Position = UDim2.fromOffset(0, 36),
		ZIndex = wheelWindow.content.ZIndex + 1,
		Parent = wheelWindow.content,
	})
	Atlas.new("ImageLabel", "shine_burst", {
		Name = "Burst",
		Size = UDim2.fromOffset(294, 294),
		Position = UDim2.fromOffset(220, 150),
		AnchorPoint = Vector2.new(0.5, 0.5),
		color = Color3.fromRGB(130, 214, 255),
		transparency = 0.45,
		ZIndex = wheelPanel.ZIndex + 1,
		Parent = wheelPanel,
	})

	wheelDisc = UI.create("Frame", {
		Name = "Wheel",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(280, 280),
		Position = UDim2.fromOffset(220, 150),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = wheelPanel.ZIndex + 2,
		Parent = wheelPanel,
	})
	Atlas.new("ImageLabel", "ring_track", {
		Name = "Track",
		Size = UDim2.fromOffset(276, 276),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		color = Color3.fromRGB(220, 238, 255),
		ZIndex = wheelDisc.ZIndex,
		Parent = wheelDisc,
	})
	Atlas.new("ImageLabel", "ring_zone", {
		Name = "Zone",
		Size = UDim2.fromOffset(266, 266),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		color = Color3.fromRGB(255, 220, 88),
		transparency = 0.28,
		ZIndex = wheelDisc.ZIndex + 1,
		Parent = wheelDisc,
	})
	buildWheelPods(wheelDisc, Vector2.new(140, 140), 101)

	local hubGlow = Atlas.new("ImageLabel", "glow_soft", {
		Name = "HubGlow",
		Size = UDim2.fromOffset(98, 98),
		Position = UDim2.fromOffset(220, 150),
		AnchorPoint = Vector2.new(0.5, 0.5),
		color = Color3.fromRGB(255, 224, 92),
		ZIndex = wheelPanel.ZIndex + 8,
		Parent = wheelPanel,
	})
	local hub = Atlas.new("ImageLabel", "btn_yellow", {
		Name = "Hub",
		Size = UDim2.fromOffset(72, 72),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = hubGlow.ZIndex + 1,
		Parent = hubGlow,
	})
	Atlas.icon("icon_spin", {
		Size = UDim2.fromScale(0.54, 0.54),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		color = Theme.Color.Purple,
		ZIndex = hub.ZIndex + 1,
		Parent = hub,
	})

	Atlas.icon("icon_arrow_d", {
		Name = "Pointer",
		Size = UDim2.fromOffset(48, 48),
		Position = UDim2.fromOffset(220, 3),
		AnchorPoint = Vector2.new(0.5, 0),
		color = Theme.Color.Red,
		ZIndex = wheelPanel.ZIndex + 12,
		Parent = wheelPanel,
	})

	local rewardPanel = Atlas.new("ImageLabel", "panel_blue", {
		Name = "RewardPanel",
		Size = UDim2.fromOffset(324, 300),
		Position = UDim2.fromOffset(452, 36),
		ZIndex = wheelWindow.content.ZIndex + 1,
		Parent = wheelWindow.content,
	})
	local rewardHeader = Atlas.new("ImageLabel", "panel_dark", {
		Name = "Header",
		Size = UDim2.new(1, -12, 0, 32),
		Position = UDim2.fromOffset(6, 5),
		ZIndex = rewardPanel.ZIndex + 1,
		Parent = rewardPanel,
	})
	Atlas.icon("icon_trophy", {
		Size = UDim2.fromOffset(23, 23),
		Position = UDim2.fromOffset(8, 4),
		color = Theme.Color.Yellow,
		ZIndex = rewardHeader.ZIndex + 1,
		Parent = rewardHeader,
	})
	UI.text({
		Size = UDim2.new(1, -44, 1, 0),
		Position = UDim2.fromOffset(38, 0),
		localeKey = "roulette_rewards",
		font = Theme.Font.Heading,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = rewardHeader.ZIndex + 1,
		Parent = rewardHeader,
	})

	rewardList = UI.create("ScrollingFrame", {
		Name = "RewardList",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -14, 0, 218),
		Position = UDim2.fromOffset(7, 42),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Color.Cyan,
		ZIndex = rewardPanel.ZIndex + 1,
		Parent = rewardPanel,
	})
	UI.list({ Padding = UDim.new(0, 4) }, rewardList)
	UI.padding(2, rewardList)

	UI.button({
		Name = "WheelEggOdds",
		palette = "yellow",
		localeKey = "roulette_egg_odds",
		icon = "icon_info",
		Size = UDim2.new(1, -16, 0, 31),
		Position = UDim2.new(0.5, 0, 1, -6),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = rewardPanel.ZIndex + 2,
		Parent = rewardPanel,
		onClick = function()
			showOdds(RouletteConfig.WheelEggId)
		end,
	})

	local statusPanel = Atlas.new("ImageLabel", "panel_white", {
		Name = "StatusPanel",
		Size = UDim2.new(1, 0, 0, 42),
		Position = UDim2.fromOffset(0, 342),
		ZIndex = wheelWindow.content.ZIndex + 1,
		Parent = wheelWindow.content,
	})
	Atlas.icon("icon_clock", {
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromOffset(10, 7),
		color = Theme.Color.Purple,
		ZIndex = statusPanel.ZIndex + 1,
		Parent = statusPanel,
	})
	timerLabel = UI.text({
		Name = "Timer",
		Size = UDim2.new(0.62, -52, 1, 0),
		Position = UDim2.fromOffset(45, 0),
		text = "",
		font = Theme.Font.Heading,
		textColor = Theme.Color.Purple,
		stroke = false,
		maxTextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = statusPanel.ZIndex + 1,
		Parent = statusPanel,
	})
	Atlas.icon("icon_spin", {
		Size = UDim2.fromOffset(27, 27),
		Position = UDim2.new(0.66, 0, 0, 7),
		color = Theme.Color.Cyan,
		ZIndex = statusPanel.ZIndex + 1,
		Parent = statusPanel,
	})
	paidLabel = UI.text({
		Name = "Paid",
		Size = UDim2.new(0.34, -42, 1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		text = "",
		font = Theme.Font.Heading,
		textColor = Theme.Color.Cyan,
		stroke = false,
		maxTextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = statusPanel.ZIndex + 1,
		Parent = statusPanel,
	})

	buyOneButton = UI.button({
		Name = "BuyOne",
		palette = "cyan",
		text = "",
		icon = "icon_cash",
		Size = UDim2.fromOffset(205, 50),
		Position = UDim2.new(0, 0, 1, -2),
		AnchorPoint = Vector2.new(0, 1),
		ZIndex = wheelWindow.content.ZIndex + 2,
		Parent = wheelWindow.content,
		onClick = function()
			promptProduct(RouletteConfig.Products.One)
		end,
	})
	spinButton = UI.button({
		Name = "Spin",
		palette = "purple",
		text = "",
		icon = "icon_spin",
		Size = UDim2.fromOffset(246, 58),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = wheelWindow.content.ZIndex + 3,
		Parent = wheelWindow.content,
		onClick = handleSpin,
	})
	buyThreeButton = UI.button({
		Name = "BuyThree",
		palette = "pink",
		text = "",
		icon = "icon_cash",
		Size = UDim2.fromOffset(205, 50),
		Position = UDim2.new(1, 0, 1, -2),
		AnchorPoint = Vector2.new(1, 1),
		ZIndex = wheelWindow.content.ZIndex + 2,
		Parent = wheelWindow.content,
		onClick = function()
			promptProduct(RouletteConfig.Products.Three)
		end,
	})

	renderRewardList()
	refreshProductButtons()
	refreshStateText()
end

local function openWheel()
	openModal(wheelWindow)
	fetchState()
end

local function injectIntoShop(shop: Instance)
	task.defer(function()
		local shopWindow = shop:FindFirstChild("ShopWindow", true)
		local deadline = os.clock() + 15
		while not shopWindow and os.clock() < deadline do
			task.wait(0.1)
			shopWindow = shop:FindFirstChild("ShopWindow", true)
		end
		if not shopWindow then
			return
		end

		local tabBar = shopWindow:FindFirstChild("TabBar", true)
		if tabBar then
			local old = tabBar:FindFirstChild("Tab_roulette")
			tabBar.Size = UDim2.new(0, 5 * 60, 0, 52)
			if not old then
				local button = makeAtlasIconButton({
					Name = "Tab_roulette",
					Size = UDim2.fromOffset(48, 48),
					LayoutOrder = 5,
					icon = "icon_spin",
					palette = "cyan",
					ZIndex = tabBar.ZIndex + 1,
					Parent = tabBar,
					onClick = openWheel,
				})
				button:SetAttribute("RadRouletteV2", true)
			end
		end

		local eggsPage = shopWindow:FindFirstChild("eggs", true)
		if not eggsPage then
			return
		end
		for _, eggId in ipairs(EggConfig.Order) do
			local card = eggsPage:FindFirstChild(eggId)
			if card then
				local oddsEggId = eggId
				local old = card:FindFirstChild("OddsButton")
				if old and not old:GetAttribute("RadRouletteV2") then
					old:Destroy()
					old = nil
				end
				if not old then
					local button = makeAtlasIconButton({
						Name = "OddsButton",
						Size = UDim2.fromOffset(38, 38),
						Position = UDim2.fromOffset(7, 7),
						icon = "icon_info",
						palette = "dark",
						ZIndex = card.ZIndex + 8,
						Parent = card,
						onClick = function()
							showOdds(oddsEggId)
						end,
					})
					button:SetAttribute("RadRouletteV2", true)
				end
			end
		end
	end)
end

local function refreshLocalizedUi()
	renderRewardList()
	refreshProductButtons()
	refreshStateText()
	refreshOddsHeader()
	if oddsWindow and oddsWindow.root.Visible then
		renderOdds(currentOddsData == nil and not oddsFailed, oddsFailed)
	end
end

local function start()
	-- Studio에서 스크립트를 교체 실행해도 이전 디머가 남지 않도록 이 UI만 정리한다.
	local previous = playerGui:FindFirstChild("RadEggWheel")
	if previous then
		previous:Destroy()
	end

	screen = UI.create("ScreenGui", {
		Name = "RadEggWheel",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = Theme.Z.Modal,
		Parent = playerGui,
	})
	dimmer = UI.dimmer({
		transparency = 0.48,
		ZIndex = Theme.Z.Modal - 1,
		Parent = screen,
	})
	dimmer.Visible = false
	dimmer.Active = false

	buildWheelWindow()
	buildOddsWindow()

	wheelWindow.root:GetPropertyChangedSignal("Visible"):Connect(refreshDimmer)
	oddsWindow.root:GetPropertyChangedSignal("Visible"):Connect(refreshDimmer)
	screen:GetPropertyChangedSignal("Enabled"):Connect(refreshDimmer)
	ShopController.onRouletteRequest = openWheel

	NetClient.on("RouletteSync", applyState)
	Localization.Changed:Connect(refreshLocalizedUi)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.Escape then
			return
		end
		if oddsWindow.root.Visible then
			closeOdds()
		elseif wheelWindow.root.Visible then
			closeModal(wheelWindow)
		end
	end)

	local existingShop = playerGui:FindFirstChild("RadShop")
	if existingShop then
		injectIntoShop(existingShop)
	end
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "RadShop" then
			injectIntoShop(child)
		end
	end)

	fetchState()
	task.spawn(function()
		while screen.Parent do
			task.wait(1)
			refreshStateText()
			if wheelWindow.root.Visible
				and state
				and remainingSeconds() <= 0
				and (state.freeSpins or 0) <= 0
				and os.clock() - lastStateFetch >= 3
			then
				fetchState()
			end
		end
	end)
end

local ok, err = pcall(start)
if not ok then
	if screen and screen.Parent then
		screen:Destroy()
	end
	warn("[EggWheelClient] 시작 실패: " .. tostring(err))
end

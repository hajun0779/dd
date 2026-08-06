--!nonstrict

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local UI = require(Shared.UI.UIBuilder)
local Theme = require(Shared.UI.Theme)
local Atlas = require(Shared.UI.Atlas)
local EggVisual = require(Shared.UI.EggVisual)
local EggConfig = require(Shared.Config.EggConfig)
local GrowthConfig = require(Shared.Config.GrowthConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Format = require(Shared.Util.Format)
local Localization = require(Shared.Locale.Localization)
local NetClient = require(Shared.Net.NetClient)

local ClientState = require(script.Parent.Parent.ClientState)
local NotifyController = require(script.Parent.NotifyController)

local ShopController = {}

local player = Players.LocalPlayer
local window
local dimmer: Frame
local pages: { [string]: ScrollingFrame } = {}
local currentTab = "eggs"

ShopController.onGiftRequest = nil
ShopController.onRouletteRequest = nil

-- 탭도 색을 하나로 맞춘다. 어느 탭인지는 아이콘과 눌린 표시로 구분한다.
local TABS = {
	{ id = "eggs", icon = "icon_egg", palette = "cyan" },
	{ id = "feed", icon = "icon_fruit", palette = "cyan" },
	{ id = "gamepass", icon = "icon_trophy", palette = "cyan" },
	{ id = "cash", icon = "icon_money", palette = "cyan" },
	{ id = "roulette", icon = "icon_spin", palette = "cyan" },
}

local feedCards: { [string]: any } = {}
local eggCards: { [string]: any } = {}

--[[
	재고.

	서버가 "다음 재입고 시각" 을 보내 준다. 남은 초를 받으면 늦게 연 사람의
	화면이 어긋나므로, 시각을 받아 각자 계산한다.
]]
local stock = { egg = {}, feed = {}, nextAt = 0 }
local restockLabel: TextLabel

local RESTOCK_BAR_HEIGHT = 40

local function stockOf(kind: string, id: string): number
	local value = stock[kind] and stock[kind][id]
	if value == nil then
		return -1
	end
	return value
end

local function descKey(key: string): string
	return "pass_desc_" .. key:gsub("(%l)(%u)", "%1_%2"):lower()
end

local function priceButton(parent: Frame, order: number, config)
	local isRobux = config.Currency == "Robux" or config.robux ~= nil
	local palette = isRobux and "green" or "yellow"
	local priceText = isRobux
		and tostring(config.robux or config.Price)
		or Format.short(config.Price or 0)

	local btn = UI.button({
		Name = "Price",
		palette = palette,
		text = priceText,
		icon = isRobux and "icon_cash" or "icon_money",
		Size = UDim2.new(1, -20, 0, 44),
		LayoutOrder = order,
		ZIndex = parent.ZIndex + 2,
		Parent = parent,
	})
	return btn
end

local function buildEggCard(parent: Frame, order: number, eggId: string)
	local config = EggConfig.get(eggId)
	if not config then
		return
	end

	local card = UI.card({
		Name = eggId,
		palette = order % 2 == 0 and "pink" or "cyan",
		Size = UDim2.fromOffset(228, 268),
		LayoutOrder = order,
		ZIndex = parent.ZIndex + 1,
		Parent = parent,
	})

	if config.IsNew then
		UI.ribbon({
			palette = "red",
			localeKey = "common_new",
			Position = UDim2.new(1, -8, 0, 8),
			ZIndex = card.ZIndex + 6,
			Parent = card,
		})
	end

	UI.text({
		Name = "Title",
		Size = UDim2.new(0.9, 0, 0, 34),
		Position = UDim2.new(0.5, 0, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		localeKey = config.LocaleKey,
		font = Theme.Font.Heading,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 26,
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})

	-- 알마다 껍데기 색과 기호가 다르다. 상점에서 이름을 읽기 전에 알아볼 수 있어야 한다.
	EggVisual.applyIcon(Atlas.icon("icon_egg", {
		Name = "Icon",
		Size = UDim2.fromOffset(110, 110),
		Position = UDim2.fromScale(0.5, 0.48),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = card.ZIndex + 2,
		Parent = card,
	}), config.Id)

	local buttonHolder = UI.create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})
	UI.list({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 4),
	}, buttonHolder)

	local stockLabel = UI.text({
		Name = "Stock",
		Size = UDim2.new(0.9, 0, 0, 22),
		Position = UDim2.new(0.5, 0, 1, -66),
		AnchorPoint = Vector2.new(0.5, 1),
		text = "",
		font = Theme.Font.Body,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 16,
		ZIndex = card.ZIndex + 3,
		Parent = card,
	})

	local buyButton = priceButton(buttonHolder, 1, config)
	eggCards[eggId] = { card = card, stock = stockLabel, buy = buyButton }

	local required = config.RequiredRebirth or 0
	if required > 0 then
		local lock = UI.ribbon({
			palette = "dark",
			text = "",
			Size = UDim2.fromOffset(120, 28),
			Position = UDim2.new(0.5, 0, 0, 52),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = card.ZIndex + 6,
			Parent = card,
		})
		local lockLabel = lock:FindFirstChildOfClass("TextLabel")
		if lockLabel then
			Localization.bind(lockLabel, "Text", "rebirth_locked", { required })
		end
		lock.Name = "RebirthLock"
		card:SetAttribute("RequiredRebirth", required)
		lock.Visible = (ClientState.rebirths or 0) < required
	end

	buyButton.MouseButton1Click:Connect(function()
		local result = NetClient.invoke("ShopBuy", 8, eggId)
		if result and result.ok then
			if not result.prompt then
				NotifyController.toast({
					key = "shop_buy_success",
					args = { Localization.t(config.LocaleKey) },
					kind = "success",
					icon = "icon_egg",
				})
			end
		else
			local reason = result and result.reason
			local key = "shop_not_enough"
			local args = nil
			if reason == "inventory_full" then
				key = "shop_inventory_full"
			elseif reason == "out_of_stock" then
				key = "stock_out"
			elseif reason == "rebirth_required" then
				key = "rebirth_required"
				args = { result.required or required }
			elseif reason == "product_not_configured" then
				key = "gift_not_configured"
			end
			NotifyController.toast({ key = key, args = args, kind = "error" })
		end
	end)

	return card
end

function ShopController.refreshLocks()
	local page = pages.eggs
	if not page then
		return
	end
	for _, card in ipairs(page:GetChildren()) do
		local required = card:GetAttribute("RequiredRebirth")
		local lock = card:FindFirstChild("RebirthLock")
		if required and lock then
			lock.Visible = (ClientState.rebirths or 0) < required
		end
	end
end

--[[
	먹이 한 종류.

	사 두면 개수가 표시되고, 거위 옆에서 G 를 눌러 먹인다.
	비싼 먹이일수록 점수당 값이 싸다는 걸 카드에 그대로 보여 준다.
]]
local function buildFeedCard(parent: Frame, order: number, feed)
	local card = UI.card({
		Name = feed.Id,
		palette = "green",
		Size = UDim2.fromOffset(228, 306),
		LayoutOrder = order,
		ZIndex = parent.ZIndex + 1,
		Parent = parent,
	})

	UI.text({
		Name = "Title",
		Size = UDim2.new(0.9, 0, 0, 32),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		localeKey = feed.LocaleKey,
		font = Theme.Font.Heading,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 24,
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})

	Atlas.icon(feed.Icon or "icon_fruit", {
		Name = "Icon",
		Size = UDim2.fromOffset(68, 68),
		Position = UDim2.new(0.5, 0, 0, 48),
		AnchorPoint = Vector2.new(0.5, 0),
		color = Theme.Color.TextInverse,
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})

	UI.text({
		Name = "Points",
		Size = UDim2.new(0.9, 0, 0, 26),
		Position = UDim2.new(0.5, 0, 0, 124),
		AnchorPoint = Vector2.new(0.5, 0),
		localeKey = "feed_points",
		localeArgs = { Format.short(feed.Points) },
		font = Theme.Font.Body,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 17,
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})

	local stockLabel = UI.text({
		Name = "Stock",
		Size = UDim2.new(0.9, 0, 0, 22),
		Position = UDim2.new(0.5, 0, 0, 174),
		AnchorPoint = Vector2.new(0.5, 0),
		text = "",
		font = Theme.Font.Body,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 15,
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})

	local ownedLabel = UI.text({
		Name = "Owned",
		Size = UDim2.new(0.9, 0, 0, 24),
		Position = UDim2.new(0.5, 0, 0, 152),
		AnchorPoint = Vector2.new(0.5, 0),
		text = "",
		font = Theme.Font.Body,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 16,
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})

	local buttonHolder = UI.create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 92),
		Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})
	UI.list({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 4),
	}, buttonHolder)

	local function buy(count: number)
		local result = NetClient.invoke("BuyFeed", 8, feed.Id, count)
		if result and result.ok then
			NotifyController.toast({
				key = "feed_bought",
				args = { { key = feed.LocaleKey }, result.count },
				kind = "success",
				icon = feed.Icon or "icon_fruit",
			})
		else
			local reason = result and result.reason
			local key = "shop_not_enough"
			if reason == "feed_full" then
				key = "feed_full"
			elseif reason == "out_of_stock" then
				key = "stock_out"
			end
			NotifyController.toast({ key = key, kind = "error" })
		end
	end

	for i, count in ipairs({ 1, 10 }) do
		UI.button({
			Name = "Buy" .. count,
			palette = i == 1 and "yellow" or "green",
			text = ("x%d  %s"):format(count, Format.short(feed.Price * count)),
			Size = UDim2.fromOffset(190, 42),
			LayoutOrder = i,
			ZIndex = buttonHolder.ZIndex + 1,
			Parent = buttonHolder,
			onClick = function()
				buy(count)
			end,
		})
	end

	feedCards[feed.Id] = { card = card, owned = ownedLabel, stock = stockLabel }
end

local function refreshFeedCounts()
	for id, entry in pairs(feedCards) do
		local owned = (ClientState.feed and ClientState.feed[id]) or 0
		Localization.bind(entry.owned, "Text", "feed_owned", { owned })
	end
end

--[[
	재고 표시를 갱신한다.

	품절이면 버튼을 회색으로 바꾸고 "품절" 을 띄운다.
	재고를 세지 않는 품목(-1)은 아무것도 안 띄운다.
]]
local function refreshStock()
	for id, entry in pairs(eggCards) do
		local count = stockOf("egg", id)
		if count < 0 then
			entry.stock.Text = ""
		elseif count == 0 then
			Localization.bind(entry.stock, "Text", "stock_out")
		else
			Localization.bind(entry.stock, "Text", "stock_left", { count })
		end

		if count == 0 then
			Atlas.apply(entry.buy, "btn_gray")
		end
	end

	for id, entry in pairs(feedCards) do
		local count = stockOf("feed", id)
		if entry.stock then
			if count < 0 then
				entry.stock.Text = ""
			elseif count == 0 then
				Localization.bind(entry.stock, "Text", "stock_out")
			else
				Localization.bind(entry.stock, "Text", "stock_left", { count })
			end
		end
	end
end

local function applyStock(data)
	if type(data) ~= "table" then
		return
	end
	stock.egg = data.egg or {}
	stock.feed = data.feed or {}
	stock.nextAt = data.nextAt or 0
	refreshStock()
end

local function buildGamepassCard(parent: Frame, order: number, key: string)
	local config = MonetizationConfig.getGamepass(key)
	if not config then
		return
	end

	local card = UI.card({
		Name = key,
		palette = config.palette or "blue",
		Size = UDim2.fromOffset(228, 306),
		LayoutOrder = order,
		ZIndex = parent.ZIndex + 1,
		Parent = parent,
	})

	UI.text({
		Name = "Title",
		Size = UDim2.new(0.9, 0, 0, 32),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		localeKey = config.localeKey,
		font = Theme.Font.Heading,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 24,
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})

	Atlas.icon(config.icon or "icon_star", {
		Name = "Icon",
		Size = UDim2.fromOffset(68, 68),
		Position = UDim2.new(0.5, 0, 0, 46),
		AnchorPoint = Vector2.new(0.5, 0),
		color = Theme.Color.TextInverse,
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})

	UI.text({
		Name = "Desc",
		Size = UDim2.new(0.88, 0, 0, 46),
		Position = UDim2.new(0.5, 0, 0, 120),
		AnchorPoint = Vector2.new(0.5, 0),
		localeKey = descKey(key),
		font = Theme.Font.Body,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 15,
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})

	local buttonHolder = UI.create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 92),
		Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})
	UI.list({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 4),
	}, buttonHolder)

	local owned = ClientState.entitlements[key] ~= nil

	local buy = UI.button({
		Name = "Buy",
		palette = owned and "gray" or "green",
		localeKey = owned and "common_owned" or nil,
		text = (not owned) and tostring(config.robux) or nil,
		icon = owned and "icon_check" or "icon_cash",
		Size = UDim2.new(1, -20, 0, 40),
		LayoutOrder = 1,
		ZIndex = buttonHolder.ZIndex + 1,
		Parent = buttonHolder,
		onClick = function()
			if owned then
				return
			end
			if config.gamepassId == 0 then
				NotifyController.toast({ key = "gift_not_configured", kind = "error" })
				return
			end
			pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, config.gamepassId)
			end)
		end,
	})

	if config.giftable then
		UI.button({
			Name = "Gift",
			palette = "pink",
			localeKey = "gift_send",
			icon = "icon_gift",
			Size = UDim2.new(1, -20, 0, 40),
			LayoutOrder = 2,
			ZIndex = buttonHolder.ZIndex + 1,
			Parent = buttonHolder,
			onClick = function()
				if ShopController.onGiftRequest then
					ShopController.onGiftRequest(key)
				end
			end,
		})
	end

	return card
end

local function buildProductCard(parent: Frame, order: number, key: string)
	local config = MonetizationConfig.getProduct(key)
	if not config then
		return
	end

	local card = UI.card({
		Name = key,
		palette = config.palette or "green",
		Size = UDim2.fromOffset(228, 240),
		LayoutOrder = order,
		ZIndex = parent.ZIndex + 1,
		Parent = parent,
	})

	UI.text({
		Name = "Title",
		Size = UDim2.new(0.9, 0, 0, 34),
		Position = UDim2.new(0.5, 0, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		localeKey = config.localeKey,
		font = Theme.Font.Heading,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 26,
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})

	Atlas.icon(config.icon or "icon_money", {
		Size = UDim2.fromOffset(96, 96),
		Position = UDim2.fromScale(0.5, 0.48),
		AnchorPoint = Vector2.new(0.5, 0.5),
		color = Theme.Color.TextInverse,
		ZIndex = card.ZIndex + 2,
		Parent = card,
	})

	UI.button({
		Name = "Buy",
		palette = "yellow",
		text = tostring(config.robux),
		icon = "icon_cash",
		Size = UDim2.new(1, -30, 0, 42),
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = card.ZIndex + 3,
		Parent = card,
		onClick = function()
			if config.productId == 0 then
				NotifyController.toast({ key = "gift_not_configured", kind = "error" })
				return
			end
			pcall(function()
				MarketplaceService:PromptProductPurchase(player, config.productId)
			end)
		end,
	})

	return card
end

local function makePage(parent: Frame, id: string)
	local page = UI.create("ScrollingFrame", {
		Name = id,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		-- 위쪽 재입고 줄에 가리지 않도록 그만큼 내려서 시작한다
		Size = UDim2.new(1, 0, 1, -RESTOCK_BAR_HEIGHT),
		Position = UDim2.fromOffset(0, RESTOCK_BAR_HEIGHT),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Color.Cyan,
		Visible = false,
		ZIndex = parent.ZIndex + 1,
		Parent = parent,
	})
	UI.grid({
		CellSize = UDim2.fromOffset(228, 306),
		CellPadding = UDim2.fromOffset(14, 14),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, page)
	UI.padding(8, page)
	pages[id] = page
	return page
end

function ShopController.setTab(id: string)
	-- 룰렛은 기존 상점 페이지를 갈아 끼우지 않고 전용 아틀라스 창으로 연다.
	-- 탭 자체는 상점 생성 시 함께 만들어져 별도 LocalScript의 생성 순서에 의존하지 않는다.
	if id == "roulette" then
		if ShopController.onRouletteRequest then
			ShopController.onRouletteRequest()
		end
		return
	end

	currentTab = id
	for pageId, page in pairs(pages) do
		page.Visible = pageId == id
	end
	if window then
		window.setTabActive(id)
	end
end

function ShopController.start(playerGui: PlayerGui)
	local screen = UI.create("ScreenGui", {
		Name = "RadShop",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = Theme.Z.Panel,
		Parent = playerGui,
	})

	dimmer = UI.dimmer({ Parent = screen })

	window = UI.window({
		Name = "ShopWindow",
		localeKey = "shop_title",
		icon = "icon_shop",
		Size = UDim2.fromOffset(800, 500),
		tabs = TABS,
		Parent = screen,
		onTab = function(id)
			ShopController.setTab(id)
		end,
		onClose = function()
			ShopController.close()
		end,
	})

	local eggsPage = makePage(window.content, "eggs")
	for i, eggId in ipairs(EggConfig.Order) do
		buildEggCard(eggsPage, i, eggId)
	end

	--[[
		재입고 줄. 남은 시간과 "지금 바로" 버튼을 같이 둔다.
		참고 화면처럼 창 맨 위에 붙인다.
	]]
	local restockBar = Atlas.new("ImageLabel", "panel_dark", {
		Name = "Restock",
		Size = UDim2.new(1, -12, 0, RESTOCK_BAR_HEIGHT - 8),
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = window.content.ZIndex + 4,
		Parent = window.content,
	})

	Atlas.icon("icon_clock", {
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.fromOffset(14, 5),
		color = Theme.Color.Yellow,
		ZIndex = restockBar.ZIndex + 1,
		Parent = restockBar,
	})

	restockLabel = UI.text({
		Name = "Timer",
		Size = UDim2.new(1, -200, 1, -8),
		Position = UDim2.fromOffset(44, 4),
		text = "",
		font = Theme.Font.Heading,
		textColor = Theme.Color.TextInverse,
		stroke = false,
		maxTextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = restockBar.ZIndex + 1,
		Parent = restockBar,
	})

	local restockButton = UI.button({
		Name = "Now",
		palette = "blue",
		localeKey = "stock_restock_now",
		Size = UDim2.fromOffset(132, 28),
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		ZIndex = restockBar.ZIndex + 2,
		Parent = restockBar,
	})

	restockButton.MouseButton1Click:Connect(function()
		local result = NetClient.invoke("StockRestock", 8)
		if result and result.ok then
			applyStock(result.stock)
		else
			NotifyController.toast({ key = "shop_not_enough", kind = "error" })
		end
	end)

	NetClient.on("StockSync", applyStock)

	task.spawn(function()
		local data = NetClient.invoke("StockGet", 8)
		applyStock(data)
	end)

	task.spawn(function()
		while true do
			if restockLabel and stock.nextAt > 0 then
				local left = math.max(stock.nextAt - workspace:GetServerTimeNow(), 0)
				Localization.bind(restockLabel, "Text", "stock_restock_in", {
					("%d:%02d"):format(math.floor(left / 60), math.floor(left % 60)),
				})
			end
			task.wait(1)
		end
	end)

	local feedPage = makePage(window.content, "feed")
	for i, feed in ipairs(GrowthConfig.Feeds) do
		buildFeedCard(feedPage, i, feed)
	end
	refreshFeedCounts()

	NetClient.on("FeedSync", function(data)
		if type(data) == "table" and type(data.feed) == "table" then
			ClientState.feed = data.feed
			refreshFeedCounts()
		end
	end)

	local passPage = makePage(window.content, "gamepass")
	for i, key in ipairs(MonetizationConfig.GamepassOrder) do
		buildGamepassCard(passPage, i, key)
	end

	local cashPage = makePage(window.content, "cash")
	for i, key in ipairs(MonetizationConfig.ProductOrder) do
		buildProductCard(cashPage, i, key)
	end

	ShopController.setTab("eggs")
	ShopController.screen = screen
	return screen
end

function ShopController.open(tab: string?)
	if not window then
		return
	end
	dimmer.Visible = true
	window.open()
	ShopController.setTab(tab or currentTab)
end

function ShopController.close()
	if not window then
		return
	end
	dimmer.Visible = false
	window.close()
end

function ShopController.toggle()
	if window and window.root.Visible then
		ShopController.close()
	else
		ShopController.open()
	end
end

return ShopController

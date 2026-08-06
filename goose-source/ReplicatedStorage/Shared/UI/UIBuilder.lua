--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage.Shared
local Atlas = require(Shared.UI.Atlas)
local Theme = require(Shared.UI.Theme)
local Localization = require(Shared.Locale.Localization)

local UI = {}
UI.Atlas = Atlas
UI.Theme = Theme

local function isRobloxProperty(key): boolean
	if type(key) ~= "string" or key == "" then
		return false
	end
	if key == "Parent" or key == "Children" then
		return false
	end
	return string.match(string.sub(key, 1, 1), "%u") ~= nil
end

UI.isRobloxProperty = isRobloxProperty

function UI.create(className: string, props, children)
	local inst = Instance.new(className)
	props = props or {}

	for k, v in pairs(props) do
		if isRobloxProperty(k) then
			inst[k] = v
		end
	end

	if children then
		for _, child in ipairs(children) do
			if child then
				child.Parent = inst
			end
		end
	end
	if props.Children then
		for _, child in ipairs(props.Children) do
			if child then
				child.Parent = inst
			end
		end
	end

	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function UI.corner(radius: UDim?, parent: Instance?)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or Theme.Size.CornerRadius
	c.Parent = parent
	return c
end

function UI.stroke(thickness: number?, color: Color3?, parent: Instance?, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or Theme.Size.StrokeThick
	s.Color = color or Color3.fromRGB(255, 255, 255)
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

function UI.gradient(colors, rotation: number?, parent: Instance?)
	local g = Instance.new("UIGradient")
	if typeof(colors) == "ColorSequence" then
		g.Color = colors
	elseif type(colors) == "table" then
		g.Color = ColorSequence.new(colors[1], colors[2])
	end
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

function UI.padding(all: number?, parent: Instance?, t: number?, b: number?, l: number?, r: number?)
	local p = Instance.new("UIPadding")
	local v = all or 0
	p.PaddingTop = UDim.new(0, t or v)
	p.PaddingBottom = UDim.new(0, b or v)
	p.PaddingLeft = UDim.new(0, l or v)
	p.PaddingRight = UDim.new(0, r or v)
	p.Parent = parent
	return p
end

function UI.aspect(ratio: number, parent: Instance?)
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = ratio
	a.Parent = parent
	return a
end

function UI.list(props, parent: Instance?)
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = Enum.FillDirection.Vertical
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Top
	l.Padding = UDim.new(0, Theme.Size.Padding)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function UI.grid(props, parent: Instance?)
	local g = Instance.new("UIGridLayout")
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.CellPadding = UDim2.fromOffset(10, 10)
	g.CellSize = UDim2.fromOffset(120, 120)
	for k, v in pairs(props or {}) do
		g[k] = v
	end
	g.Parent = parent
	return g
end

function UI.scale(value: number, parent: Instance?)
	local s = Instance.new("UIScale")
	s.Scale = value
	s.Parent = parent
	return s
end

local soundCache = {}
local soundFailed = {}

function UI.playSound(id: string, volume: number?)
	if not id or id == "" or soundFailed[id] then
		return
	end

	local s = soundCache[id]
	if not s or not s.Parent then
		s = Instance.new("Sound")
		s.SoundId = id
		s.Parent = SoundService
		soundCache[id] = s

		s.Loaded:Once(function()
			soundFailed[id] = nil
		end)
		task.delay(6, function()
			if s.Parent and not s.IsLoaded then
				soundFailed[id] = true
			end
		end)
	end

	s.Volume = volume or 0.5
	pcall(function()
		s:Play()
	end)
end

--[[
	배경에 스터드를 깐다.

	타일 한 장에 스터드가 하나라서 `size` 가 그대로 스터드 간격이다.
	가로로 몇 개를 깔지 정하고 거기서 간격을 역산하는 게 편하다.
	  92px 버튼에 4개 → 간격 23
	  92px 버튼에 5개 → 간격 18

	타일에는 색을 칠하지 않았다. 밝은 곳과 어두운 곳만 그려 놨기 때문에
	어떤 색 위에 깔아도 그 색이 살아 있는 채로 오돌토돌해 보인다.
]]
function UI.studs(parent: GuiObject, props)
	props = props or {}
	local size = props.size or 22

	return Atlas.new("ImageLabel", props.soft and "stud_tile_soft" or "stud_tile", {
		Name = "Studs",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.new(1, props.inset or -14, 1, props.inset or -14),
		Position = props.Position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		ZIndex = (props.ZIndex or parent.ZIndex) + (props.zOffset or 1),
		Parent = parent,
		tile = true,
		tileSize = UDim2.fromOffset(size, size),
		transparency = props.transparency or 0,
	})
end

--[[
	언어에 따라 폰트를 바꿔 끼운다.

	장식체에는 한글 글리프가 없어서 그대로 두면 글자가 안 보인다.
	여기서 한 번 걸러 두면 UI.text 를 쓰는 모든 글씨가 자동으로 고쳐진다.

	약한 참조로 들고 있으므로, 사라진 라벨은 알아서 정리된다.
	언어를 바꾸면 이미 붙어 있는 글씨까지 같이 갈아 끼운다.
]]
local localeFonts = setmetatable({}, { __mode = "k" })

function UI.setFont(label, font: Enum.Font?)
	if not label then
		return label
	end
	local wanted = font or Theme.Font.Heading
	localeFonts[label] = wanted
	label.Font = Theme.resolveFont(wanted, Localization.getLocale())
	return label
end

Localization.Changed:Connect(function(code)
	for label, font in pairs(localeFonts) do
		if typeof(label) == "Instance" and label.Parent then
			label.Font = Theme.resolveFont(font, code)
		else
			localeFonts[label] = nil
		end
	end
end)

function UI.text(props)
	props = props or {}
	local label = UI.create("TextLabel", props)
	label.BackgroundTransparency = props.BackgroundTransparency or 1
	label.BorderSizePixel = 0
	UI.setFont(label, props.font)
	label.TextColor3 = props.textColor or Theme.Color.Text
	label.TextScaled = props.TextScaled ~= false
	label.RichText = props.RichText or false

	if props.textSize then
		label.TextScaled = false
		label.TextSize = props.textSize
	end

	if props.stroke ~= false then
		local thickness = type(props.stroke) == "number" and props.stroke or 2
		local s = UI.stroke(thickness, props.strokeColor or Theme.Color.TextStroke, label)
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	end

	if props.localeKey then
		Localization.bind(label, "Text", props.localeKey, props.localeArgs)
	elseif props.text then
		label.Text = props.text
	end

	if label.TextScaled and props.maxTextSize then
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = props.maxTextSize
		c.MinTextSize = props.minTextSize or 8
		c.Parent = label
	end

	return label
end

--[[
	글씨 테두리는 글씨색의 반대여야 한다.

	어두운 글씨에 어두운 테두리를 두르면 글자가 뭉개져 검은 덩어리가 된다.
	밝기를 재서 반대쪽 색을 고른다.
]]
local function contrastStroke(textColor: Color3): Color3
	local luminance = textColor.R * 0.299 + textColor.G * 0.587 + textColor.B * 0.114
	if luminance > 0.55 then
		return Theme.Color.Dark
	end
	return Color3.fromRGB(255, 255, 255)
end

--[[
	글씨색을 바꿀 때 테두리도 같이 바꾼다.

	색만 바꾸면 흰 글씨에 흰 테두리가 남아 글자가 사라진다.
	켜짐/꺼짐처럼 상태에 따라 색이 뒤집히는 곳에서 반드시 이걸 쓴다.
]]
function UI.setTextColor(label: TextLabel, color: Color3)
	if not label then
		return
	end
	label.TextColor3 = color

	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = contrastStroke(color)
	end
end

local function attachPressFeedback(button: GuiButton, scaleObj: UIScale, enabled: boolean)
	if not enabled then
		return
	end
	local base = scaleObj.Scale
	local down = false

	local function to(target, info)
		TweenService:Create(scaleObj, info or Theme.Tween.Fast, { Scale = target }):Play()
	end

	button.MouseButton1Down:Connect(function()
		down = true
		to(base * Theme.PressScale)
	end)
	button.MouseButton1Up:Connect(function()
		down = false
		to(base, Theme.Tween.Pop)
	end)
	button.MouseEnter:Connect(function()
		if not down and not UserInputService.TouchEnabled then
			to(base * Theme.HoverScale)
		end
	end)
	button.MouseLeave:Connect(function()
		down = false
		to(base)
	end)
end

function UI.button(props)
	props = props or {}
	local palette = props.palette or "blue"
	local sprite = props.sprite or ("btn_" .. palette)

	local btn = Atlas.new("ImageButton", sprite, {
		Size = props.Size or UDim2.fromOffset(200, 68),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex or 1,
		Visible = props.Visible,
		Name = props.Name or "Button",
		sliceScale = props.sliceScale or 1,
	})

	local scaleObj = UI.scale(1, btn)
	attachPressFeedback(btn, scaleObj, props.scaleOnPress ~= false)

	local textColor = props.textColor or Theme.PaletteTextColor[palette] or Theme.Color.TextInverse

		local holder = UI.create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 1, -16),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = btn.ZIndex + 1,
		Parent = btn,
	})

	local labelSize = UDim2.fromScale(1, 1)
	local labelPos = UDim2.fromScale(0.5, 0.5)

	if props.icon then
		local iconLabel = Atlas.icon(props.icon, {
			Name = "Icon",
			Size = UDim2.fromScale(1, 1),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			Position = UDim2.fromScale(0, 0.5),
			AnchorPoint = Vector2.new(0, 0.5),
			color = props.iconColor or textColor,
			ZIndex = holder.ZIndex + 1,
			Parent = holder,
		})
		iconLabel.Size = UDim2.new(0, 0, 0.86, 0)
		iconLabel.SizeConstraint = Enum.SizeConstraint.RelativeYY
		iconLabel.Size = UDim2.fromScale(0.86, 0.86)

		labelSize = UDim2.new(1, -34, 1, 0)
		labelPos = UDim2.new(1, 0, 0.5, 0)
	end

	local label = UI.text({
		Name = "Label",
		Size = labelSize,
		Position = labelPos,
		AnchorPoint = props.icon and Vector2.new(1, 0.5) or Vector2.new(0.5, 0.5),
		localeKey = props.localeKey,
		localeArgs = props.localeArgs,
		text = props.text,
		font = props.font or Theme.Font.Heading,
		textColor = textColor,
		strokeColor = props.strokeColor or contrastStroke(textColor),
		stroke = props.stroke or 2.5,
		maxTextSize = props.maxTextSize or 32,
		ZIndex = holder.ZIndex + 1,
		Parent = holder,
	})
	label.TextXAlignment = Enum.TextXAlignment.Center

	if props.onClick then
		btn.MouseButton1Click:Connect(function()
			UI.playSound(props.sound or Theme.Sound.Click)
			props.onClick(btn)
		end)
	end

	if props.Parent then
		btn.Parent = props.Parent
	end
	btn:SetAttribute("Palette", palette)
	return btn, label
end

function UI.menuButton(props)
	props = props or {}
	local palette = props.palette or "red"
	local size = props.Size or UDim2.fromOffset(Theme.Size.MenuButton.X, Theme.Size.MenuButton.Y)

	local btn = Atlas.new("ImageButton", props.sprite or ("btn_" .. palette), {
		Name = props.Name or "MenuButton",
		Size = size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex or 1,
		sliceScale = props.sliceScale or 1,
	})
	UI.aspect(1, btn)

	local scaleObj = UI.scale(1, btn)
	attachPressFeedback(btn, scaleObj, props.scaleOnPress ~= false)

	--[[
		메뉴 버튼 글씨는 버튼 색과 상관없이 항상 흰색이다.

		팔레트마다 글씨색이 다르면 (노랑만 갈색 글씨 같은 식으로)
		나란히 놓았을 때 그 버튼만 다른 폰트처럼 보인다.
		어두운 테두리를 둘렀으므로 밝은 버튼 위에서도 읽힌다.
	]]
	local textColor = props.textColor or Theme.Color.TextInverse

	Atlas.icon(props.icon or "icon_star", {
		Name = "Icon",
		Size = UDim2.fromScale(0.56, 0.56),
		Position = UDim2.fromScale(0.5, 0.40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		color = props.iconColor or textColor,
		ZIndex = btn.ZIndex + 1,
		Parent = btn,
	})

	local label = UI.text({
		Name = "Label",
		Size = UDim2.new(0.9, 0, 0.26, 0),
		Position = UDim2.fromScale(0.5, 0.80),
		AnchorPoint = Vector2.new(0.5, 0.5),
		localeKey = props.localeKey,
		localeArgs = props.localeArgs,
		text = props.text,
		font = Theme.Font.Heading,
		textColor = textColor,
		strokeColor = contrastStroke(textColor),
		stroke = 3,
		maxTextSize = 20,
		ZIndex = btn.ZIndex + 1,
		Parent = btn,
	})

	if props.badge then
		local badge = Atlas.new("ImageLabel", "panel_red", {
			Name = "Badge",
			Size = UDim2.fromScale(0.42, 0.42),
			Position = UDim2.fromScale(0.94, 0.06),
			AnchorPoint = Vector2.new(1, 0),
			color = props.badgeColor,
			ZIndex = btn.ZIndex + 2,
			Parent = btn,
		})
		UI.text({
			Size = UDim2.fromScale(0.7, 0.7),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			text = tostring(props.badge),
			font = Theme.Font.Number,
			textColor = Theme.Color.TextInverse,
			ZIndex = btn.ZIndex + 3,
			Parent = badge,
		})
	end

	if props.onClick then
		btn.MouseButton1Click:Connect(function()
			UI.playSound(props.sound or Theme.Sound.Click)
			props.onClick(btn)
		end)
	end

	if props.Parent then
		btn.Parent = props.Parent
	end
	return btn, label
end

function UI.closeButton(props)
	props = props or {}
	local btn = Atlas.new("ImageButton", "btn_red", {
		Name = "Close",
		Size = props.Size or UDim2.fromOffset(52, 52),
		Position = props.Position or UDim2.new(1, 10, 0, -10),
		AnchorPoint = props.AnchorPoint or Vector2.new(1, 0),
		ZIndex = props.ZIndex or 5,
	})
	UI.aspect(1, btn)
	local scaleObj = UI.scale(1, btn)
	attachPressFeedback(btn, scaleObj, true)

	Atlas.icon("icon_close", {
		Size = UDim2.fromScale(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		color = Theme.Color.TextInverse,
		ZIndex = btn.ZIndex + 1,
		Parent = btn,
	})

	if props.onClick then
		btn.MouseButton1Click:Connect(function()
			UI.playSound(Theme.Sound.Close)
			props.onClick(btn)
		end)
	end
	if props.Parent then
		btn.Parent = props.Parent
	end
	return btn
end

function UI.window(props)
	props = props or {}

	local root = UI.create("Frame", {
		Name = props.Name or "Window",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(720, 460),
		Position = props.Position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = props.ZIndex or Theme.Z.Panel,
		Visible = false,
	})

	local scaleObj = UI.scale(1, root)

	--[[
		창은 고정 크기(예: 800x500)로 만든다. 그 크기가 화면보다 크면
		휴대폰에서는 화면 밖으로 삐져나가 닫기 버튼도 안 보인다.

		그래서 화면에 맞춰 줄인다. 늘리지는 않는다 —
		큰 화면에서 창만 커지면 촌스럽다.

		머리말과 닫기 버튼이 창 위/옆으로 튀어나와 있어서 여백을 넉넉히 잡는다.
	]]
	local designX = root.Size.X.Offset
	local designY = root.Size.Y.Offset
	local fitScale = 1

	local function computeFit(): number
		if designX <= 0 or designY <= 0 then
			return 1
		end
		local parent = root.Parent
		if not parent then
			return 1
		end

		local vp = parent.AbsoluteSize
		if vp.X <= 0 or vp.Y <= 0 then
			return 1
		end

		local mobile = UI.isMobile()
		local marginX = mobile and 22 or 48
		local marginY = mobile and 58 or 72

		local s = math.min(
			(vp.X - marginX * 2) / designX,
			(vp.Y - marginY * 2) / designY,
			1
		)
		return math.clamp(s, 0.35, 1)
	end

	local function applyFit()
		fitScale = computeFit()
		if root.Visible then
			scaleObj.Scale = fitScale
		end
	end

	local body = Atlas.new("ImageLabel", "window_main", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		ZIndex = root.ZIndex,
		sliceScale = 1,
		Parent = root,
	})

	if props.studs ~= false then
		UI.studs(body, { size = 24, inset = -34, transparency = 0.65, soft = true })
	end

	local header = UI.create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -40, 0, 56),
		Position = UDim2.new(0, 20, 0, -14),
		ZIndex = root.ZIndex + 2,
		Parent = root,
	})

	UI.list({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}, header)

	if props.icon ~= false then
		Atlas.icon(props.icon or "icon_shop", {
			Name = "Icon",
			Size = UDim2.fromOffset(52, 52),
			color = Theme.Color.Pink,
			LayoutOrder = 1,
			ZIndex = header.ZIndex + 1,
			Parent = header,
		})
	end

	local title = UI.text({
		Name = "Title",
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		localeKey = props.localeKey,
		text = props.text,
		-- 언어별 교체는 UI.setFont 이 알아서 한다. 여기서 따로 걸 필요가 없다.
		font = Theme.Font.Title,
		textColor = Theme.Color.TextInverse,
		strokeColor = Theme.Color.Dark,
		stroke = 3,
		maxTextSize = 42,
		LayoutOrder = 2,
		ZIndex = header.ZIndex + 1,
		Parent = header,
	})

	local tabBar
	local tabButtons = {}
	if props.tabs and #props.tabs > 0 then
		tabBar = UI.create("Frame", {
			Name = "TabBar",
			BackgroundTransparency = 1,
			Size = UDim2.new(0, #props.tabs * 60, 0, 52),
			Position = UDim2.new(0.5, 0, 0, -10),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = root.ZIndex + 3,
			Parent = root,
		})
		UI.list({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}, tabBar)

		for i, tab in ipairs(props.tabs) do
			local tb = UI.menuButton({
				Name = "Tab_" .. tostring(tab.id),
				Size = UDim2.fromOffset(48, 48),
				icon = tab.icon,
				palette = tab.palette or "cyan",
				text = "",
				LayoutOrder = i,
				ZIndex = tabBar.ZIndex + 1,
				Parent = tabBar,
				onClick = function()
					if props.onTab then
						props.onTab(tab.id)
					end
				end,
			})
			tb:FindFirstChild("Label"):Destroy()
			local ico = tb:FindFirstChild("Icon")
			if ico then
				ico.Size = UDim2.fromScale(0.62, 0.62)
				ico.Position = UDim2.fromScale(0.5, 0.5)
			end
			tabButtons[tab.id] = tb
		end
	end

	local content = UI.create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -44, 1, -76),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = root.ZIndex + 1,
		ClipsDescendants = props.ClipsDescendants ~= false,
		Parent = root,
	})

	local closeBtn = UI.closeButton({
		Position = UDim2.new(1, 16, 0, -16),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = root.ZIndex + 4,
		Parent = root,
		onClick = function()
			if props.onClose then
				props.onClose()
			end
		end,
	})

	local api = {
		root = root,
		body = body,
		header = header,
		title = title,
		content = content,
		tabBar = tabBar,
		tabs = tabButtons,
		closeButton = closeBtn,
	}

	function api.setTabActive(id)
		for tabId, btn in pairs(tabButtons) do
			local target = tabId == id and 1.12 or 1
			local s = btn:FindFirstChildOfClass("UIScale")
			if s then
				TweenService:Create(s, Theme.Tween.Fast, { Scale = target }):Play()
			end
		end
	end

	function api.open()
		if root.Visible then
			return
		end
		applyFit()
		root.Visible = true
		scaleObj.Scale = fitScale * 0.7
		TweenService:Create(scaleObj, Theme.Tween.PopIn, { Scale = fitScale }):Play()
		UI.playSound(Theme.Sound.Open)
	end

	function api.close()
		if not root.Visible then
			return
		end
		local t = TweenService:Create(scaleObj, Theme.Tween.Fast, { Scale = fitScale * 0.75 })
		t.Completed:Once(function()
			root.Visible = false
			scaleObj.Scale = fitScale
		end)
		t:Play()
	end

	api.refreshFit = applyFit

	if props.Parent then
		root.Parent = props.Parent

		if props.Parent:IsA("GuiBase2d") then
			props.Parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyFit)
		end
	end

	task.defer(applyFit)
	return api
end

function UI.card(props)
	props = props or {}
	local palette = props.palette or "cyan"

	local card = Atlas.new("ImageButton", props.sprite or ("panel_" .. palette), {
		Name = props.Name or "Card",
		Size = props.Size or UDim2.fromOffset(220, 260),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	local scaleObj = UI.scale(1, card)
	attachPressFeedback(card, scaleObj, props.scaleOnPress ~= false)

	--[[
		카드에는 스터드를 깔지 않는다.
		아이콘 뒤에서 도는 빛살과 겹치면 어디를 봐야 할지 알 수 없다.
		질감은 창 배경이 맡고, 카드는 상품만 보여 준다.
	]]
	if props.studs == true then
		UI.studs(card, { size = 20, inset = -26, transparency = 0.45, soft = true })
	end

	if props.onClick then
		card.MouseButton1Click:Connect(function()
			UI.playSound(Theme.Sound.Click)
			props.onClick(card)
		end)
	end
	return card
end

function UI.ribbon(props)
	props = props or {}
	local frame = Atlas.new("ImageLabel", "panel_" .. (props.palette or "red"), {
		Name = "Ribbon",
		Size = props.Size or UDim2.fromOffset(74, 30),
		Position = props.Position or UDim2.new(1, -6, 0, 6),
		AnchorPoint = props.AnchorPoint or Vector2.new(1, 0),
		Rotation = props.Rotation or 0,
		ZIndex = props.ZIndex or 6,
		Parent = props.Parent,
	})
	UI.text({
		Size = UDim2.fromScale(0.86, 0.6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		localeKey = props.localeKey,
		text = props.text,
		font = Theme.Font.Heading,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 20,
		ZIndex = frame.ZIndex + 1,
		Parent = frame,
	})
	return frame
end

function UI.bar(props)
	props = props or {}
	local bg = Atlas.new("ImageLabel", "bar_bg", {
		Name = props.Name or "Bar",
		Size = props.Size or UDim2.fromOffset(240, 26),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})

	local fillHolder = UI.create("Frame", {
		Name = "FillHolder",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ClipsDescendants = true,
		ZIndex = bg.ZIndex + 1,
		Parent = bg,
	})

	local fill = Atlas.new("ImageLabel", props.fillSprite or "bar_fill", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		ZIndex = fillHolder.ZIndex + 1,
		Parent = fillHolder,
	})

	local api = { root = bg, fill = fill }

	function api.set(alpha: number, animate: boolean?)
		alpha = math.clamp(alpha, 0, 1)
		if animate == false then
			fill.Size = UDim2.fromScale(alpha, 1)
		else
			TweenService:Create(fill, Theme.Tween.Fast, { Size = UDim2.fromScale(alpha, 1) }):Play()
		end
	end

	api.set(props.value or 0, false)
	return api
end

function UI.slot(props)
	props = props or {}
	local slot = Atlas.new("ImageButton", props.sprite or "slot_empty", {
		Name = props.Name or "Slot",
		Size = props.Size or UDim2.fromOffset(Theme.Size.HotbarSlot.X, Theme.Size.HotbarSlot.Y),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})

	local rarityFrame = Atlas.new("ImageLabel", "frame_common", {
		Name = "RarityFrame",
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = slot.ZIndex + 3,
		Parent = slot,
	})

	local icon = Atlas.icon("icon_egg", {
		Name = "Icon",
		Size = UDim2.fromScale(0.62, 0.62),
		Position = UDim2.fromScale(0.5, 0.44),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = slot.ZIndex + 1,
		Parent = slot,
	})

	local keyLabel = UI.text({
		Name = "KeyLabel",
		Size = UDim2.new(0.4, 0, 0.28, 0),
		Position = UDim2.fromScale(0.10, 0.06),
		text = props.keyText or "",
		font = Theme.Font.Heading,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = slot.ZIndex + 2,
		Parent = slot,
	})

	local nameLabel = UI.text({
		Name = "NameLabel",
		Size = UDim2.new(0.9, 0, 0.3, 0),
		Position = UDim2.fromScale(0.5, 0.82),
		AnchorPoint = Vector2.new(0.5, 0.5),
		text = "",
		font = Theme.Font.Body,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 14,
		ZIndex = slot.ZIndex + 2,
		Parent = slot,
	})

	return {
		root = slot,
		icon = icon,
		keyLabel = keyLabel,
		nameLabel = nameLabel,
		rarityFrame = rarityFrame,
	}
end

function UI.dimmer(props)
	props = props or {}

	local frame = UI.create("Frame", {
		Name = "Dimmer",
		BackgroundColor3 = Theme.Color.Overlay,
		BackgroundTransparency = props.transparency or 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = props.ZIndex or (Theme.Z.Panel - 1),
		Visible = false,
		Parent = props.Parent,
	})

		local function fit()
		local inset = GuiService:GetGuiInset()
		frame.Position = UDim2.fromOffset(0, -inset.Y)
		frame.Size = UDim2.new(1, 0, 1, inset.Y + 4)
	end

	fit()
	task.defer(fit)
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fit)
	end)

	return frame
end

function UI.responsiveScale(gui: LayerCollector, baseWidth: number?, extra: number?)
	local scaleObj = Instance.new("UIScale")
	local base = baseWidth or 1280

	local function update()
		local vp = gui.AbsoluteSize
		if vp.X <= 0 then
			return
		end
		local s = math.clamp(vp.X / base, 0.62, 1.35)
		if vp.Y < 460 then
			s *= 0.9
		end
		s *= (extra or 1)
		scaleObj.Scale = s

		local parent = scaleObj.Parent
		if parent and parent:IsA("GuiObject") then
			parent.Size = UDim2.fromScale(1 / s, 1 / s)
		end
	end

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	scaleObj:GetPropertyChangedSignal("Parent"):Connect(function()
		task.defer(update)
	end)
	task.defer(update)
	return scaleObj, update
end

function UI.isMobile(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

function UI.topInset(): number
	return GuiService:GetGuiInset().Y
end

return UI

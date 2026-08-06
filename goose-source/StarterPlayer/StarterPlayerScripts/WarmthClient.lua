--!nonstrict

--[[
	새 LocalScript로 StarterPlayerScripts에 넣는다.

	왼쪽에 온기 칩 하나를 띄우고, 칩을 누르면 단계표가 열린다.
	황금알이 떨어지면 알 위에 남은 시간을 띄우고 칩을 금색으로 바꾼다.

	화면에 쓰는 패널·버튼·아이콘은 전부 기존 RadAtlas 스프라이트다.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(Shared.UI.UIBuilder)
local Theme = require(Shared.UI.Theme)
local Atlas = require(Shared.UI.Atlas)
local WarmthConfig = require(Shared.Config.WarmthConfig)
local EggConfig = require(Shared.Config.EggConfig)
local Format = require(Shared.Util.Format)
local Localization = require(Shared.Locale.Localization)
local NetClient = require(Shared.Net.NetClient)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local clientRoot = script.Parent:WaitForChild("Client")
local NotifyController = require(clientRoot.Controllers.NotifyController)

local EGG_TAG = "RadGoldenEgg"

local chip: ImageButton
local chipIcon: ImageLabel
local tierLabel: TextLabel
local multiplierLabel: TextLabel
local dropLabel: TextLabel
local dropIcon: ImageLabel
local progressBar
local panel
local dimmer: Frame
local tierRows: Frame
local panelLeave: TextLabel
local panelDrop: TextLabel
local panelStat: TextLabel
local flashLabel: TextLabel

-- 칩에서 먼저 부르고 아래에서 채운다.
local closePanel
local refreshPanel

--[[
	서버가 보내 준 마지막 상태와 그걸 받은 시각.

	온기는 초당 일정하게 차오르므로 매초 물어볼 이유가 없다.
	받은 값에서 흐른 시간만큼 더해 쓰고, 5초마다 오는 동기화로 맞춘다.
]]
local state = nil
local stateAt = 0
local dropExpiresAt = nil
local shownTierIndex = nil
local shownDropLine = nil

local animated = {}

--------------------------------------------------------------------------------
-- 잔손질
--------------------------------------------------------------------------------

local function mmss(seconds: number): string
	seconds = math.max(math.floor(tonumber(seconds) or 0), 0)
	local minutes = math.floor(seconds / 60)
	if minutes >= 60 then
		return string.format("%d:%02d:%02d", math.floor(minutes / 60), minutes % 60, seconds % 60)
	end
	return string.format("%d:%02d", minutes, seconds % 60)
end

local function eggName(eggId: string?): string
	local egg = eggId and EggConfig.get(eggId)
	return egg and Localization.t(egg.LocaleKey) or tostring(eggId or "?")
end

--- 지금 이 순간의 온기. 마지막 동기화 이후 흐른 시간만큼 앞당겨 계산한다.
local function currentValue(): number
	if not state or not state.ok then
		return 0
	end
	if state.idle then
		return state.value
	end
	local elapsed = os.clock() - stateAt
	return math.clamp(state.value + elapsed * (state.fillPerMinute or 0) / 60, 0, state.max or WarmthConfig.Max)
end

--------------------------------------------------------------------------------
-- 칩
--------------------------------------------------------------------------------

local function buildChip(parent: Frame)
	chip = Atlas.new("ImageButton", "panel_gray", {
		Name = "WarmthChip",
		Size = UDim2.fromOffset(214, 104),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = Theme.Z.Hud + 1,
		Visible = false,
		Parent = parent,
	})
	UI.scale(1, chip)

	chipIcon = Atlas.icon("icon_fire", {
		Name = "TierIcon",
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(12, 10),
		color = Theme.Color.TextInverse,
		ZIndex = chip.ZIndex + 1,
		Parent = chip,
	})

	tierLabel = UI.text({
		Name = "Tier",
		Size = UDim2.fromOffset(108, 28),
		Position = UDim2.fromOffset(48, 11),
		text = "",
		font = Theme.Font.Heading,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = chip.ZIndex + 1,
		Parent = chip,
	})

	multiplierLabel = UI.text({
		Name = "Multiplier",
		Size = UDim2.fromOffset(56, 28),
		Position = UDim2.fromOffset(150, 11),
		text = "x1.00",
		font = Theme.Font.Number,
		textColor = Theme.Color.Cash,
		maxTextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = chip.ZIndex + 1,
		Parent = chip,
	})

	progressBar = UI.bar({
		Name = "Progress",
		Size = UDim2.fromOffset(190, 16),
		Position = UDim2.fromOffset(12, 46),
		ZIndex = chip.ZIndex + 1,
		value = 0,
		Parent = chip,
	})

	dropIcon = Atlas.icon("icon_egg", {
		Name = "DropIcon",
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.fromOffset(13, 70),
		color = Theme.Color.Cash,
		ZIndex = chip.ZIndex + 1,
		Parent = chip,
	})

	dropLabel = UI.text({
		Name = "Drop",
		Size = UDim2.fromOffset(164, 24),
		Position = UDim2.fromOffset(44, 70),
		text = "",
		font = Theme.Font.Body,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = chip.ZIndex + 1,
		Parent = chip,
	})

	--[[
		panel.close() 는 애니메이션이 끝난 뒤에야 Visible 을 내린다.
		누른 직후의 Visible 로 디머를 정하면 창은 닫혔는데 화면만 어두운 채로 남는다.
	]]
	chip.MouseButton1Click:Connect(function()
		UI.playSound(Theme.Sound.Click)
		if panel.root.Visible then
			closePanel()
		else
			panel.open()
			dimmer.Visible = true
			refreshPanel()
		end
	end)
end

local function pulseChip(scale: number)
	local scaleObj = chip:FindFirstChildOfClass("UIScale")
	if not scaleObj then
		return
	end
	scaleObj.Scale = scale
	TweenService:Create(scaleObj, Theme.Tween.Bounce, { Scale = 1 }):Play()
end

--------------------------------------------------------------------------------
-- 단계표
--------------------------------------------------------------------------------

local function buildTierRow(index: number, tier, parent: Frame)
	local row = Atlas.new("ImageLabel", "panel_" .. (tier.Palette or "gray"), {
		Name = "Tier" .. tostring(index),
		Size = UDim2.new(1, -6, 0, 54),
		LayoutOrder = index,
		Parent = parent,
	})

	Atlas.icon(tier.Icon or "icon_fire", {
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(14, 12),
		color = Theme.Color.TextInverse,
		ZIndex = row.ZIndex + 1,
		Parent = row,
	})

	UI.text({
		Name = "Name",
		Size = UDim2.fromOffset(150, 26),
		Position = UDim2.fromOffset(52, 14),
		localeKey = tier.LocaleKey,
		font = Theme.Font.Heading,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = row.ZIndex + 1,
		Parent = row,
	})

	local detail = UI.text({
		Name = "Detail",
		Size = UDim2.new(1, -216, 0, 26),
		Position = UDim2.new(1, -10, 0, 14),
		AnchorPoint = Vector2.new(1, 0),
		font = Theme.Font.Body,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = row.ZIndex + 1,
		Parent = row,
	})
	Localization.bind(detail, "Text", "warmth_tier_row", {
		math.floor(tier.Threshold),
		string.format("%.2f", tier.Multiplier),
	})

	local marker = UI.text({
		Name = "Marker",
		Size = UDim2.fromOffset(56, 22),
		Position = UDim2.fromOffset(52, 34),
		localeKey = "warmth_current",
		font = Theme.Font.Heading,
		textColor = Theme.Color.Cash,
		maxTextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = row.ZIndex + 1,
		Parent = row,
	})

	return row, marker
end

local markers = {}

local function buildPanel(parent: Frame)
	dimmer = UI.dimmer({ ZIndex = Theme.Z.Panel - 1, Parent = parent })

	panel = UI.window({
		Name = "WarmthPanel",
		Size = UDim2.fromOffset(560, 560),
		localeKey = "warmth_title",
		icon = "icon_fire",
		ZIndex = Theme.Z.Panel,
		Parent = parent,
		onClose = function()
			panel.close()
			dimmer.Visible = false
		end,
	})

	UI.text({
		Name = "Hint",
		Size = UDim2.new(1, -12, 0, 40),
		Position = UDim2.fromOffset(6, 0),
		localeKey = "warmth_panel_hint",
		font = Theme.Font.Body,
		textColor = Theme.Color.Text,
		stroke = false,
		maxTextSize = 17,
		TextWrapped = true,
		ZIndex = panel.content.ZIndex + 1,
		Parent = panel.content,
	})

	tierRows = UI.create("Frame", {
		Name = "Tiers",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 0, #WarmthConfig.Tiers * 60),
		Position = UDim2.fromOffset(6, 44),
		ZIndex = panel.content.ZIndex + 1,
		Parent = panel.content,
	})
	UI.list({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
	}, tierRows)

	for index, tier in ipairs(WarmthConfig.Tiers) do
		local _, marker = buildTierRow(index, tier, tierRows)
		markers[index] = marker
	end

	local footer = UI.create("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 0, 108),
		Position = UDim2.new(0, 6, 1, -4),
		AnchorPoint = Vector2.new(0, 1),
		ZIndex = panel.content.ZIndex + 1,
		Parent = panel.content,
	})
	UI.list({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 4),
	}, footer)

	local function footerLine(order: number, key: string, color: Color3)
		local label = UI.text({
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = order,
			localeKey = key,
			font = Theme.Font.Body,
			textColor = color,
			stroke = false,
			maxTextSize = 17,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = footer.ZIndex + 1,
			Parent = footer,
		})
		return label
	end

	panelDrop = footerLine(1, "warmth_panel_drop", Theme.Color.Text)
	panelLeave = footerLine(2, "warmth_panel_leave", Theme.Color.Danger)
	panelStat = footerLine(3, "warmth_panel_stat", Theme.Color.TextMuted)

	Localization.bind(panelDrop, "Text", "warmth_panel_drop", {
		mmss(WarmthConfig.Drop.LifetimeSeconds),
	})
	Localization.bind(panelLeave, "Text", "warmth_panel_leave", {
		mmss(WarmthConfig.GraceSeconds),
		WarmthConfig.DecayPerMinute,
	})
	Localization.bind(panelStat, "Text", "warmth_panel_stat", { 0 })
end

--------------------------------------------------------------------------------
-- 가운데 알림
--------------------------------------------------------------------------------

local function buildFlash(parent: Frame)
	flashLabel = UI.text({
		Name = "Flash",
		Size = UDim2.fromOffset(720, 64),
		Position = UDim2.fromScale(0.5, 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		text = "",
		font = Theme.Font.Number,
		textColor = Theme.Color.Cash,
		strokeColor = Theme.Color.Dark,
		stroke = 4,
		maxTextSize = 46,
		Visible = false,
		ZIndex = Theme.Z.Alert,
		Parent = parent,
	})
end

local function flash(text: string)
	if not flashLabel then
		return
	end
	flashLabel.Text = text
	flashLabel.Visible = true
	flashLabel.TextTransparency = 0

	local scaleObj = flashLabel:FindFirstChildOfClass("UIScale") or UI.scale(1, flashLabel)
	scaleObj.Scale = 0.6
	TweenService:Create(scaleObj, Theme.Tween.Bounce, { Scale = 1 }):Play()

	task.delay(1.6, function()
		if not flashLabel or flashLabel.Text ~= text then
			return
		end
		local out = TweenService:Create(flashLabel, Theme.Tween.Slow, { TextTransparency = 1 })
		out.Completed:Once(function()
			if flashLabel and flashLabel.Text == text then
				flashLabel.Visible = false
			end
		end)
		out:Play()
	end)
end

--------------------------------------------------------------------------------
-- 화면 갱신
--------------------------------------------------------------------------------

local function refreshChip()
	if not state or not state.ok then
		return
	end

	local value = currentValue()
	local index = WarmthConfig.tierIndexFor(value)
	local tier = WarmthConfig.tier(index)
	local nextTier = WarmthConfig.nextTier(index)

	chip.Visible = true

	--[[
		단계가 바뀔 때만 그림과 글씨를 갈아 끼운다.
		매초 다시 칠하면 슬라이스와 바인딩을 초당 한 번씩 새로 만드는 셈이 된다.
	]]
	if index ~= shownTierIndex then
		Atlas.apply(chip, "panel_" .. (tier.Palette or "gray"))
		Atlas.apply(chipIcon, tier.Icon or "icon_fire", { color = Theme.Color.TextInverse, fit = true })
		Localization.bind(tierLabel, "Text", tier.LocaleKey)
		multiplierLabel.Text = string.format("x%.2f", tier.Multiplier)

		if shownTierIndex ~= nil and index > shownTierIndex then
			pulseChip(1.35)
		end
		shownTierIndex = index
		for i, marker in pairs(markers) do
			marker.Visible = i == index
		end
	end

	--[[
		막대는 다음 단계까지의 거리를 보여 준다.
		최고 단계에서는 가득 채운 채로 둔다 — 0으로 되돌아가면 잃은 줄 안다.
	]]
	if nextTier then
		local span = math.max(nextTier.Threshold - tier.Threshold, 1)
		progressBar.set(math.clamp((value - tier.Threshold) / span, 0, 1))
	else
		progressBar.set(1)
	end

	-- 아래 줄은 상황에 따라 세 가지 중 하나다: 방치 / 주우러 가기 / 다음 알까지
	local now = Workspace:GetServerTimeNow()
	local line, args, color

	if state.idle then
		line, args, color = "warmth_idle", nil, Theme.Color.Gray
	elseif dropExpiresAt and dropExpiresAt - now > 0 then
		line, args, color = "warmth_egg_waiting", { mmss(dropExpiresAt - now) }, Theme.Color.Cash
	elseif state.nextDropAt then
		line, args, color = "warmth_egg_next", { mmss(state.nextDropAt - now) }, Theme.Color.TextInverse
	else
		line, args, color = "warmth_egg_next", { "--:--" }, Theme.Color.TextInverse
	end

	dropIcon.ImageColor3 = color
	if line ~= shownDropLine then
		shownDropLine = line
		Localization.bind(dropLabel, "Text", line, args)
	elseif args then
		Localization.setArgs(dropLabel, "Text", args)
	end
end

function refreshPanel()
	if not state or not state.ok or not panel or not panel.root.Visible then
		return
	end
	Localization.setArgs(panelStat, "Text", { math.floor(state.eggsClaimed or 0) })
end

--------------------------------------------------------------------------------
-- 월드의 황금알
--------------------------------------------------------------------------------

local function makeTimerGui(part: BasePart): TextLabel
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RadGoldenEggTimer"
	billboard.Size = UDim2.fromOffset(160, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 260
	billboard.Parent = part

	return UI.text({
		Size = UDim2.fromScale(1, 1),
		text = "",
		font = Theme.Font.Number,
		textColor = Theme.Color.Cash,
		strokeColor = Theme.Color.Dark,
		stroke = 3,
		maxTextSize = 30,
		Parent = billboard,
	})
end

local function trackEgg(model: Instance)
	if not model:IsA("Model") or model:GetAttribute(EGG_TAG) ~= true or animated[model] then
		return
	end

	--[[
		복제는 모델 먼저, 자식은 그 뒤에 온다.
		알맹이가 도착할 때까지 몇 프레임 기다린다.
	]]
	local part = model:WaitForChild("Egg", 5)
	if not part or not part:IsA("BasePart") then
		part = model.PrimaryPart
	end
	if not part or not part:IsA("BasePart") or not model.Parent or animated[model] then
		return
	end

	local mine = model:GetAttribute("OwnerUserId") == player.UserId
	animated[model] = {
		part = part,
		origin = part.Position,
		phase = math.random() * math.pi * 2,
		timer = mine and makeTimerGui(part) or nil,
	}

	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			animated[model] = nil
		end
	end)
end

local function animateEggs()
	local now = Workspace:GetServerTimeNow()
	for model, entry in pairs(animated) do
		if not model.Parent or not entry.part.Parent then
			animated[model] = nil
		else
			--[[
				서버는 알을 놓기만 하고 움직이지 않는다.
				여기서 바꾸는 CFrame 은 이 화면에만 남으므로 복제와 싸우지 않는다.
				줍는 판정은 서버가 처음 놓은 자리에서 재기 때문에 결과도 같다.
			]]
			local bob = math.sin(now * 1.6 + entry.phase) * 0.55
			entry.part.CFrame = CFrame.new(entry.origin + Vector3.new(0, bob, 0))
				* CFrame.Angles(0, now * 1.1, math.rad(6))

			if entry.timer and dropExpiresAt then
				entry.timer.Text = mmss(dropExpiresAt - now)
			end
		end
	end
end

local function watchWorld()
	for _, child in ipairs(Workspace:GetChildren()) do
		task.spawn(trackEgg, child)
	end
	Workspace.ChildAdded:Connect(function(child)
		task.spawn(trackEgg, child)
	end)
	RunService.RenderStepped:Connect(animateEggs)
end

--------------------------------------------------------------------------------
-- 서버와의 연결
--------------------------------------------------------------------------------

local function applyState(payload)
	if type(payload) ~= "table" or not payload.ok then
		return
	end
	state = payload
	stateAt = os.clock()
	dropExpiresAt = payload.dropExpiresAt
	refreshChip()
	refreshPanel()
end

local function onDrop(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.state == "incoming" then
		local seconds = math.max(math.floor((payload.at or 0) - Workspace:GetServerTimeNow() + 0.5), 1)
		NotifyController.toast({
			key = "warmth_egg_incoming",
			args = { seconds },
			kind = "info",
			icon = "icon_clock",
			duration = 4,
		})
		pulseChip(1.15)
		return
	end

	if payload.state == "landed" then
		dropExpiresAt = payload.expiresAt
		if state then
			state.nextDropAt = nil
			state.dropExpiresAt = payload.expiresAt
		end
		flash(Localization.t("warmth_egg_landed"))
		NotifyController.toast({
			key = "warmth_egg_landed",
			kind = "rare",
			icon = "icon_egg",
			duration = 5,
		})
		pulseChip(1.3)
		refreshChip()
		return
	end

	if payload.state == "claimed" then
		dropExpiresAt = nil
		if state then
			state.nextDropAt = payload.nextDropAt
			state.dropExpiresAt = nil
		end

		NotifyController.toast({
			key = "warmth_egg_claimed",
			args = { Format.money(payload.cash or 0) },
			kind = "success",
			icon = "icon_money",
			duration = 5,
		})
		flash("+" .. Format.money(payload.cash or 0))

		for _, extra in ipairs(payload.extras or {}) do
			if extra.kind == "egg" then
				NotifyController.toast({
					key = "warmth_egg_bonus_egg",
					args = { eggName(extra.eggId) },
					kind = "rare",
					icon = "icon_egg",
					duration = 5,
				})
			elseif extra.kind == "spin" then
				NotifyController.toast({
					key = "warmth_egg_bonus_spin",
					kind = "rare",
					icon = "icon_spin",
					duration = 5,
				})
			elseif extra.kind == "egg_failed" then
				NotifyController.toast({
					key = "warmth_egg_bonus_full",
					args = { eggName(extra.eggId) },
					kind = "info",
					icon = "icon_bag",
					duration = 5,
				})
			end
		end

		refreshChip()
		return
	end

	if payload.state == "expired" then
		dropExpiresAt = nil
		if state then
			state.nextDropAt = payload.nextDropAt
			state.dropExpiresAt = nil
		end
		NotifyController.toast({
			key = "warmth_egg_expired",
			kind = "error",
			icon = "icon_warning",
			duration = 4,
		})
		refreshChip()
	end
end

--[[
	화면을 둘로 나눈다.

	칩은 HUD 높이에 있어야 상점을 열면 가려진다.
	단계표는 다른 창과 같은 높이여야 디머가 HUD 를 덮는다.
	한 ScreenGui 에 다 넣으면 둘 중 하나는 반드시 어긋난다.
]]
local function makeScreen(name: string, order: number)
	local gui = UI.create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order,
		Parent = playerGui,
	})

	local root = UI.create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	local scaleObj = UI.responsiveScale(gui)
	scaleObj.Parent = root
	return root
end

function closePanel()
	if panel and panel.root.Visible then
		panel.close()
	end
	if dimmer then
		dimmer.Visible = false
	end
end

local function start()
	local hudRoot = makeScreen("RadWarmth", Theme.Z.Hud + 1)
	local panelRoot = makeScreen("RadWarmthPanel", Theme.Z.Panel)

	buildChip(hudRoot)
	buildPanel(panelRoot)
	buildFlash(panelRoot)
	watchWorld()

	UserInputService.InputBegan:Connect(function(inputObject, processed)
		if not processed and inputObject.KeyCode == Enum.KeyCode.Escape then
			closePanel()
		end
	end)

	NetClient.on("WarmthSync", applyState)
	NetClient.on("WarmthDrop", onDrop)
	Localization.Changed:Connect(refreshChip)

	--[[
		1초마다 다시 그린다. 서버에 묻지 않는다 —
		온기가 차는 속도도, 알이 떨어지는 시각도 이미 알고 있다.
	]]
	task.spawn(function()
		while true do
			task.wait(1)
			pcall(refreshChip)
			pcall(refreshPanel)
		end
	end)

	task.spawn(function()
		for _ = 1, 5 do
			local result = NetClient.invoke("WarmthGetState", 8)
			if type(result) == "table" and result.ok then
				applyState(result)
				return
			end
			task.wait(3)
		end
	end)
end

local ok, err = pcall(start)
if not ok then
	warn("[WarmthClient] 둥지 온기 화면 시작 실패: " .. tostring(err))
end

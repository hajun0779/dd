--!nonstrict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local UI = require(Shared.UI.UIBuilder)
local Theme = require(Shared.UI.Theme)
local Atlas = require(Shared.UI.Atlas)
local EggVisual = require(Shared.UI.EggVisual)
local GameConfig = require(Shared.Config.GameConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local GooseConfig = require(Shared.Config.GooseConfig)
local EggConfig = require(Shared.Config.EggConfig)
local Localization = require(Shared.Locale.Localization)
local NetClient = require(Shared.Net.NetClient)

local ClientState = require(script.Parent.Parent.ClientState)
local NotifyController = require(script.Parent.NotifyController)

local InventoryController = {}

local HOTBAR = GameConfig.Inventory.HotbarSlots
local DRAG_THRESHOLD = 8

local player = Players.LocalPlayer
local screen: ScreenGui
local hotbarFrame: Frame
local installButton: ImageButton
local slots = {}
local ghost: ImageLabel? = nil
local installBusy = false

local drag = {
	active = false,
	fromIndex = nil,
	inputObject = nil,
	startPos = nil,
	moved = false,
	hasItem = false,
}

local function itemDisplayName(item): string
	if not item then
		return ""
	end
	if item.kind == "Tool" then
		return item.name
	end
	if item.kind == "Goose" then
		local cfg = GooseConfig.get(item.gooseId)
		return cfg and Localization.t(cfg.LocaleKey) or item.gooseId or "?"
	else
		local cfg = EggConfig.get(item.eggId)
		return cfg and Localization.t(cfg.LocaleKey) or item.eggId or "?"
	end
end

local function itemIcon(item): string
	if not item then
		return "icon_egg"
	end
	if item.kind == "Tool" then
		return "icon_hand"
	end
	return item.kind == "Goose" and "icon_goose" or "icon_egg"
end

local function paintSlot(slot, item, index: number)
	slot.index = index

	if not item then
		Atlas.apply(slot.root, "slot_empty")
		slot.icon.Visible = false
		slot.nameLabel.Text = ""
		slot.rarityFrame.Visible = false
		return
	end

	local equipped = item.kind == "Tool" and item.equipped
	Atlas.apply(slot.root, equipped and "slot_selected" or "slot_filled")
	slot.icon.Visible = true
	Atlas.apply(slot.icon, itemIcon(item), { color = Color3.fromRGB(255, 255, 255), fit = true })

	if item.kind == "Tool" then
		EggVisual.clear(slot.icon)
		slot.icon.ImageColor3 = equipped and Theme.Color.Yellow or Color3.fromRGB(235, 240, 250)
		slot.rarityFrame.Visible = false
	elseif item.kind == "Egg" then
		--[[
			알은 등급 색이 아니라 그 알의 색으로 칠한다.

			등급으로 칠하면 종류가 스물여섯인데 화면에는 여섯 색만 나온다.
			등급은 테두리(rarityFrame)가 이미 말해 주고 있다.
		]]
		EggVisual.applyIcon(slot.icon, item.eggId)
		slot.rarityFrame.Visible = true
		Atlas.apply(slot.rarityFrame, Atlas.rarityFrame(item.rarity))
	else
		local rarity = RarityConfig.get(item.rarity)
		EggVisual.clear(slot.icon)
		slot.icon.ImageColor3 = rarity.Glow
		slot.rarityFrame.Visible = true
		Atlas.apply(slot.rarityFrame, Atlas.rarityFrame(item.rarity))
	end

	slot.nameLabel.Text = itemDisplayName(item)
end

--- 지금 들고 있거나 가방에 있는 Tool 들
local function collectTools()
	local tools = {}
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")

	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then
				table.insert(tools, { kind = "Tool", tool = child, name = child.Name, equipped = true })
			end
		end
	end
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				table.insert(tools, { kind = "Tool", tool = child, name = child.Name, equipped = false })
			end
		end
	end

	table.sort(tools, function(a, b)
		return a.name < b.name
	end)
	return tools
end

--[[
	핫바에 보이는 목록 = Tool 들 + 기지에 놓지 않은 알/거위.

	Tool 은 앞쪽 칸을 차지하고, 그 칸을 누르면 들거나 내려놓는다.
	mapping 은 알/거위만 대상으로 하므로 순서 바꾸기는 그쪽에만 적용된다.
]]
local function computeVisible()
	local visible, mapping = {}, {}
	local placed = ClientState.placed or {}

	for _, tool in ipairs(collectTools()) do
		table.insert(visible, tool)
		table.insert(mapping, false)
	end

	for fullIndex, item in ipairs(ClientState.inventory) do
		if not placed[item.uid] then
			table.insert(visible, item)
			table.insert(mapping, fullIndex)
		end
	end
	return visible, mapping
end

local function selectedPlaceable()
	local visible = computeVisible()
	local item = visible[ClientState.selectedSlot or 1]
	if item and (item.kind == "Egg" or item.kind == "Goose") and type(item.uid) == "string" then
		return item
	end
	return nil
end

local function updateInstallButton()
	if not installButton then
		return
	end
	local available = selectedPlaceable() ~= nil and ClientState.carrying ~= true
	installButton.Visible = available
	installButton.Active = available and not installBusy
	installButton.Selectable = available and not installBusy
	Atlas.apply(installButton, available and not installBusy and "btn_green" or "btn_gray")
end

function InventoryController.refresh()
	local visible = computeVisible()
	for i = 1, HOTBAR do
		local slot = slots[i]
		if slot then
			paintSlot(slot, visible[i], i)
		end
	end
	updateInstallButton()
end

local function installSelected()
	if installBusy then
		return
	end
	local item = selectedPlaceable()
	if not item then
		return
	end

	installBusy = true
	updateInstallButton()
	task.spawn(function()
		local result = NetClient.invoke("InventoryPlace", 8, item.uid)
		installBusy = false
		if not result or not result.ok then
			local reason = result and result.reason
			local key = reason == "base_full" and "inventory_base_full"
				or reason == "no_base" and "inventory_no_base"
				or "inventory_install_failed"
			NotifyController.toast({ key = key, kind = "error" })
		end
		InventoryController.refresh()
	end)
end

--[[
	Tool 칸을 누르면 들고, 다시 누르면 내려놓는다.
	다른 칸을 누르면 들고 있던 Tool 을 내려놓는다.
]]
local function applyToolSelection(index: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local visible = computeVisible()
	local entry = visible[index]

	if entry and entry.kind == "Tool" then
		if entry.equipped then
			humanoid:UnequipTools()
		else
			pcall(function()
				humanoid:EquipTool(entry.tool)
			end)
		end
	else
		humanoid:UnequipTools()
	end

	task.defer(function()
		InventoryController.refresh()
	end)
end

local function setSelected(index: number, silent: boolean?)
	ClientState.selectedSlot = index
	for i, slot in ipairs(slots) do
		local scale = slot.root:FindFirstChildOfClass("UIScale")
		if scale then
			TweenService:Create(scale, Theme.Tween.Fast, {
				Scale = i == index and 1.12 or 1,
			}):Play()
		end
	end
	if not silent then
		NetClient.fire("InventorySelect", index)
		applyToolSelection(index)
	end
	updateInstallButton()
end

local function createGhost(item)
	if ghost then
		ghost:Destroy()
	end
	ghost = Atlas.new("ImageLabel", "slot_drag", {
		Name = "DragGhost",
		Size = UDim2.fromOffset(Theme.Size.HotbarSlot.X, Theme.Size.HotbarSlot.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = Theme.Z.Drag,
		Parent = screen,
	})
	ghost.ImageTransparency = 0.1

	local icon = Atlas.icon(itemIcon(item), {
		Size = UDim2.fromScale(0.62, 0.62),
		Position = UDim2.fromScale(0.5, 0.44),
		AnchorPoint = Vector2.new(0.5, 0.5),
		color = RarityConfig.get(item.rarity).Glow,
		ZIndex = Theme.Z.Drag + 1,
		Parent = ghost,
	})
	EggVisual.applyItem(icon, item)

	UI.text({
		Size = UDim2.new(0.9, 0, 0.3, 0),
		Position = UDim2.fromScale(0.5, 0.82),
		AnchorPoint = Vector2.new(0.5, 0.5),
		text = itemDisplayName(item),
		font = Theme.Font.Body,
		textColor = Theme.Color.TextInverse,
		maxTextSize = 14,
		ZIndex = Theme.Z.Drag + 1,
		Parent = ghost,
	})

	return ghost
end

local function slotIndexAtPosition(position: Vector2): number?
	for i, slot in ipairs(slots) do
		local root = slot.root
		local pos = root.AbsolutePosition
		local size = root.AbsoluteSize
		local pad = 6
		if position.X >= pos.X - pad and position.X <= pos.X + size.X + pad
			and position.Y >= pos.Y - pad and position.Y <= pos.Y + size.Y + pad
		then
			return i
		end
	end
	return nil
end

local function endDrag(dropPosition: Vector2?)
	local fromIndex = drag.fromIndex
	local moved = drag.moved

	drag.active = false
	drag.fromIndex = nil
	drag.inputObject = nil
	drag.moved = false
	drag.hasItem = false

	if ghost then
		ghost:Destroy()
		ghost = nil
	end

	for _, slot in ipairs(slots) do
		slot.root.ImageTransparency = 0
	end

	if not fromIndex then
		return
	end

	if not moved or not dropPosition then
		setSelected(fromIndex)
		return
	end

	local toIndex = slotIndexAtPosition(dropPosition)
	if not toIndex or toIndex == fromIndex then
		return
	end

	local visible, mapping = computeVisible()
	local fromFull = mapping[fromIndex]
	local toFull = mapping[toIndex]
	if not visible[fromIndex] or type(fromFull) ~= "number" or type(toFull) ~= "number" then
		return
	end

	local full = table.clone(ClientState.inventory)
	local item = table.remove(full, fromFull)
	if fromFull < toFull then
		toFull -= 1
	end
	table.insert(full, math.clamp(toFull, 1, #full + 1), item)
	ClientState.inventory = full

	InventoryController.refresh()

	local order = table.create(#full)
	for i, entry in ipairs(full) do
		order[i] = entry.uid
	end
	NetClient.fire("InventoryReorder", order)
end

local function beginDrag(index: number, inputObject: InputObject)
	if ClientState.carrying then
		return
	end

	drag.active = true
	drag.fromIndex = index
	drag.inputObject = inputObject
	drag.startPos = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
	drag.moved = false
	local visible = computeVisible()
	drag.hasItem = visible[index] ~= nil and visible[index].kind ~= "Tool"
end

local function updateDrag(position: Vector2)
	if not drag.active then
		return
	end
	if not drag.hasItem then
		return
	end

	if not drag.moved then
		if (position - drag.startPos).Magnitude < DRAG_THRESHOLD then
			return
		end
		drag.moved = true
		local visible = computeVisible()
		local item = visible[drag.fromIndex]
		if item then
			createGhost(item)
			local slot = slots[drag.fromIndex]
			if slot then
				slot.root.ImageTransparency = 0.6
			end
		end
	end

	if ghost then
		ghost.Position = UDim2.fromOffset(position.X, position.Y)
	end

	local hovered = slotIndexAtPosition(position)
	local visible = computeVisible()
	for i, slot in ipairs(slots) do
		if i ~= drag.fromIndex then
			Atlas.apply(slot.root, (i == hovered) and "slot_selected" or
				(visible[i] and "slot_filled" or "slot_empty"))
		end
	end
end

local KEY_LABELS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }

local NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,

	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.KeypadFive] = 5,
	[Enum.KeyCode.KeypadSix] = 6,
	[Enum.KeyCode.KeypadSeven] = 7,
	[Enum.KeyCode.KeypadEight] = 8,
	[Enum.KeyCode.KeypadNine] = 9,
	[Enum.KeyCode.KeypadZero] = 10,
}

local function buildHotbar(parent: Frame)
	local isMobile = UI.isMobile()
	local slotSize = isMobile and Theme.Size.HotbarSlotMobile or Theme.Size.HotbarSlot

	local bottomMargin = isMobile and Theme.Size.HotbarMarginMobile or Theme.Size.HotbarMargin

	hotbarFrame = UI.create("Frame", {
		Name = "Hotbar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(HOTBAR * (slotSize.X + 6), slotSize.Y + 8),
		Position = UDim2.new(0.5, 0, 1, -bottomMargin),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = Theme.Z.Hotbar,
		Parent = parent,
	})

	UI.list({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}, hotbarFrame)

	for i = 1, HOTBAR do
		local slot = UI.slot({
			Name = "Slot" .. i,
			Size = UDim2.fromOffset(slotSize.X, slotSize.Y),
			keyText = KEY_LABELS[i],
			LayoutOrder = i,
			ZIndex = Theme.Z.Hotbar,
			Parent = hotbarFrame,
		})
		UI.scale(1, slot.root)
		slot.index = i
		slots[i] = slot

		slot.root.InputBegan:Connect(function(inputObject)
			if inputObject.UserInputType == Enum.UserInputType.MouseButton1
				or inputObject.UserInputType == Enum.UserInputType.Touch
			then
				beginDrag(i, inputObject)
			end
		end)

		slot.root.MouseButton1Click:Connect(function()
			if ClientState.carrying then
				return
			end
			setSelected(i)
		end)
	end

	installButton = UI.button({
		Name = "InstallSelected",
		palette = "green",
		localeKey = "inventory_install",
		Size = UDim2.fromOffset(isMobile and 176 or 204, isMobile and 38 or 44),
		Position = UDim2.new(0.5, 0, 1, -(bottomMargin + slotSize.Y + 10)),
		AnchorPoint = Vector2.new(0.5, 1),
		maxTextSize = isMobile and 15 or 18,
		ZIndex = Theme.Z.Hotbar + 3,
		Parent = parent,
		onClick = installSelected,
	})
	installButton.Visible = false

	return hotbarFrame
end

function InventoryController.start(playerGui: PlayerGui)
	screen = UI.create("ScreenGui", {
		Name = "RadInventory",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = Theme.Z.Hotbar,
		Parent = playerGui,
	})

	local root = UI.create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = screen,
	})
	local scaleObj = UI.responsiveScale(screen)
	scaleObj.Parent = root

	buildHotbar(root)
	InventoryController.refresh()
	setSelected(1)

	UserInputService.InputChanged:Connect(function(inputObject)
		if not drag.active then
			return
		end
		if inputObject.UserInputType == Enum.UserInputType.MouseMovement
			or inputObject.UserInputType == Enum.UserInputType.Touch
		then
			updateDrag(Vector2.new(inputObject.Position.X, inputObject.Position.Y))
		end
	end)

	UserInputService.InputEnded:Connect(function(inputObject)
		if not drag.active then
			return
		end
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1
			or inputObject.UserInputType == Enum.UserInputType.Touch
		then
			endDrag(Vector2.new(inputObject.Position.X, inputObject.Position.Y))
			InventoryController.refresh()
		end
	end)

	UserInputService.InputBegan:Connect(function(inputObject, processed)
		if processed or ClientState.carrying then
			return
		end
		if inputObject.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local index = NUMBER_KEYS[inputObject.KeyCode]
		if index and slots[index] then
			setSelected(index)
		end
	end)

	--[[
		Tool 이 가방↔손 사이를 오갈 때마다 핫바를 다시 그린다.
		(들고 있는 표시가 실제 상태와 어긋나지 않게)
	]]
	local function watchTools()
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			backpack.ChildAdded:Connect(function()
				task.defer(InventoryController.refresh)
			end)
			backpack.ChildRemoved:Connect(function()
				task.defer(InventoryController.refresh)
			end)
		end

		local character = player.Character
		if character then
			character.ChildAdded:Connect(function(child)
				if child:IsA("Tool") then
					task.defer(InventoryController.refresh)
				end
			end)
			character.ChildRemoved:Connect(function(child)
				if child:IsA("Tool") then
					task.defer(InventoryController.refresh)
				end
			end)
		end
	end

	watchTools()
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		watchTools()
		InventoryController.refresh()
	end)

	ClientState.InventoryChanged:Connect(function()
		InventoryController.refresh()
		local saved = ClientState.savedSlot
		if saved and slots[saved] and saved ~= ClientState.selectedSlot then
			setSelected(saved, true)
		end
	end)

	ClientState.CarryChanged:Connect(function(carrying)
		if carrying and drag.active then
			endDrag(nil)
		end
		hotbarFrame.Visible = not carrying
		updateInstallButton()
	end)

	Localization.Changed:Connect(function()
		InventoryController.refresh()
	end)

	InventoryController.screen = screen
	return screen
end

return InventoryController

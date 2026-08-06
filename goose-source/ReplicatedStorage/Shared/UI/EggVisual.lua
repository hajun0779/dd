--!nonstrict

--[[
	알 아이콘.

	알은 스물여섯 종인데 화면에서는 전부 같은 아이콘 하나였다.
	색도 등급(Glow)으로만 칠해서, 결국 눈에 보이는 건 두어 가지였다.
	가방을 열면 어느 게 무슨 알인지 알 수 없었다.

	그래서 두 겹으로 그린다.

	  껍데기  icon_egg 를 그 알의 Color 로 칠한다      → 멀리서도 색으로 구분
	  무늬    그 알의 Glyph 를 Accent 로 얹는다        → 가까이서 기호로 확정

	색만으로는 스물여섯을 못 나눈다(비슷한 파랑이 넷이다). 기호만으로도 안 된다
	(작은 슬롯에서는 안 읽힌다). 둘을 같이 써야 한 눈에 갈린다.

	이미 있는 ImageLabel 에 덧씌우는 방식이라, 부르는 쪽은 한 줄만 바꾸면 된다.
]]
local EggConfig = require(script.Parent.Parent.Config.EggConfig)
local Atlas = require(script.Parent.Atlas)

local EggVisual = {}

local GLYPH_NAME = "EggGlyph"

local DEFAULT_SHELL = Color3.fromRGB(245, 240, 228)
local DEFAULT_ACCENT = Color3.fromRGB(214, 200, 176)
local DEFAULT_GLYPH = "icon_dots"

--- 도감에서 아직 못 찾은 칸
local DIM_SHELL = Color3.fromRGB(70, 76, 92)
local DIM_ACCENT = Color3.fromRGB(52, 58, 72)

local function isImage(instance): boolean
	return typeof(instance) == "Instance"
		and (instance:IsA("ImageLabel") or instance:IsA("ImageButton"))
end

function EggVisual.shell(eggId: string?): Color3
	local egg = EggConfig.get(eggId)
	return (egg and egg.Color) or DEFAULT_SHELL
end

function EggVisual.accent(eggId: string?): Color3
	local egg = EggConfig.get(eggId)
	return (egg and egg.Accent) or DEFAULT_ACCENT
end

function EggVisual.glyph(eggId: string?): string
	local egg = EggConfig.get(eggId)
	local name = egg and egg.Glyph or DEFAULT_GLYPH
	return Atlas.has(name) and name or DEFAULT_GLYPH
end

--[[
	무늬를 지운다.

	같은 슬롯이 알과 거위를 번갈아 보여 주므로 반드시 필요하다.
	안 지우면 거위 아이콘 위에 눈송이가 남는다.
]]
function EggVisual.clear(image)
	if not isImage(image) then
		return image
	end
	local glyph = image:FindFirstChild(GLYPH_NAME)
	if glyph then
		glyph.Visible = false
	end
	return image
end

--[[
	opts
	  dim         못 찾은 칸처럼 어둡게
	  glyphScale  무늬 크기 (아이콘 대비 비율)
	  shell       껍데기 색을 직접 지정
	  glyphColor  무늬 색을 직접 지정
]]
function EggVisual.applyIcon(image, eggId: string?, opts)
	if not isImage(image) then
		return image
	end
	opts = opts or {}

	Atlas.apply(image, "icon_egg", { fit = true })
	image.ImageColor3 = opts.shell or (opts.dim and DIM_SHELL or EggVisual.shell(eggId))

	local glyph = image:FindFirstChild(GLYPH_NAME)
	if not glyph or not isImage(glyph) then
		if glyph then
			glyph:Destroy()
		end
		glyph = Atlas.icon(EggVisual.glyph(eggId), {
			Name = GLYPH_NAME,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = image,
		})
	else
		Atlas.apply(glyph, EggVisual.glyph(eggId), { fit = true })
	end

	local scale = math.clamp(tonumber(opts.glyphScale) or 0.44, 0.15, 0.8)
	glyph.Size = UDim2.fromScale(scale, scale)
	--[[
		한가운데가 아니라 조금 아래.
		알은 위가 좁아서 정중앙에 놓으면 무늬가 껍데기 밖으로 삐져나와 보인다.
	]]
	glyph.Position = UDim2.fromScale(0.5, 0.56)
	glyph.ImageColor3 = opts.glyphColor or (opts.dim and DIM_ACCENT or EggVisual.accent(eggId))
	glyph.ImageTransparency = image.ImageTransparency
	glyph.ZIndex = image.ZIndex + 1
	glyph.Visible = true

	return image
end

--[[
	알이면 알처럼, 아니면 원래 아이콘 그대로.

	가방 슬롯처럼 알·거위·도구가 섞여 나오는 곳에서 쓴다.
]]
function EggVisual.applyItem(image, item, opts)
	if not isImage(image) then
		return image
	end
	if type(item) == "table" and item.kind == "Egg" and item.eggId then
		return EggVisual.applyIcon(image, item.eggId, opts)
	end
	return EggVisual.clear(image)
end

return EggVisual

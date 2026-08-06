--!nonstrict

local Theme = {}

Theme.Color = {
	Window = Color3.fromRGB(255, 255, 255),
	WindowBorder = Color3.fromRGB(41, 182, 214),
	Overlay = Color3.fromRGB(12, 16, 26),

	Text = Color3.fromRGB(38, 44, 60),
	TextInverse = Color3.fromRGB(255, 255, 255),
	TextMuted = Color3.fromRGB(120, 132, 152),
	TextStroke = Color3.fromRGB(24, 28, 40),

	Blue = Color3.fromRGB(30, 136, 229),
	Cyan = Color3.fromRGB(41, 182, 214),
	Teal = Color3.fromRGB(22, 173, 148),
	Green = Color3.fromRGB(47, 177, 59),
	Yellow = Color3.fromRGB(255, 179, 0),
	Orange = Color3.fromRGB(255, 122, 24),
	Red = Color3.fromRGB(226, 59, 52),
	Pink = Color3.fromRGB(240, 71, 159),
	Purple = Color3.fromRGB(139, 63, 232),
	Gray = Color3.fromRGB(168, 178, 194),
	Dark = Color3.fromRGB(40, 45, 60),

	Success = Color3.fromRGB(47, 177, 59),
	Warning = Color3.fromRGB(255, 179, 0),
	Danger = Color3.fromRGB(226, 59, 52),

	Cash = Color3.fromRGB(255, 196, 40),
	Gem = Color3.fromRGB(88, 214, 255),
	Robux = Color3.fromRGB(64, 214, 120),
}

Theme.Palettes = {
	"blue", "cyan", "teal", "green", "yellow", "orange",
	"red", "pink", "purple", "gray", "white", "dark",
}

Theme.PaletteColor = {
	blue = Theme.Color.Blue,
	cyan = Theme.Color.Cyan,
	teal = Theme.Color.Teal,
	green = Theme.Color.Green,
	yellow = Theme.Color.Yellow,
	orange = Theme.Color.Orange,
	red = Theme.Color.Red,
	pink = Theme.Color.Pink,
	purple = Theme.Color.Purple,
	gray = Theme.Color.Gray,
	white = Color3.fromRGB(255, 255, 255),
	dark = Theme.Color.Dark,
}

Theme.PaletteTextColor = {
	white = Theme.Color.Text,
	gray = Theme.Color.Text,
	yellow = Color3.fromRGB(92, 58, 0),
}

Theme.Font = {
	Title = Enum.Font.FredokaOne,
	TitleIntl = Enum.Font.GothamBlack,
	Heading = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Number = Enum.Font.FredokaOne,
}

--[[
	글씨가 안 보이는 문제.

	FredokaOne 같은 장식체에는 한글 글리프가 없다. 그 폰트로 한국어를 쓰면
	글자가 통째로 사라지거나 네모로 나온다. 창 제목만 따로 바꿔 놨었는데,
	숫자 폰트(Number)로 찍는 곳이나 컨트롤러가 직접 지정한 곳은 그대로 깨졌다.

	그래서 "쓰고 싶은 폰트" 와 "이 언어에서 실제로 그려지는 폰트" 를 나눈다.
	화면에 붙일 때는 반드시 Theme.resolveFont 를 거친다 —
	UI.text 가 전부 이 함수를 통하므로 한 곳만 고치면 전부 고쳐진다.
]]
Theme.CjkLocales = {
	ko = true,
	ja = true,
	zh = true,
	th = true,
}

--[[
	표는 이름으로 적고, 실제 폰트는 찾아서 채운다.

	Enum.Font 의 구성은 로블록스 버전마다 다르다. 없는 이름을 그대로 쓰면
	`Enum.Font.XXX` 한 줄에서 이 모듈이 통째로 로드에 실패하고,
	Theme 를 require 하는 화면이 전부 같이 죽는다. 글씨 하나 바꾸자고
	게임을 못 켜게 만들 수는 없다.

	그래서 지금 이 클라이언트에 실제로 있는 폰트만 표에 넣는다.
	없는 이름은 조용히 건너뛴다.
]]
local FONT_BY_NAME = {}
for _, item in ipairs(Enum.Font:GetEnumItems()) do
	FONT_BY_NAME[item.Name] = item
end

--- { 바꿀 폰트, 대신 쓸 폰트 }
local FALLBACK_NAMES = {
	{ "FredokaOne", "GothamBlack" },
	{ "LuckiestGuy", "GothamBlack" },
	{ "Bangers", "GothamBlack" },
	{ "Creepster", "GothamBlack" },
	{ "Arcade", "GothamBlack" },
	{ "PermanentMarker", "GothamBlack" },
	{ "Cartoon", "GothamBold" },
	{ "Fantasy", "GothamBold" },
	{ "SciFi", "GothamBold" },
	{ "Michroma", "GothamBold" },
	{ "Sarpanch", "GothamBold" },
	{ "AmaticSC", "GothamBold" },
	{ "IndieFlower", "GothamBold" },
	{ "PatrickHand", "GothamBold" },
	{ "Antique", "Gotham" },
	{ "Bodoni", "Gotham" },
	{ "Garamond", "Gotham" },
	{ "Highway", "Gotham" },
	{ "Nunito", "Gotham" },
	{ "Oswald", "Gotham" },
	{ "Merriweather", "Gotham" },
	{ "JosefinSans", "Gotham" },
	{ "TitilliumWeb", "Gotham" },
	{ "SpecialElite", "Gotham" },
	{ "Jura", "Gotham" },
	{ "Kalam", "Gotham" },
	{ "Fondamento", "Gotham" },
	{ "DenkOne", "GothamBold" },
	{ "GrenzeGotisch", "GothamBold" },
	{ "Code", "RobotoMono" },
}

Theme.FontFallback = {}
for _, pair in ipairs(FALLBACK_NAMES) do
	local from = FONT_BY_NAME[pair[1]]
	local to = FONT_BY_NAME[pair[2]] or FONT_BY_NAME.GothamBold or Enum.Font.SourceSansBold
	if from then
		Theme.FontFallback[from] = to
	end
end

function Theme.resolveFont(font: Enum.Font?, localeCode: string?): Enum.Font
	if not font then
		return Theme.Font.Body
	end
	if not Theme.CjkLocales[localeCode] then
		return font
	end
	return Theme.FontFallback[font] or font
end

function Theme.titleFont(localeCode: string?): Enum.Font
	return Theme.resolveFont(Theme.Font.Title, localeCode)
end

Theme.Size = {
	CornerRadius = UDim.new(0, 14),
	CornerRadiusLarge = UDim.new(0, 22),
	StrokeThin = 2,
	StrokeThick = 4,
	Padding = 10,
	PaddingLarge = 18,

	MenuButton = Vector2.new(92, 92),
	HotbarSlot = Vector2.new(66, 66),
	HotbarSlotMobile = Vector2.new(54, 54),

	-- 화면 아래에서 핫바까지 띄우는 간격. 모바일은 조작 버튼을 피해야 한다.
	HotbarMargin = 10,
	HotbarMarginMobile = 96,
}

--- 핫바 윗변이 화면 아래에서 얼마나 떨어져 있는지
function Theme.hotbarTop(isMobile: boolean): number
	local slot = isMobile and Theme.Size.HotbarSlotMobile or Theme.Size.HotbarSlot
	local margin = isMobile and Theme.Size.HotbarMarginMobile or Theme.Size.HotbarMargin
	return margin + slot.Y + 8
end

Theme.Tween = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Pop = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	PopIn = TweenInfo.new(0.36, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0),
	Bounce = TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
}

Theme.PressScale = 0.94
Theme.HoverScale = 1.04

Theme.Sound = {
	Click = "rbxassetid://6042053626",
	Hover = "rbxassetid://6324790483",
	Open = "rbxassetid://6026984224",
	Close = "rbxassetid://6026984224",
	Success = "rbxassetid://6026984224",
	Error = "rbxassetid://550209561",
	Coin = "rbxassetid://607665037",
	Hatch = "rbxassetid://5766498482",
	Tick = "rbxassetid://6042053626",
	Siren = "rbxassetid://90249996359980",
	Music = "rbxassetid://1836057733",
}

Theme.Z = {
	Hud = 10,
	Hotbar = 20,
	Panel = 60,
	Modal = 100,
	Toast = 150,
	Alert = 200,
	Drag = 300,
}

return Theme

--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FOLDER_NAME = "RadRemotes"

Remotes.Definitions = {
	StateSync = { type = "Event", dir = "S2C" },
	Notify = { type = "Event", dir = "S2C" },
	CurrencyUpdate = { type = "Event", dir = "S2C" },
	InventorySync = { type = "Event", dir = "S2C" },
	BaseAssigned = { type = "Event", dir = "S2C" },

	SetSetting = {
		type = "Event", dir = "C2S", rate = 6,
		args = {
			{ t = "string", max = 32, pattern = "^[%a_]+$" },
			{ t = "any" },
		},
	},

	InventoryReorder = {
		type = "Event", dir = "C2S", rate = 8,
		args = {
			{ t = "table", maxCount = 200, of = { t = "string", max = 40, pattern = "^[%w_%-]+$" } },
		},
	},
	InventorySelect = {
		type = "Event", dir = "C2S", rate = 20,
		args = { { t = "number", int = true, min = 0, max = 200 } },
	},
	InventoryPlace = {
		type = "Function", dir = "C2S", rate = 4,
		args = {
			{ t = "string", max = 40, pattern = "^[%w_%-]+$" },
		},
	},

	HatchBegin = {
		type = "Function", dir = "C2S", rate = 3,
		args = {
			{ t = "Instance", class = "BasePart" },
		},
	},
	HatchTap = {
		type = "Event", dir = "C2S", rate = 25,
		args = {
			{ t = "string", max = 40 },
			{ t = "number", min = 0, max = 1e6 },
		},
	},
	HatchCancel = { type = "Event", dir = "C2S", rate = 4 },
	HatchFeedback = { type = "Event", dir = "S2C" },
	HatchResult = { type = "Event", dir = "S2C" },

	StealState = { type = "Event", dir = "S2C" },
	StealAlert = { type = "Event", dir = "S2C" },
	StealCancel = {
		type = "Event", dir = "C2S", rate = 4,
	},

	SellRequest = { type = "Event", dir = "S2C" },
	SellConfirm = {
		type = "Event", dir = "C2S", rate = 6,
		args = {
			{ t = "string", max = 40 },
			{ t = "boolean" },
		},
	},

	ShopBuy = {
		type = "Function", dir = "C2S", rate = 4,
		args = { { t = "string", max = 32, pattern = "^[%w_]+$" } },
	},
	EggOddsGet = {
		type = "Function", dir = "C2S", rate = 6,
		args = { { t = "string", max = 32, pattern = "^[%w_]+$" } },
	},
	RouletteGetState = { type = "Function", dir = "C2S", rate = 4 },
	RouletteSpin = { type = "Function", dir = "C2S", rate = 2 },
	RouletteSync = { type = "Event", dir = "S2C" },
	ShowSync = { type = "Event", dir = "S2C" },

	FloorSync = { type = "Event", dir = "S2C" },
	FloorGetState = { type = "Function", dir = "C2S", rate = 4 },

	WarmthSync = { type = "Event", dir = "S2C" },
	WarmthDrop = { type = "Event", dir = "S2C" },
	WarmthGetState = { type = "Function", dir = "C2S", rate = 4 },
	TutorialGetState = { type = "Function", dir = "C2S", rate = 4 },
	TutorialSkip = { type = "Function", dir = "C2S", rate = 2 },
	TutorialSync = { type = "Event", dir = "S2C" },
	BuyFeed = {
		type = "Function", dir = "C2S", rate = 6,
		args = {
			{ t = "string", max = 32, pattern = "^[%w_]+$" },
			{ t = "number", int = true, min = 1, max = 100 },
		},
	},
	FeedSync = { type = "Event", dir = "S2C" },
	WorldEvent = { type = "Event", dir = "S2C" },
	StockSync = { type = "Event", dir = "S2C" },
	EventFx = { type = "Event", dir = "S2C" },
	StockGet = { type = "Function", dir = "C2S", rate = 4 },
	StockRestock = { type = "Function", dir = "C2S", rate = 2 },

	FusionList = { type = "Function", dir = "C2S", rate = 6 },
	Fuse = {
		type = "Function", dir = "C2S", rate = 6,
		args = {
			{ t = "string", max = 32, pattern = "^[%w_]+$" },
			{ t = "string", max = 32, pattern = "^[%w_]+$" },
		},
	},
	NpcDialogue = {
		type = "Function", dir = "C2S", rate = 8,
		args = {
			{ t = "string", max = 32, pattern = "^[%w_]+$" },
			{ t = "string", max = 32, pattern = "^[%w_]+$", optional = true },
		},
	},

	GiftPrompt = {
		type = "Function", dir = "C2S", rate = 3,
		args = {
			{ t = "number", int = true, min = 1, max = 1e12 },
			{ t = "string", max = 40, pattern = "^[%w_]+$" },
		},
	},
	GiftSearch = {
		type = "Function", dir = "C2S", rate = 6,
		args = { { t = "string", max = 32 } },
	},
	GiftReceived = { type = "Event", dir = "S2C" },

	OfflineEarnings = { type = "Event", dir = "S2C" },
	OfflineClaim = { type = "Event", dir = "C2S", rate = 3 },

	CheaterShame = { type = "Event", dir = "S2C" },

	LockState = { type = "Event", dir = "S2C" },

	IndexSync = { type = "Event", dir = "S2C" },

	Rebirth = {
		type = "Function", dir = "C2S", rate = 4,
		args = { { t = "boolean", optional = true } },
	},

	AdminState = { type = "Event", dir = "S2C" },

	AdminLookup = {
		type = "Function", dir = "C2S", rate = 6,
		args = { { t = "string", max = 32, min = 1 } },
	},

	AdminCommand = {
		type = "Function", dir = "C2S", rate = 8,
		args = {
			{ t = "string", max = 32, pattern = "^[%a_]+$" },
			{
				t = "table", array = false, maxCount = 16,
			},
		},
	},

	AdminServerInfo = { type = "Function", dir = "C2S", rate = 6 },
}

local folder: Folder? = nil

function Remotes.build(): Folder
	assert(RunService:IsServer(), "Remotes.build() 는 서버에서만 호출합니다")
	local f = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not f then
		f = Instance.new("Folder")
		f.Name = FOLDER_NAME
		f.Parent = ReplicatedStorage
	end

	for name, def in pairs(Remotes.Definitions) do
		local className = def.type == "Function" and "RemoteFunction" or "RemoteEvent"
		local existing = f:FindFirstChild(name)
		if existing and not existing:IsA(className) then
			existing:Destroy()
			existing = nil
		end
		if not existing then
			local r = Instance.new(className)
			r.Name = name
			r.Parent = f
		end
	end

	folder = f
	return f
end

function Remotes.folder(): Folder
	if folder and folder.Parent then
		return folder
	end
	if RunService:IsServer() then
		return Remotes.build()
	end
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 30)
	assert(folder, "[Remotes] 리모트 폴더를 찾지 못했습니다.")
	return folder
end

function Remotes.get(name: string)
	local def = Remotes.Definitions[name]
	assert(def, ("[Remotes] 정의되지 않은 리모트: %q"):format(tostring(name)))
	local r = Remotes.folder():WaitForChild(name, 20)
	assert(r, ("[Remotes] 리모트 인스턴스 없음: %q"):format(name))
	return r
end

return Remotes

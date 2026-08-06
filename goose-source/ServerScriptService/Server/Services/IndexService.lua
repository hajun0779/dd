--!nonstrict

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local EggConfig = require(Shared.Config.EggConfig)
local GooseConfig = require(Shared.Config.GooseConfig)
local Signal = require(Shared.Util.Signal)
local NetServer = require(Shared.Net.NetServer)

local DataService = require(script.Parent.DataService)

local IndexService = {}

--[[
	새로 발견했을 때 알린다. (player, 총 발견 수)

	2층 해금이 이 신호를 듣는다. 도감이 늘어나는 순간을 아는 곳은 여기뿐이라,
	여기서 알려 주지 않으면 다른 서비스가 매 초 세어 보는 수밖에 없다.
]]
IndexService.Discovered = Signal.new()

local function ensure(profile)
	local data = profile.data
	if type(data.index) ~= "table" then
		data.index = {}
	end
	if type(data.index.geese) ~= "table" then
		data.index.geese = {}
	end
	if type(data.index.eggs) ~= "table" then
		data.index.eggs = {}
	end
	return data.index
end

local function countBucket(bucket): number
	local count = 0
	for _ in pairs(bucket or {}) do
		count += 1
	end
	return count
end

--[[
	지금까지 발견한 총 개수. 거위와 알을 함께 센다.

	도감 퀘스트와 2층 해금이 같은 수를 봐야 한다.
	둘이 따로 세면 화면에는 30/30 인데 2층은 안 열리는 일이 생긴다.
]]
function IndexService.discoveredCount(player: Player): number
	local profile = DataService.get(player)
	if not profile then
		return 0
	end
	local index = ensure(profile)
	return countBucket(index.geese) + countBucket(index.eggs)
end

--- 도감에 있을 수 있는 총 개수
function IndexService.totalCount(): number
	local total = 0
	for _ in pairs(GooseConfig.Data or {}) do
		total += 1
	end
	for _ in pairs(EggConfig.Data or {}) do
		total += 1
	end
	return total
end

function IndexService.sync(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local index = ensure(profile)

	NetServer.fire(player, "IndexSync", {
		geese = index.geese,
		eggs = index.eggs,
		found = IndexService.discoveredCount(player),
		total = IndexService.totalCount(),
	})
end

local function record(player: Player, category: string, id: string, meta): boolean
	if type(id) ~= "string" or id == "" then
		return false
	end
	local profile = DataService.get(player)
	if not profile then
		return false
	end

	local index = ensure(profile)
	local bucket = index[category]
	if not bucket then
		return false
	end

	local entry = bucket[id]
	local isNew = entry == nil

	if isNew then
		entry = { count = 0, first = os.time() }
		bucket[id] = entry
	end
	entry.count = (entry.count or 0) + 1

	if meta then
		if meta.rarity then
			entry.rarity = meta.rarity
		end
		if meta.variant and meta.variant ~= "Normal" then
			entry.variants = entry.variants or {}
			entry.variants[meta.variant] = true
		end
	end

	profile.dirty = true
	DataService.saveSoon(player, 2)
	IndexService.sync(player)

	if isNew then
		IndexService.Discovered:Fire(player, IndexService.discoveredCount(player))
	end

	return isNew
end

function IndexService.recordGoose(player: Player, gooseId: string, meta): boolean
	if not GooseConfig.get(gooseId) then
		return false
	end
	return record(player, "geese", gooseId, meta)
end

function IndexService.recordEgg(player: Player, eggId: string): boolean
	if not EggConfig.get(eggId) then
		return false
	end
	return record(player, "eggs", eggId, nil)
end

function IndexService.start()
	DataService.ProfileLoaded:Connect(function(player)
		task.defer(IndexService.sync, player)
	end)
end

return IndexService

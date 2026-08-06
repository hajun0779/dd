--!nonstrict

local AdminConfig = {}

AdminConfig.Order = {
	"inspect",
	"give_cash",
	"set_cash",
	"give_gems",
	"give_egg",
	"grant_pass",
	"clear_inventory",
	"reset_data",
	"unlock_base",
	"bring",
	"goto",
	"freeze",
	"kick",
	"ban",
	"unban",
	"announce",
	"show",
	"show_stop",
	"ball_event",
	"floor_two",
	"anticheat_dryrun",
	"shutdown",
}

AdminConfig.Commands = {
	inspect = {
		id = "inspect",
		localeKey = "admin_cmd_inspect",
		descKey = "admin_cmd_inspect_desc",
		icon = "icon_search",
		palette = "cyan",
		scope = "user",
		danger = false,
		skipConfirm = true,
	},

	give_cash = {
		id = "give_cash",
		localeKey = "admin_cmd_give_cash",
		descKey = "admin_cmd_give_cash_desc",
		icon = "icon_money",
		palette = "green",
		scope = "user",
		params = {
			{ id = "amount", type = "number", localeKey = "admin_param_amount", min = -1e12, max = 1e12, default = 10000 },
		},
	},

	set_cash = {
		id = "set_cash",
		localeKey = "admin_cmd_set_cash",
		descKey = "admin_cmd_set_cash_desc",
		icon = "icon_money",
		palette = "green",
		scope = "user",
		params = {
			{ id = "amount", type = "number", localeKey = "admin_param_amount", min = 0, max = 1e12, default = 0 },
		},
	},

	give_gems = {
		id = "give_gems",
		localeKey = "admin_cmd_give_gems",
		descKey = "admin_cmd_give_gems_desc",
		icon = "icon_gem",
		palette = "cyan",
		scope = "user",
		params = {
			{ id = "amount", type = "number", localeKey = "admin_param_amount", min = -1e9, max = 1e9, default = 100 },
		},
	},

	give_egg = {
		id = "give_egg",
		localeKey = "admin_cmd_give_egg",
		descKey = "admin_cmd_give_egg_desc",
		icon = "icon_egg",
		palette = "yellow",
		scope = "user",
		params = {
			{ id = "eggId", type = "string", localeKey = "admin_param_egg", max = 32, default = "Basic" },
			{ id = "count", type = "number", localeKey = "admin_param_count", min = 1, max = 20, default = 1 },
		},
	},

	grant_pass = {
		id = "grant_pass",
		localeKey = "admin_cmd_grant_pass",
		descKey = "admin_cmd_grant_pass_desc",
		icon = "icon_gift",
		palette = "pink",
		scope = "user",
		params = {
			{ id = "key", type = "string", localeKey = "admin_param_pass", max = 40, default = "VIP" },
		},
	},

	clear_inventory = {
		id = "clear_inventory",
		localeKey = "admin_cmd_clear_inventory",
		descKey = "admin_cmd_clear_inventory_desc",
		icon = "icon_trash",
		palette = "orange",
		scope = "user",
		danger = true,
	},

	reset_data = {
		id = "reset_data",
		localeKey = "admin_cmd_reset_data",
		descKey = "admin_cmd_reset_data_desc",
		icon = "icon_refresh",
		palette = "red",
		scope = "user",
		danger = true,
	},

	unlock_base = {
		id = "unlock_base",
		localeKey = "admin_cmd_unlock_base",
		descKey = "admin_cmd_unlock_base_desc",
		icon = "icon_unlock",
		palette = "blue",
		scope = "user",
		params = {
			{ id = "locked", type = "boolean", localeKey = "admin_param_locked", default = false },
		},
	},

	bring = {
		id = "bring",
		localeKey = "admin_cmd_bring",
		descKey = "admin_cmd_bring_desc",
		icon = "icon_arrow_d",
		palette = "purple",
		scope = "user",
		sameServerOnly = true,
	},

	goto = {
		id = "goto",
		localeKey = "admin_cmd_goto",
		descKey = "admin_cmd_goto_desc",
		icon = "icon_arrow_r",
		palette = "purple",
		scope = "user",
		sameServerOnly = true,
	},

	freeze = {
		id = "freeze",
		localeKey = "admin_cmd_freeze",
		descKey = "admin_cmd_freeze_desc",
		icon = "icon_snow",
		palette = "cyan",
		scope = "user",
		sameServerOnly = true,
		params = {
			{ id = "frozen", type = "boolean", localeKey = "admin_param_frozen", default = true },
		},
	},

	kick = {
		id = "kick",
		localeKey = "admin_cmd_kick",
		descKey = "admin_cmd_kick_desc",
		icon = "icon_door",
		palette = "orange",
		scope = "user",
		danger = true,
		params = {
			{ id = "reason", type = "string", localeKey = "admin_param_reason", max = 120, default = "" },
		},
	},

	ban = {
		id = "ban",
		localeKey = "admin_cmd_ban",
		descKey = "admin_cmd_ban_desc",
		icon = "icon_warning",
		palette = "red",
		scope = "user",
		danger = true,
		params = {
			{ id = "reason", type = "string", localeKey = "admin_param_reason", max = 120, default = "" },
			{ id = "days", type = "number", localeKey = "admin_param_days", min = -1, max = 3650, default = -1 },
			{ id = "alts", type = "boolean", localeKey = "admin_param_alts", default = true },
			{ id = "shame", type = "boolean", localeKey = "admin_param_shame", default = false },
		},
	},

	announce = {
		id = "announce",
		localeKey = "admin_cmd_announce",
		descKey = "admin_cmd_announce_desc",
		icon = "icon_sound",
		palette = "yellow",
		scope = "server",
		params = {
			{ id = "message", type = "string", localeKey = "admin_param_message", max = 200, default = "" },
		},
	},

	anticheat_dryrun = {
		id = "anticheat_dryrun",
		localeKey = "admin_cmd_anticheat",
		descKey = "admin_cmd_anticheat_desc",
		icon = "icon_bolt",
		palette = "orange",
		scope = "server",
		params = {
			{ id = "dryRun", type = "boolean", localeKey = "admin_param_dryrun", default = true },
		},
	},

	unban = {
		id = "unban",
		localeKey = "admin_cmd_unban",
		descKey = "admin_cmd_unban_desc",
		icon = "icon_unlock",
		palette = "green",
		scope = "user",
		--- 밴된 사람은 접속해 있을 수 없다
		allowOffline = true,
		params = {},
	},

	--[[
		연출.

		showId 에 ShowConfig 의 Id 를 적는다. 대소문자는 가리지 않는다.
		  Aurora  Storm  Meteor  Sakura  Disco
		  Frost   Rift   GoldRain  Nebula  Taco

		seconds 를 0 으로 두면 그 연출에 정해진 길이를 쓴다.
	]]
	show = {
		id = "show",
		localeKey = "admin_cmd_show",
		descKey = "admin_cmd_show_desc",
		icon = "icon_star",
		palette = "purple",
		scope = "server",
		params = {
			{ id = "showId", type = "string", localeKey = "admin_param_show", max = 24, default = "Aurora" },
			{ id = "seconds", type = "number", localeKey = "admin_param_seconds", min = 0, max = 900, default = 0 },
		},
	},

	show_stop = {
		id = "show_stop",
		localeKey = "admin_cmd_show_stop",
		descKey = "admin_cmd_show_stop_desc",
		icon = "icon_close",
		palette = "gray",
		scope = "server",
		skipConfirm = true,
		params = {},
	},

	floor_two = {
		id = "floor_two",
		localeKey = "admin_cmd_floor_two",
		descKey = "admin_cmd_floor_two_desc",
		icon = "icon_home",
		palette = "teal",
		scope = "user",
		sameServerOnly = true,
		params = {
			{ id = "unlocked", type = "boolean", localeKey = "admin_param_unlocked", default = true },
		},
	},

	ball_event = {
		id = "ball_event",
		localeKey = "admin_cmd_ball_event",
		descKey = "admin_cmd_ball_event_desc",
		icon = "icon_fire",
		palette = "orange",
		scope = "server",
		params = {},
	},

	shutdown = {
		id = "shutdown",
		localeKey = "admin_cmd_shutdown",
		descKey = "admin_cmd_shutdown_desc",
		icon = "icon_close",
		palette = "red",
		scope = "server",
		danger = true,
		params = {
			{ id = "seconds", type = "number", localeKey = "admin_param_delay", min = 0, max = 300, default = 15 },
		},
	},
}

local ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

function AdminConfig.serverCode(jobId: string?): string
	jobId = jobId or game.JobId
	if not jobId or jobId == "" then
		return "STUD-IO00"
	end

	local h1, h2 = 5381, 52711
	for i = 1, #jobId do
		local b = string.byte(jobId, i)
		h1 = (h1 * 33 + b) % 4294967296
		h2 = (h2 * 31 + b * (i % 7 + 1)) % 4294967296
	end

	local function encode(value: number, length: number): string
		local out = {}
		local n = #ALPHABET
		for _ = 1, length do
			local index = (value % n) + 1
			table.insert(out, string.sub(ALPHABET, index, index))
			value = math.floor(value / n)
		end
		return table.concat(out)
	end

	return encode(h1, 4) .. "-" .. encode(h2, 4)
end

function AdminConfig.normalizeCode(input: string): string?
	if type(input) ~= "string" then
		return nil
	end
	local cleaned = string.upper(input):gsub("[^%w]", "")
	if #cleaned ~= 8 then
		return nil
	end
	for i = 1, 8 do
		local char = string.sub(cleaned, i, i)
		if not string.find(ALPHABET, char, 1, true) then
			return nil
		end
	end
	return string.sub(cleaned, 1, 4) .. "-" .. string.sub(cleaned, 5, 8)
end

function AdminConfig.get(commandId: string)
	return AdminConfig.Commands[commandId]
end

return AdminConfig

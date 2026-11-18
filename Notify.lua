-- Whack: notifications (loot, money, currency, skill-ups, reputation, XP, honour, level up, quest progress,
-- bags full) as floating text in their own area.
--
-- Chat messages are read with the game's own format strings (LOOT_ITEM_SELF and friends), so this works in
-- every language. A message, an amount or a GUID may be a secret value (in instances on this client): we
-- never do maths, comparisons or string work on those. A secret loot message is shown as it is only when a
-- readable GUID says it is yours; any other secret is shown raw or dropped, never parsed.
local _, ns = ...
local N = {}
ns.Notify = N

local AREA = "notify"
local MERGE = 1.0     -- the same item (or faction, or coin) within this many seconds joins the line on screen
local GAP = 0.15      -- at most one new line per GAP seconds, so a mass loot scrolls instead of piling up
local MAX_QUEUE = 8   -- waiting lines; more are counted into one "+N more" line
local BAGS_QUIET = 4  -- "Inventory is full" at most this often

local function readable(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end
local function str(v) if readable(v) and type(v) == "string" then return v end end
local function num(v) if readable(v) and type(v) == "number" then return v end end
N.readable = readable

local COLORS = {
	count  = { 0.80, 0.80, 0.80 },
	skill  = { 0.45, 0.70, 1.00 },
	repUp  = { 0.50, 0.85, 0.65 },
	repDown = { 0.95, 0.45, 0.40 },
	xp     = { 0.75, 0.60, 1.00 },
	honor  = { 0.95, 0.75, 0.35 },
	level  = { 1.00, 0.82, 0.00 },
	quest  = { 0.95, 0.90, 0.60 },
	bags   = { 1.00, 0.40, 0.35 },
	more   = { 0.60, 0.60, 0.60 },
	white  = { 1, 1, 1 },
}
N.COLORS = COLORS

local function hexOf(c)
	return ("|cff%02x%02x%02x"):format(c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5)
end
local COUNT_HEX = hexOf(COLORS.count)

------------------------------------------------------------------------
-- Format strings -> patterns
------------------------------------------------------------------------
-- "You receive loot: %sx%d." -> "^You receive loot: (.+)x(%-?%d+)%.$". Handles %s, %d, %.1f and positional
-- %2$s. Returns the pattern and the argument number of each capture.
function N.ToPattern(fmt)
	local out, order, i, n = { "^" }, {}, 1, 0
	while i <= #fmt do
		local c = fmt:sub(i, i)
		if c == "%" then
			local s, e, pos, conv = fmt:find("^%%(%d?)%$?[%-%d%.]*([sdfi])", i)
			if s then
				n = n + 1
				order[#order + 1] = tonumber(pos ~= "" and pos or nil) or n
				out[#out + 1] = conv == "s" and "(.+)" or conv == "f" and "(%-?[%d%.]+)" or "(%-?%d+)"
				i = e + 1
			elseif fmt:sub(i + 1, i + 1) == "%" then
				out[#out + 1] = "%%"
				i = i + 2
			else
				out[#out + 1] = "%%"
				i = i + 1
			end
		else
			out[#out + 1] = c:find("[%(%)%.%+%-%*%?%[%]%^%$]") and ("%" .. c) or c
			i = i + 1
		end
	end
	out[#out + 1] = "$"
	return table.concat(out), order
end

-- Match msg against the named global format strings (tried in the order given). Returns the name of the one
-- that matched and its arguments in format order.
local cache = {}
function N.Match(msg, names)
	for _, name in ipairs(names) do
		local fmt = _G[name]
		if type(fmt) == "string" and fmt ~= "" then
			local p = cache[name]
			if not p or p.fmt ~= fmt then
				local pat, order = N.ToPattern(fmt)
				p = { fmt = fmt, pat = pat, order = order }
				cache[name] = p
			end
			local caps = { msg:match(p.pat) }
			if caps[1] ~= nil then
				if #p.order == 0 then return name, {} end -- no arguments: the whole message matched
				local args = {}
				for k, v in ipairs(caps) do args[p.order[k]] = v end
				return name, args
			end
		end
	end
end

-- MULTIPLE first: "%s." would otherwise swallow "Linen Clothx5."
N.LOOT_FORMATS = {
	"LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF_MULTIPLE",
	"LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "LOOT_ITEM_REFUND_MULTIPLE",
	"LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_BONUS_ROLL_SELF", "LOOT_ITEM_REFUND",
}
N.CURRENCY_FORMATS = { "CURRENCY_GAINED_MULTIPLE_BONUS", "CURRENCY_GAINED_MULTIPLE", "CURRENCY_GAINED" }
N.SKILL_FORMATS = { "SKILL_RANK_UP" }
N.REP_UP = { "FACTION_STANDING_INCREASED_DOUBLE_BONUS", "FACTION_STANDING_INCREASED_ACH_BONUS",
	"FACTION_STANDING_INCREASED_BONUS", "FACTION_STANDING_INCREASED", "FACTION_STANDING_INCREASED_GENERIC" }
N.REP_DOWN = { "FACTION_STANDING_DECREASED", "FACTION_STANDING_DECREASED_GENERIC" }
N.HONOR_FORMATS = { "COMBATLOG_HONORAWARD", "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK", "COMBATLOG_HONORGAIN_EXHAUSTION1" }
N.QUEST_FORMATS = { "ERR_QUEST_ADD_KILL_SII", "ERR_QUEST_ADD_FOUND_SII", "ERR_QUEST_ADD_PLAYER_KILL_SII",
	"ERR_QUEST_ADD_ITEM_SII", "ERR_QUEST_OBJECTIVE_COMPLETE_S", "ERR_QUEST_UNKNOWN_COMPLETE" }

------------------------------------------------------------------------
-- Items and money
------------------------------------------------------------------------
local QUALITY_FALLBACK = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000", "|cffe6cc80", "|cff00ccff" }

local function QualityHex(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if c and c.hex then return c.hex end
	return QUALITY_FALLBACK[q] or "|cffffffff"
end

local function ItemInfo(link)
	local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not fn then return end
	local ok, name, _, quality, _, _, _, _, _, _, icon = pcall(fn, link)
	if ok then return name, quality, icon end
end

-- What an item link says: { name, quality, icon, id, color } (any of them may be missing).
function N.ParseItem(link)
	local it = { link = link }
	it.id = tonumber(link:match("item:(%d+)"))
	it.name = link:match("|h%[(.-)%]|h") or link:match("%[(.-)%]")
	local name, quality, icon = ItemInfo(link)
	it.name = it.name or name
	it.quality = num(quality)
	it.icon = icon
	if it.id and not it.icon then
		local fn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
		if fn then
			local ok, tex = pcall(fn, it.id)
			if ok then it.icon = tex end
		end
	end
	-- the link's own colour: "|cff1eff00" or the newer "|cnIQ2:"
	it.color = link:match("^(|c%x%x%x%x%x%x%x%x)") or link:match("^(|cn[^:|]+:)")
	if not it.quality then
		local q = link:match("^|cnIQ(%d+):")
		if q then
			it.quality = tonumber(q)
		elseif it.color then
			local hex = it.color:lower()
			for i = 0, 8 do
				if QualityHex(i):lower() == hex then it.quality = i break end
			end
		end
	end
	if not it.color and it.quality then it.color = QualityHex(it.quality) end
	return it
end

local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
local COINS = { ("Gold"), ("Silver"), ("Copper") }

-- 12345 copper -> "1 [gold] 23 [silver] 45 [copper]" with the game's coin icons; zero parts are left out.
function N.FormatMoney(copper)
	copper = math.floor(copper)
	local g = math.floor(copper / 10000)
	local s = math.floor(copper / 100) % 100
	local c = copper % 100
	local parts = {}
	for i, v in ipairs({ g, s, c }) do
		if v > 0 or (i == 3 and #parts == 0) then
			local n = (i == 1 and BreakUpLargeNumbers) and BreakUpLargeNumbers(v) or tostring(v)
			parts[#parts + 1] = n .. COIN:format(COINS[i])
		end
	end
	return table.concat(parts, " ")
end

local function Plain(n)
	if BreakUpLargeNumbers then
		local ok, s = pcall(BreakUpLargeNumbers, n)
		if ok and s then return s end
	end
	return tostring(n)
end

------------------------------------------------------------------------
-- The queue: merging and throttling
------------------------------------------------------------------------
-- An entry: { key = merge key or nil, amount = number, merge = "sum" | "last", render = fn(amount) -> text,
--             icon, color, crit, raw = a secret message to show as it is }
local queue, dropped, pumping, lastSpawn = {}, 0, false, -1e9
N.queue = queue

local function db() return ns.db and ns.db.notify end
local function areaOn() return ns.db and ns.db.areas[AREA] and ns.db.areas[AREA].enabled end

local function Combine(into, e)
	if e.merge == "sum" then into.amount = into.amount + e.amount else into.amount = e.amount end
	into.render = e.render or into.render
end

local function Show(e)
	local spec = { icon = e.icon, color = e.color or COLORS.white, crit = e.crit, mergeKey = e.key }
	if e.raw ~= nil then spec.raw = e.raw else spec.text = e.render(e.amount) end
	local t = ns.Display:Spawn(AREA, spec)
	if t then
		t.entry = e
		t.mergeTime = GetTime()
	end
	lastSpawn = GetTime()
	return t
end

function N.Pump()
	pumping = false
	local now = GetTime()
	if now - lastSpawn >= GAP - 1e-6 then
		if #queue > 0 then
			Show(table.remove(queue, 1))
		elseif dropped > 0 then
			local n = dropped
			dropped = 0
			Show({ amount = n, color = COLORS.more, render = function(v) return ("+%d more"):format(v) end })
		end
	end
	if (#queue > 0 or dropped > 0) and not pumping then
		pumping = true
		C_Timer.After(GAP, N.Pump)
	end
end

function N:Push(e)
	if not areaOn() then return end
	e.amount = e.amount or 0
	if e.key then
		for _, q in ipairs(queue) do
			if q.key == e.key then Combine(q, e) return end
		end
		local t = ns.Display:FindMerge(AREA, e.key)
		if t and t.entry and GetTime() - (t.mergeTime or 0) <= MERGE then
			Combine(t.entry, e)
			t.mergeTime = GetTime()
			ns.Display:Retext(t, t.entry.render(t.entry.amount))
			return
		end
	end
	if #queue >= MAX_QUEUE then
		dropped = dropped + 1
	else
		queue[#queue + 1] = e
	end
	N.Pump()
end

function N:Clear()
	wipe(queue)
	dropped = 0
end

------------------------------------------------------------------------
-- Readers: one per kind of message
------------------------------------------------------------------------
local function LootText(it)
	local name = it.name or "?"
	return function(count)
		local s = (it.color or "|cffffffff") .. name .. "|r"
		if count > 1 then s = s .. COUNT_HEX .. " \195\151" .. count .. "|r" end -- ×
		return s
	end
end

-- link, count -> an entry, or nil when filtered out
function N:LootEntry(link, count)
	local o = db()
	local it = N.ParseItem(link)
	if it.quality and it.quality < (o.quality or 0) then return end
	return { key = "item:" .. (it.id or it.name or link), amount = count or 1, merge = "sum", icon = it.icon, render = LootText(it) }
end

function N:OnLoot(msg, guid)
	local o = db()
	if not o.loot then return end
	if not readable(msg) then
		-- secret: we cannot tell whose loot it is from the text. Show it as it is only when the GUID says it is ours.
		local me = UnitGUID and UnitGUID("player")
		if readable(guid) and readable(me) and guid == me then self:Push({ raw = msg }) end
		return
	end
	if type(msg) ~= "string" then return end
	local _, args = N.Match(msg, N.LOOT_FORMATS)
	if not args then return end -- someone else's, or a roll message
	local e = self:LootEntry(args[1], tonumber(args[2]) or 1)
	if e then self:Push(e) end
end

function N:OnCurrency(msg)
	local o = db()
	if not o.currency then return end
	if not readable(msg) then self:Push({ raw = msg }) return end
	local _, args = N.Match(msg, N.CURRENCY_FORMATS)
	if not args then return end
	local link = args[1]
	local id = tonumber(link:match("currency:(%d+)"))
	local name = link:match("%[(.-)%]") or link
	local color = link:match("^(|c%x%x%x%x%x%x%x%x)") or link:match("^(|cn[^:|]+:)") or "|cffffffff"
	local icon
	if id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
		local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
		if ok and type(info) == "table" then icon = info.iconFileID end
	end
	self:Push({ key = "currency:" .. (id or name), amount = tonumber(args[2]) or 1, merge = "sum", icon = icon,
		render = function(n) return color .. name .. "|r" .. (n > 1 and (COUNT_HEX .. " \195\151" .. n .. "|r") or "") end })
end

function N:OnSkill(msg)
	if not db().skill then return end
	if not readable(msg) then self:Push({ raw = msg, color = COLORS.skill }) return end
	local _, args = N.Match(msg, N.SKILL_FORMATS)
	if not args then return end
	local skill, rank = args[1], tonumber(args[2])
	if not rank then return end
	self:Push({ key = "skill:" .. skill, amount = rank, merge = "last", color = COLORS.skill,
		render = function(n) return skill .. " " .. n end })
end

function N:OnFaction(msg)
	if not db().rep then return end
	if not readable(msg) then self:Push({ raw = msg, color = COLORS.repUp }) return end
	local up = true
	local _, args = N.Match(msg, N.REP_UP)
	if not args then
		up = false
		_, args = N.Match(msg, N.REP_DOWN)
	end
	if not args then return end
	local faction, amount = args[1], tonumber(args[2])
	if not amount then -- the _GENERIC form names no amount
		self:Push({ color = up and COLORS.repUp or COLORS.repDown, render = function() return (up and "+ " or "- ") .. faction end })
		return
	end
	local sign = up and 1 or -1
	self:Push({ key = "rep:" .. faction, amount = sign * amount, merge = "sum", color = up and COLORS.repUp or COLORS.repDown,
		render = function(n) return (n >= 0 and "+" or "") .. Plain(n) .. " " .. faction end })
end

function N:OnHonor(msg)
	if not db().honor then return end
	if not readable(msg) then self:Push({ raw = msg, color = COLORS.honor }) return end
	local _, args = N.Match(msg, N.HONOR_FORMATS)
	local amount = args and tonumber(args[#args])
	if not amount then return end
	local label = HONOR or "Honor"
	self:Push({ key = "honor", amount = amount, merge = "sum", color = COLORS.honor,
		render = function(n) return "+" .. Plain(n) .. " " .. label end })
end

function N:XPGained(amount)
	if not db().xp or amount <= 0 then return end
	local label = XP or "XP"
	self:Push({ key = "xp", amount = amount, merge = "sum", color = COLORS.xp,
		render = function(n) return "+" .. Plain(n) .. " " .. label end })
end

function N:MoneyGained(copper)
	if not db().money or copper <= 0 then return end
	self:Push({ key = "money", amount = copper, merge = "sum", render = N.FormatMoney })
end

function N:OnLevel(level)
	if not db().level then return end
	level = num(level)
	if not level then return end
	local fmt = LEVEL_GAINED or "Level %d"
	self:Push({ color = COLORS.level, crit = true, render = function() return fmt:format(level) end })
end

function N:OnInfo(msg)
	if not db().quest or not readable(msg) or type(msg) ~= "string" then return end
	local which, args = N.Match(msg, N.QUEST_FORMATS)
	if not which then return end
	-- "Turtle Meat: 3/10" followed by "Turtle Meat: 4/10" updates the same line
	local key = "quest:" .. tostring(args[1] or msg)
	self:Push({ key = key, amount = 0, merge = "last", color = COLORS.quest, render = function() return msg end })
end

local bagsAt = -1e9
function N:OnError(msg)
	if not db().bagsFull or not readable(msg) then return end
	if msg ~= ERR_INV_FULL and msg ~= ERR_BAG_FULL then return end
	local now = GetTime()
	if now - bagsAt < BAGS_QUIET then return end
	bagsAt = now
	self:Push({ color = COLORS.bags, render = function() return msg end })
end

------------------------------------------------------------------------
-- Money and XP from their totals (the change since last time; nothing when a total is secret)
------------------------------------------------------------------------
local last = {}
N.last = last

function N:ReadMoney()
	local m = num(GetMoney and GetMoney())
	if m and last.money then self:MoneyGained(m - last.money) end
	last.money = m
end

function N:ReadXP()
	local xp = num(UnitXP and UnitXP("player"))
	local max = num(UnitXPMax and UnitXPMax("player"))
	local lvl = num(UnitLevel and UnitLevel("player"))
	if xp and lvl and last.xp and last.level then
		local gain
		if lvl == last.level then
			gain = xp - last.xp
		elseif lvl == last.level + 1 and last.max then
			gain = last.max - last.xp + xp
		end
		if gain then self:XPGained(gain) end
	end
	last.xp, last.max, last.level = xp, max, lvl
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
N.eventFrame = ev
N.seen = { loot = 0, secret = 0 }

local function Register(e)
	if C_EventUtils and C_EventUtils.IsEventValid then
		local ok, valid = pcall(C_EventUtils.IsEventValid, e)
		if ok and valid == false then return false end
	end
	return (pcall(ev.RegisterEvent, ev, e))
end

function N:Init()
	for _, e in ipairs({ "CHAT_MSG_LOOT", "CHAT_MSG_SKILL", "CHAT_MSG_COMBAT_FACTION_CHANGE", "PLAYER_MONEY",
		"PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE", "PLAYER_ENTERING_WORLD" }) do
		Register(e)
	end
	N.hasCurrency = Register("CHAT_MSG_CURRENCY")
	N.hasHonor = Register("CHAT_MSG_COMBAT_HONOR_GAIN")
	self:ReadMoney()
	self:ReadXP()
end

local function guarded(fn, ...)
	local ok, err = pcall(fn, N, ...)
	if not ok and geterrorhandler then geterrorhandler()(err) end
end

ev:SetScript("OnEvent", function(_, event, a1, a2, _, _, _, _, _, _, _, _, _, a12)
	if a1 ~= nil and not readable(a1) then N.seen.secret = N.seen.secret + 1 end
	if event == "PLAYER_MONEY" then return guarded(N.ReadMoney) end
	if event == "PLAYER_XP_UPDATE" then return guarded(N.ReadXP) end
	if event == "PLAYER_ENTERING_WORLD" then
		last.money = nil; last.xp = nil
		guarded(N.ReadMoney); guarded(N.ReadXP)
		return
	end
	if not areaOn() then return end
	if event == "CHAT_MSG_LOOT" then
		N.seen.loot = N.seen.loot + 1
		guarded(N.OnLoot, a1, a12)
	elseif event == "CHAT_MSG_CURRENCY" then guarded(N.OnCurrency, a1)
	elseif event == "CHAT_MSG_SKILL" then guarded(N.OnSkill, a1)
	elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then guarded(N.OnFaction, a1)
	elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then guarded(N.OnHonor, a1)
	elseif event == "PLAYER_LEVEL_UP" then guarded(N.OnLevel, a1)
	elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" then
		-- (messageType, message) on this client; (message) on older ones
		local msg = a2
		if msg == nil then msg = a1 end
		guarded(event == "UI_INFO_MESSAGE" and N.OnInfo or N.OnError, msg)
	end
end)

------------------------------------------------------------------------
-- Test
------------------------------------------------------------------------
local TEST = {
	function() return N:LootEntry("|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r", 3) end,
	function() return { key = "money", amount = 1234, merge = "sum", render = N.FormatMoney } end,
	function() return { key = "skill:test", amount = 112, merge = "last", color = COLORS.skill, render = function(n) return "Mining " .. n end } end,
	function() return N:LootEntry("|cff1eff00|Hitem:6070::::::::|h[Wolfskin Bracers]|h|r", 1) end,
	function() return { key = "rep:test", amount = 25, merge = "sum", color = COLORS.repUp, render = function(n) return "+" .. n .. " Stormwind" end } end,
	function() return { key = "xp", amount = 340, merge = "sum", color = COLORS.xp, render = function(n) return "+" .. n .. " " .. (XP or "XP") end } end,
	function() return { key = "quest:test", amount = 0, merge = "last", color = COLORS.quest, render = function() return "Turtle Meat: 3/10" end } end,
}

function N:Test()
	if not areaOn() then
		ns:Print("Notifications are off: /whack notify on (or tick Show notifications).")
		return
	end
	local saved = ns.db.notify.quality
	ns.db.notify.quality = 0
	for _, f in ipairs(TEST) do
		local e = f()
		if e then e.key = e.key and ("test:" .. e.key); self:Push(e) end
	end
	ns.db.notify.quality = saved
end

function N:Status()
	local on = areaOn()
	local o = db()
	local kinds = {}
	for _, k in ipairs({ "loot", "money", "currency", "skill", "rep", "xp", "honor", "level", "quest", "bagsFull" }) do
		if o[k] then kinds[#kinds + 1] = k end
	end
	ns:Print(("notifications %s (%s); loot messages seen %d, secret messages %d, on screen %d"):format(
		on and "on" or "off", #kinds > 0 and table.concat(kinds, ", ") or "nothing ticked",
		N.seen.loot, N.seen.secret, ns.Display:ActiveCount(AREA)))
end

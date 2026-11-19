-- Whack: settings window (/whack), slash settings and the Settings > AddOns entry, on EverlookUI.
-- Every option is defined once below; the window and "/whack <setting> <value>" both use it.
local ADDON, ns = ...
local UI = ns.UI
local O = {}
ns.Options = O

local STYLES = {
	{ value = "scroll",  text = "Scroll - glide in one direction" },
	{ value = "arc",     text = "Arc - fountain out to the sides" },
	{ value = "cascade", text = "Cascade - new line pushes the others" },
	{ value = "burst",   text = "Burst - pop up in place" },
}
local DIRECTIONS = { { value = "up", text = "Upwards" }, { value = "down", text = "Downwards" } }
local ALIGNS = { { value = "left", text = "Left" }, { value = "center", text = "Center" }, { value = "right", text = "Right" } }
local OUTLINES = { { value = "", text = "None" }, { value = "OUTLINE", text = "Outline" }, { value = "THICKOUTLINE", text = "Thick outline" } }
local SIDES = { { value = "left", text = "Left of the number" }, { value = "right", text = "Right of the number" } }
local NUMBERS = { { value = "short", text = "Short (12.3k)" }, { value = "full", text = "Full (12,345)" } }
local MODES = {
	{ value = "smart", text = "Only mine (best guess in groups)" },
	{ value = "all",   text = "Everything that hits my target" },
}

local app = UI:NewApp({
	name = "Whack",
	addon = ADDON,
	slash = "/whack",
	tagline = "Scrolling combat text: your hits and the hits you take.",
	aiAbout = "Whack is scrolling combat text. It has three areas on screen, each with its own settings: outgoing (the hits "
		.. "you deal, on your target), incoming (the hits you take and heals you receive) and notifications (loot, money, "
		.. "skill-ups, reputation, XP and more; off until switched on). Area settings are keyed by area: outgoing.fontsize, "
		.. "incoming.style, notify.enabled. Positions are pixels from the screen centre; /whack unlock shows the areas to drag.",
	siteURL = "https://everlookdb.com/whack.html",
	accent = ns.ACCENT,
	position = function() return ns.db end,
	feedbackURL = ns.FEEDBACK_URL,
	buttons = {
		{ label = "Unlock areas", text = function() return ns.db and not ns.db.locked and "Lock areas" or "Unlock areas" end,
			onClick = function() ns.Display:SetLocked(not ns.db.locked) end,
			desc = "Show the two text areas so you can drag them where you want them." },
		{ label = "Test both", onClick = function() ns.Combat:Test() end, desc = "Fake numbers in both areas." },
	},
})
ns.app = app

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
app:Setting({
	key = "mode", type = "choice", label = "Outgoing: whose hits to show", choices = MODES, width = 320,
	keywords = { "filter", "group", "only mine", "everything" },
	get = function() return ns.db.outgoingMode end, default = ns.DEFAULTS.outgoingMode,
	set = function(v) ns.db.outgoingMode = v end,
	desc = "The game only tells addons that your target was hit, not by whom. Whack matches hits to your own swings and casts. Solo, hits it can't match (damage over time, your pet) count as yours unless someone else is fighting your target (tapped by them, or it attacks another player).",
})
app:Setting({
	key = "maxtexts", type = "number", label = "Most texts on screen per area", min = 10, max = 100,
	keywords = { "limit", "max", "clutter", "spam" },
	get = function() return ns.db.maxActive end, default = ns.DEFAULTS.maxActive,
	set = function(v) ns.db.maxActive = v end,
	desc = "When a fight floods an area, the oldest text goes first.",
})

-- Area options, set from chat as "/whack outgoing.fontsize 20", "/whack incoming.style arc", ...
local AREA_OPTIONS = {
	{ "enabled", "bool", "Show %s text" },
	{ "style", "choice", "Style", { choices = STYLES, width = 300 } },
	{ "direction", "choice", "Direction", { choices = DIRECTIONS, width = 300, desc = "Which way scroll, arc and cascade texts travel. Burst ignores this." } },
	{ "duration", "number", "Time on screen (seconds)", { min = 0.6, max = 5, step = 0.1, fmt = "%.1f" } },
	{ "font", "choice", "Font", { choices = ns.FONTS, width = 300 } },
	{ "fontSize", "number", "Font size", { min = 8, max = 48 } },
	{ "critScale", "number", "Critical hits: size multiplier", { min = 1, max = 3, step = 0.05, fmt = "%.2f" } },
	{ "outline", "choice", "Outline", { choices = OUTLINES, width = 300 } },
	{ "shadow", "bool", "Drop shadow behind the text", { desc = "A soft shadow under the letters. With an outline as well the edges get heavier; turn it off for a cleaner, sharper look." } },
	{ "align", "choice", "Alignment inside the area", { choices = ALIGNS, width = 300 } },
	{ "numberFormat", "choice", "Numbers", { choices = NUMBERS, width = 300 } },
	{ "colorSchool", "bool", "Colour by spell school (fire orange, shadow purple...)" },
	{ "color", "color", "Colour of plain hits", { desc = "Physical hits and anything without a school colour." } },
	{ "showMisses", "bool", "Show misses, dodges, parries and resists" },
	{ "critBang", "bool", "Add \"!\" to critical hits", { only = "outgoing" } },
	{ "showHeals", "bool", "Show heals you receive", { only = "incoming" } },
	{ "healColor", "color", "Colour of heals", { only = "incoming", disabled = function() return not ns.db.areas.incoming.showHeals end } },
	{ "showIcon", "bool", "Show the spell / weapon icon", { only = "outgoing" } },
	{ "iconSide", "choice", "Icon position", { choices = SIDES, width = 300, only = "outgoing", disabled = function() return not ns.db.areas.outgoing.showIcon end } },
	{ "showIcon", "bool", "Show item icons", { only = "notify" } },
	{ "iconSide", "choice", "Icon position", { choices = { { value = "left", text = "Left of the text" }, { value = "right", text = "Right of the text" } },
		width = 300, only = "notify", disabled = function() return not ns.db.areas.notify.showIcon end } },
	{ "x", "number", "Horizontal position (0 = screen centre)", { min = -1200, max = 1200 } },
	{ "y", "number", "Vertical position", { min = -700, max = 700 } },
	{ "width", "number", "Width", { min = 60, max = 600 } },
	{ "height", "number", "Height (how far text travels)", { min = 40, max = 700 } },
}

-- more words the window's search finds an area option by
local KEYWORDS = {
	enabled = { "on", "off", "disable" },
	style = { "animation", "motion" },
	direction = { "up", "down" },
	duration = { "speed", "fade", "time", "seconds" },
	font = { "typeface" },
	fontSize = { "text size", "bigger", "smaller" },
	critScale = { "crit", "size", "bigger" },
	outline = { "border", "stroke" },
	shadow = { "outline" },
	align = { "justify" },
	numberFormat = { "abbreviate", "short", "thousands", "format" },
	colorSchool = { "colour", "fire", "frost", "nature", "school" },
	color = { "colour" },
	showMisses = { "dodge", "parry", "resist", "block", "absorb", "immune" },
	critBang = { "exclamation", "crit" },
	showHeals = { "healing" },
	healColor = { "colour", "healing" },
	showIcon = { "spell icon", "weapon" },
	iconSide = { "left", "right" },
	x = { "position", "move", "offset", "horizontal" },
	y = { "position", "move", "offset", "vertical" },
	width = { "size" },
	height = { "size", "distance" },
}

-- The notifications area has no hits: no crits, school colours, misses or number formats.
local NOTIFY_FIELDS = { enabled = true, style = true, direction = true, duration = true, font = true, fontSize = true,
	outline = true, shadow = true, align = true, x = true, y = true, width = true, height = true }
local AREA_NAMES = { outgoing = "Outgoing", incoming = "Incoming", notify = "Notifications" }
local NOTIFY_KEYWORDS = { "notifications", "loot", "items", "skill", "profession", "reputation", "rep", "xp",
	"experience", "money", "gold", "quest", "honor", "honour", "level" }

for _, area in ipairs({ "outgoing", "incoming", "notify" }) do
	local Area = AREA_NAMES[area]
	for _, o in ipairs(AREA_OPTIONS) do
		local field, kind, label, extra = o[1], o[2], o[3], o[4] or {}
		local wanted
		if area == "notify" then
			wanted = extra.only == "notify" or (not extra.only and NOTIFY_FIELDS[field])
		else
			wanted = not extra.only or extra.only == area
		end
		if wanted then
			label = label:format(area)
			local keywords = KEYWORDS[field]
			if area == "notify" and field == "enabled" then
				label = "Show notifications (loot, skill-ups...)"
				keywords = NOTIFY_KEYWORDS
			end
			local def = {
				key = area .. "." .. field:lower(), type = kind, label = label, keywords = keywords,
				-- chat replies say which area: "Outgoing font size: 20"
				chatLabel = field == "enabled" and label or (Area .. " " .. label:sub(1, 1):lower() .. label:sub(2)),
				get = function() return ns.db.areas[area][field] end,
				default = function() return ns.DEFAULTS.areas[area][field] end,
				set = function(v) ns.db.areas[area][field] = v end,
				after = function() ns.Display:Layout(area) end,
			}
			for k, v in pairs(extra) do if k ~= "only" then def[k] = v end end
			app:Setting(def)
		end
	end
end

-- What the notifications area shows: "/whack loot on", "/whack rep on", "/whack loot.quality uncommon".
-- Turning one on also turns the area on, so "/whack loot on" is all it takes.
local function QualityName(i, fallback)
	local s = _G["ITEM_QUALITY" .. i .. "_DESC"]
	return type(s) == "string" and s or fallback
end
local QUALITIES = {
	{ value = 0, text = QualityName(0, "Poor") .. " (grey) and up: everything" },
	{ value = 1, text = QualityName(1, "Common") .. " (white) and up" },
	{ value = 2, text = QualityName(2, "Uncommon") .. " (green) and up" },
	{ value = 3, text = QualityName(3, "Rare") .. " (blue) and up" },
	{ value = 4, text = QualityName(4, "Epic") .. " (purple) and up" },
}

local function NotifyOn(v)
	if v and not ns.db.areas.notify.enabled then
		ns.db.areas.notify.enabled = true
		ns.Display:Layout("notify")
		ns:Print("Notifications on.")
	end
end

-- field in ns.db.notify, chat key, label, search words, description[, type, extra]
local KINDS = {
	{ "loot", "loot", "Loot: items you loot, receive or create", { "items", "drops", "icon" },
		"The item's icon, its name in its quality colour, and how many. The same item within a second joins one line (Linen Cloth \195\1515)." },
	{ "quality", "loot.quality", "Loot: lowest quality shown", { "items", "grey", "junk", "rarity", "uncommon", "rare", "epic" },
		"Hide cheaper items.", "choice", { choices = QUALITIES, width = 300 } },
	{ "money", "money", "Money you gain (loot, quests, sales)", { "gold", "silver", "copper", "coins" },
		"Gold, silver and copper with the coin icons. Spending is not shown." },
	{ "currency", "currency", "Currencies you receive", { "tokens", "marks", "badges" } },
	{ "skill", "skill", "Skill-ups", { "profession", "mining", "herbalism", "weapon skill", "rank" },
		"\"Mining 112\" when a profession or weapon skill goes up." },
	{ "rep", "rep", "Reputation gains and losses", { "reputation", "faction", "standing" }, "\"+25 Stormwind\"." },
	{ "xp", "xp", "Experience gained", { "experience", "exp" }, "\"+340 XP\" for kills, quests and exploring." },
	{ "honor", "honor", "Honour gained", { "honour", "pvp", "battleground" } },
	{ "level", "levelup", "Level up", { "ding", "level" } },
	{ "quest", "quest", "Quest progress", { "objectives", "quests" }, "\"Turtle Meat: 3/10\" as you collect and kill." },
	{ "bagsFull", "bagsfull", "Bags full", { "inventory", "space", "bag" }, "When loot doesn't fit (at most every few seconds)." },
}
for _, k in ipairs(KINDS) do
	local field, key, label, keywords, desc, kind, extra = k[1], k[2], k[3], k[4], k[5], k[6] or "bool", k[7] or {}
	local def = {
		key = key, type = kind, label = label, desc = desc, keywords = keywords,
		chatLabel = "Notifications: " .. label:sub(1, 1):lower() .. label:sub(2),
		get = function() return ns.db.notify[field] end,
		default = function() return ns.DEFAULTS.notify[field] end,
		set = function(v) ns.db.notify[field] = v end,
		after = kind == "bool" and NotifyOn or nil,
	}
	for kk, v in pairs(extra) do def[kk] = v end
	app:Setting(def)
end

local function ResetNotify()
	ns.db.notify = ns.Util.CopyTable(ns.DEFAULTS.notify)
	ns:ResetArea("notify")
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
-- /whack unlock, lock and move; reset outgoing|incoming (asks first); status; feedback: the shared EverlookUI verbs.
app:Movable({ what = "the text areas", get = function() return ns.db.locked end, set = function(locked) ns.Display:SetLocked(locked) end })
app:Reset("outgoing", "the outgoing area", function() ns:ResetArea("outgoing") end)
app:Reset("incoming", "the incoming area", function() ns:ResetArea("incoming") end)
app:Reset("notify", "the notifications area and what it shows", ResetNotify)
app:StatusLines(function() ns.Combat:Status(); ns.Notify:Status() end) -- what Whack has seen since login
app:Command("test", "test", "fake numbers in both areas", function() ns.Combat:Test() end)
-- "/whack notify on | off | test"; the switch itself is the setting notify.enabled
app:Command("notify", "notify on || off || test", "loot, skill-ups and more as floating text", function(rest)
	local w = (rest or ""):lower():match("^(%S*)")
	if w == "test" then ns.Notify:Test() return end
	app:SetFromText(app:GetSetting("notify.enabled"), w == "" and "toggle" or w)
end, { "notifications" })

------------------------------------------------------------------------
-- Window sections
------------------------------------------------------------------------
local function BuildArea(stack, area)
	local outgoing = area == "outgoing"
	local function W(field) return app:Widget(stack, area .. "." .. field:lower()) end
	UI.Header(stack, outgoing and "Outgoing" or "Incoming",
		outgoing and "Your auto attacks, wand shots and spells landing on your target."
			or "Damage and heals you take.")
	UI.ButtonRow(stack, {
		{ label = "Show test numbers", style = "accent", width = 160, onClick = function() ns.Combat:Test(area) end },
		{ label = "Reset this area", width = 160, confirm = true, keywords = { "defaults" }, onClick = function()
			ns:ResetArea(area)
			app:Refresh()
		end },
	})
	W("enabled")

	UI.Header(stack, "Motion")
	W("style")
	W("direction")
	W("duration")

	UI.Header(stack, "Text")
	W("font")
	W("fontSize")
	W("critScale")
	W("outline")
	W("shadow")
	W("align")
	W("numberFormat")
	W("colorSchool")
	W("color")
	W("showMisses")
	if outgoing then
		W("critBang")
	else
		W("showHeals")
		W("healColor")
	end
	if outgoing then
		UI.Header(stack, "Icon")
		W("showIcon")
		W("iconSide")
	end

	UI.Header(stack, "Area", "Drag it on screen with Unlock areas (bottom left), or set it exactly here.")
	W("x")
	W("y")
	W("width")
	W("height")
end

local function BuildNotify(stack)
	local function W(key) return app:Widget(stack, key) end
	UI.Header(stack, "Notifications", "Loot, skill-ups and more as floating text, in their own area.")
	UI.ButtonRow(stack, {
		{ label = "Show test notifications", style = "accent", width = 190, onClick = function() ns.Notify:Test() end },
		{ label = "Reset this area", width = 160, confirm = true, keywords = { "defaults" }, onClick = function()
			ResetNotify()
			app:Refresh()
		end },
	})
	W("notify.enabled")

	UI.Header(stack, "What to show")
	W("loot")
	W("loot.quality")
	W("money")
	if ns.Notify.hasCurrency ~= false then W("currency") end
	W("skill")
	W("rep")
	W("xp")
	if ns.Notify.hasHonor ~= false then W("honor") end
	W("levelup")
	W("quest")
	W("bagsfull")

	UI.Header(stack, "Motion")
	W("notify.style")
	W("notify.direction")
	W("notify.duration")

	UI.Header(stack, "Text")
	W("notify.font")
	W("notify.fontsize")
	W("notify.outline")
	W("notify.shadow")
	W("notify.align")
	W("notify.showicon")
	W("notify.iconside")

	UI.Header(stack, "Area", "Drag it on screen with Unlock areas (bottom left), or set it exactly here.")
	W("notify.x")
	W("notify.y")
	W("notify.width")
	W("notify.height")
	UI.Note(stack, "In dungeons and raids the game can hide what a loot message says from addons. Whack then shows your own loot as the game's plain message, or nothing when it can't tell the loot is yours.")
end

app:Section("outgoing", "Outgoing", function(stack) BuildArea(stack, "outgoing") end)
app:Section("incoming", "Incoming", function(stack) BuildArea(stack, "incoming") end)
app:Section("notify", "Notifications", BuildNotify)
app:Section("general", "General", function(stack)
	UI.Header(stack, "General")
	app:Widget(stack, "mode")
	app:Widget(stack, "maxtexts")
	UI.Note(stack, "How it knows what you hit: this client gives addons no combat log, so Whack watches hits on your target and pairs them with your own swings, wand shots and casts. Solo that is exact, unless another player fights your target: then only the hits it can pair with you show. In a group, \"Only mine\" drops hits it cannot pair with something you did, which also drops your damage-over-time ticks. Hits on mobs you are not targeting are not shown.")
	UI.Header(stack, "Chat commands", "Everything here can also be done from chat.")
	UI.Note(stack, "/whack  this window\n/whack unlock, /whack lock  move the areas\n/whack test  fake numbers\n/whack notify on, /whack notify test  loot, skill-ups and more\n/whack loot on, /whack rep off, /whack loot.quality uncommon  what it shows\n/whack reset outgoing (incoming, notify)  an area back to its defaults (type it twice)\n/whack status, /whack feedback\n/whack outgoing.fontsize 20  change a setting (/whack get lists them)\n/whack search <words>  find a setting\n/whack help  all of this in chat")
end)

------------------------------------------------------------------------
-- The API the rest of Whack (and its tests) use
------------------------------------------------------------------------
function O:ShowPage(id) app:Open(id) end
function O:Refresh() app:Refresh() end
function O:Toggle() app:Toggle() end

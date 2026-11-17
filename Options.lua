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
	get = function() return ns.db.outgoingMode end,
	set = function(v) ns.db.outgoingMode = v end,
	desc = "The game only tells addons that your target was hit, not by whom. Whack matches hits to your own swings and casts. Solo, everything on your target is shown either way.",
})
app:Setting({
	key = "maxtexts", type = "number", label = "Most texts on screen per area", min = 10, max = 100,
	keywords = { "limit", "max", "clutter", "spam" },
	get = function() return ns.db.maxActive end,
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

for _, area in ipairs({ "outgoing", "incoming" }) do
	local Area = area:sub(1, 1):upper() .. area:sub(2)
	for _, o in ipairs(AREA_OPTIONS) do
		local field, kind, label, extra = o[1], o[2], o[3], o[4] or {}
		if not extra.only or extra.only == area then
			label = label:format(area)
			local def = {
				key = area .. "." .. field:lower(), type = kind, label = label, keywords = KEYWORDS[field],
				-- chat replies say which area: "Outgoing font size: 20"
				chatLabel = field == "enabled" and label or (Area .. " " .. label:sub(1, 1):lower() .. label:sub(2)),
				get = function() return ns.db.areas[area][field] end,
				set = function(v) ns.db.areas[area][field] = v end,
				after = function() ns.Display:Layout(area) end,
			}
			for k, v in pairs(extra) do if k ~= "only" then def[k] = v end end
			app:Setting(def)
		end
	end
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
-- /whack unlock, lock and move; reset outgoing|incoming (asks first); status; feedback: the shared EverlookUI verbs.
app:Movable({ what = "the text areas", get = function() return ns.db.locked end, set = function(locked) ns.Display:SetLocked(locked) end })
app:Reset("outgoing", "the outgoing area", function() ns:ResetArea("outgoing") end)
app:Reset("incoming", "the incoming area", function() ns:ResetArea("incoming") end)
app:StatusLines(function() ns.Combat:Status() end) -- what Whack has seen since login
app:Command("test", "test", "fake numbers in both areas", function() ns.Combat:Test() end)

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

app:Section("outgoing", "Outgoing", function(stack) BuildArea(stack, "outgoing") end)
app:Section("incoming", "Incoming", function(stack) BuildArea(stack, "incoming") end)
app:Section("general", "General", function(stack)
	UI.Header(stack, "General")
	app:Widget(stack, "mode")
	app:Widget(stack, "maxtexts")
	UI.Note(stack, "How it knows what you hit: this client gives addons no combat log, so Whack watches hits on your target and pairs them with your own swings, wand shots and casts. Solo that is exact. In a group, \"Only mine\" drops hits it cannot pair with something you did, which also drops your damage-over-time ticks. Hits on mobs you are not targeting are not shown.")
	UI.Header(stack, "Chat commands", "Everything here can also be done from chat.")
	UI.Note(stack, "/whack  this window\n/whack unlock, /whack lock  move the areas\n/whack test  fake numbers\n/whack reset outgoing  an area back to its defaults (type it twice)\n/whack status, /whack feedback\n/whack outgoing.fontsize 20  change a setting (/whack get lists them)\n/whack search <words>  find a setting\n/whack help  all of this in chat")
end)

------------------------------------------------------------------------
-- The API the rest of Whack (and its tests) use
------------------------------------------------------------------------
function O:ShowPage(id) app:Open(id) end
function O:Refresh() app:Refresh() end
function O:Toggle() app:Toggle() end

-- Offline test run for Whack. Loads the addon in TOC order against wowmock.lua
-- (secret values throw on math/compare) and drives combat events through it.
local ROOT = ...
local ADDON = "Whack"
local ns = {}
local failures, passes = {}, 0

local function step(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passes = passes + 1
		print("  ok   " .. name)
	else
		failures[#failures + 1] = name .. ": " .. tostring(err)
		print("  FAIL " .. name .. "\n         " .. tostring(err))
	end
end
local function check(cond, msg) if not cond then error(msg, 2) end end
local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

-- Extra API this addon uses
BreakUpLargeNumbers = function(n) return n end
GetInventoryItemTexture = function(_, slot) return "slot" .. slot end
C_Spell.IsSpellHarmful = function(id) return id < 50000 end
C_Spell.GetSpellTexture = function(id) return "spell" .. id end
UnitCanAttack = function() return true end

local function S(v) return MOCK.Secret(v) end
local function advance(dt) MOCK.time = MOCK.time + dt end
local function frame()
	for _, w in ipairs(MOCK.widgets) do
		local fn = w.__scripts.OnUpdate
		if fn and w.__shown then fn(w, 0.016) end
	end
end
local function active(key) return ns.Display:ActiveCount(key) end
local function lastText(key)
	local a = ns.Display:GetArea(key)
	return a.active[#a.active]
end
local function clear() ns.Display:Clear("outgoing"); ns.Display:Clear("incoming") end

-- Taint guard: every global the addon assigns (at load or later) is recorded. Addon
-- code must not write Blizzard globals (in WoW Forever that taints Blizzard's UI and
-- its secret-value checks fail, e.g. closing the character sheet).
local globalWrites = {}
local addonEnv = setmetatable({}, {
	__index = _G,
	__newindex = function(_, k, v) globalWrites[k] = true; _G[k] = v end,
})

step("load TOC files", function()
	local toc = assert(io.open(ROOT .. "/Whack.toc")):read("*a")
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^%s*#") and line:match("%.lua%s*$") then
			local path = ROOT .. "/" .. line:gsub("\\", "/"):gsub("%s+$", "")
			local chunk, err = loadfile(path)
			if not chunk then error("syntax: " .. err) end
			setfenv(chunk, addonEnv)
			chunk(ADDON, ns)
		end
	end
end)

step("ADDON_LOADED", function()
	MOCK.Fire("ADDON_LOADED", ADDON)
	check(ns.db and ns.db.areas.outgoing and ns.db.areas.incoming, "db not initialised")
	check(WhackDB == ns.db, "saved variable not bound")
end)

step("solo melee hit shows with weapon icon (secret amount)", function()
	MOCK.Fire("PLAYER_SWING", 2.0, 0)
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(123), 1)
	check(active("outgoing") == 0, "should wait a moment before showing")
	MOCK.RunTimers()
	check(active("outgoing") == 1, "expected 1 outgoing text, got " .. active("outgoing"))
	check(lastText("outgoing").icon:IsShown(), "icon should show")
	clear()
end)

step("crit is flagged", function()
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S(500), 4)
	MOCK.RunTimers()
	local t = lastText("outgoing")
	check(t and t.crit, "crit flag lost")
	clear()
end)

step("solo: unmatched hit (DoT tick) still shows", function()
	advance(5)
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(30), 32)
	MOCK.RunTimers()
	check(active("outgoing") == 1, "solo hits should always show")
	clear()
end)

step("solo: someone else fighting your target: their hits are not yours", function()
	advance(5)
	-- another player is the one your target fights
	MOCK.units.targettarget = { name = "Stranger", class = "WARRIOR" }
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(88), 1)
	MOCK.RunTimers()
	eq(active("outgoing"), 0, "another player's hit shown as mine")
	-- but my own swing still is
	MOCK.Fire("PLAYER_SWING", 2.0, 0)
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(55), 1)
	MOCK.RunTimers()
	eq(active("outgoing"), 1, "my matched swing")
	clear()
	-- it fights me (or a non-player): an unmatched tick is mine again
	MOCK.units.targettarget = MOCK.units.player
	advance(5)
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(30), 32)
	MOCK.RunTimers()
	eq(active("outgoing"), 1, "my DoT tick while it fights me")
	clear()
	-- tapped by someone else
	MOCK.units.targettarget = nil
	MOCK.tapDenied = true
	advance(5)
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(30), 32)
	MOCK.RunTimers()
	eq(active("outgoing"), 0, "tapped by someone else")
	MOCK.tapDenied = false
	clear()
end)

step("group smart mode: other people's hits are dropped", function()
	MOCK.SetGroup(5, false)
	advance(5)
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(999), 1)
	MOCK.RunTimers()
	check(active("outgoing") == 0, "unattributed hit shown in group")
end)

step("group: my spell hit is matched to its cast", function()
	advance(5)
	MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 585)
	advance(1.2) -- travel time
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(200), 2)
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(77), 2) -- someone else's
	MOCK.RunTimers()
	check(active("outgoing") == 1, "expected exactly my one hit, got " .. active("outgoing"))
	clear()
end)

step("group: helpful casts are not taken as damage", function()
	advance(5)
	MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 60000)
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(50), 2)
	MOCK.RunTimers()
	check(active("outgoing") == 0, "heal cast was matched to a hit")
end)

step("wand: swing + Shoot cast count once", function()
	advance(5)
	MOCK.Fire("PLAYER_SWING", 1.5, 2)
	MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 5019)
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(40), 32)
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(41), 32)
	MOCK.RunTimers()
	check(active("outgoing") == 1, "wand shot double counted: " .. active("outgoing"))
	clear()
end)

step("group: channel ticks are mine", function()
	advance(5)
	MOCK.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-4", 15407)
	advance(1); MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(60), 32); MOCK.RunTimers()
	advance(1); MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(60), 32); MOCK.RunTimers()
	MOCK.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-4", 15407)
	advance(2); MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(60), 32); MOCK.RunTimers()
	check(active("outgoing") == 2, "expected 2 channel ticks, got " .. active("outgoing"))
	clear()
end)

step("group: all mode shows everything", function()
	ns.db.outgoingMode = "all"
	advance(5)
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(1), 1)
	MOCK.Fire("UNIT_COMBAT", "target", "PARRY", "", S(0), 1)
	MOCK.RunTimers()
	check(active("outgoing") == 2, "all mode should show 2")
	ns.db.outgoingMode = "smart"
	MOCK.SetGroup(1, false)
	clear()
end)

step("incoming damage, crushing, heal, dodge; energize ignored", function()
	MOCK.Fire("UNIT_COMBAT", "player", "WOUND", "", S(45), 1)
	MOCK.Fire("UNIT_COMBAT", "player", "WOUND", "CRUSHING", S(90), 1)
	MOCK.Fire("UNIT_COMBAT", "player", "HEAL", "", S(120), 2)
	MOCK.Fire("UNIT_COMBAT", "player", "DODGE", "", S(0), 1)
	MOCK.Fire("UNIT_COMBAT", "player", "ENERGIZE", "", S(10), 0)
	check(active("incoming") == 4, "expected 4 incoming, got " .. active("incoming"))
	ns.db.areas.incoming.showHeals = false
	MOCK.Fire("UNIT_COMBAT", "player", "HEAL", "", S(120), 2)
	check(active("incoming") == 4, "heal shown while off")
	ns.db.areas.incoming.showHeals = true
	clear()
end)

step("readable zero amount with absorb flag shows the word", function()
	MOCK.Fire("UNIT_COMBAT", "player", "WOUND", "ABSORB", 0, 1)
	check(active("incoming") == 1, "absorb not shown")
	local a = ns.Display:GetArea("incoming")
	check(a.active[1].text:GetText() == "Absorbed", "readable full absorb: " .. tostring(a.active[1].text:GetText()))
	clear()
end)

step("secret amounts with the absorb flag: \"Absorbed\" when all of it was absorbed, never \"-0 (absorbed)\"", function()
	local a = ns.Display:GetArea("incoming")
	MOCK.Fire("UNIT_COMBAT", "player", "WOUND", "ABSORB", MOCK.Secret(0), 1)
	check(active("incoming") == 1, "not shown")
	eq(MOCK.real(a.active[1].text:GetText()), "Absorbed", "fully absorbed")
	MOCK.Fire("UNIT_COMBAT", "player", "WOUND", "ABSORB", MOCK.Secret(57), 1)
	eq(MOCK.real(a.active[2].text:GetText()), "Absorbed (-57)", "partly absorbed")
	clear()
	eq(ns.Combat.AbsorbedText(MOCK.Secret(0), false) and MOCK.real(ns.Combat.AbsorbedText(MOCK.Secret(0), false)), "Absorbed", "outgoing word")
	eq(MOCK.real(ns.Combat.AbsorbedText(MOCK.Secret(12), false)), "Absorbed (12)", "outgoing partial")
end)

for _, style in ipairs({ "scroll", "arc", "cascade", "burst" }) do
	for _, dir in ipairs({ "up", "down" }) do
		step("animation " .. style .. " " .. dir .. " runs and expires", function()
			for _, key in ipairs({ "outgoing", "incoming" }) do
				ns.db.areas[key].style = style
				ns.db.areas[key].direction = dir
				ns.db.areas[key].align = dir == "up" and "left" or "right"
				ns.db.areas[key].iconSide = dir == "up" and "left" or "right"
			end
			for _ = 1, 12 do
				ns.Combat:TestOne()
				advance(0.05)
				frame()
			end
			check(active("outgoing") > 0, "nothing on screen")
			if style == "scroll" or style == "arc" then
				local a = ns.Display:GetArea("outgoing")
				local c = ns.db.areas.outgoing
				for i = 2, #a.active do
					local older, newer = a.active[i - 1], a.active[i]
					local dOld = (c.height - older.lineH) * math.min(1, (MOCK.time - older.born) / older.dur) + older.bump
					local dNew = (c.height - newer.lineH) * math.min(1, (MOCK.time - newer.born) / newer.dur) + newer.bump
					check(dOld - dNew >= newer.lineH - 0.01, "texts overlap: " .. dOld .. " vs " .. dNew)
				end
			end
			for _ = 1, 80 do advance(0.1); frame() end
			check(active("outgoing") == 0 and active("incoming") == 0, "texts did not expire")
		end)
	end
end

step("flood is capped", function()
	for _ = 1, 200 do ns.Combat:TestOne("outgoing") end
	check(active("outgoing") <= 40, "no cap: " .. active("outgoing"))
	clear()
end)

step("disabled area shows nothing", function()
	ns.db.areas.outgoing.enabled = false
	ns.Display:Layout("outgoing")
	MOCK.Fire("UNIT_COMBAT", "target", "WOUND", "", S(5), 1)
	MOCK.RunTimers()
	check(active("outgoing") == 0, "disabled area spawned text")
	ns.db.areas.outgoing.enabled = true
	ns.Display:Layout("outgoing")
end)

step("unlock, drag, lock", function()
	ns.Display:SetLocked(false)
	local a = ns.Display:GetArea("outgoing")
	check(a.mover:IsShown(), "mover hidden while unlocked")
	a.mover.__scripts.OnDragStart(a.mover)
	a.mover.__scripts.OnDragStop(a.mover)
	ns.Display:SetLocked(true)
	check(not a.mover:IsShown(), "mover shown while locked")
end)

step("options window: every page builds and refreshes", function()
	SlashCmdList.WHACK("")
	for _, id in ipairs({ "outgoing", "incoming", "general", "outgoing" }) do ns.Options:ShowPage(id) end
	ns.Options:Refresh()
	ns:ResetArea("incoming")
	ns.Options:ShowPage("incoming")
	SlashCmdList.WHACK("")
end)

step("options: the wheel scrolls the page, the bar drags, sliders ignore the wheel", function()
	if not WhackOptionsWindow:IsShown() then SlashCmdList.WHACK("") end
	ns.Options:ShowPage("outgoing")
	local scroll
	for _, c in ipairs(WhackOptionsWindow.content.__children) do
		if c.__kind == "ScrollFrame" and c:IsShown() then scroll = c end
	end
	check(scroll and scroll.track, "no page scroll with a bar")
	scroll.SetVerticalScroll = function(self, v) self.__vs = v end
	scroll.GetVerticalScroll = function(self) return self.__vs or 0 end
	local child, track = scroll.child, scroll.track
	scroll.__h, child.__h, track.__h = 400, 1500, 420
	scroll.UpdateBar()
	check(track:IsShown(), "bar hidden with content to scroll")
	check(track:GetWidth() >= 12, "bar too narrow to grab")

	scroll:GetScript("OnMouseWheel")(scroll, -1)
	check(scroll:GetVerticalScroll() == 40, "wheel down didn't scroll 40, got " .. scroll:GetVerticalScroll())
	scroll:GetScript("OnMouseWheel")(scroll, 5)
	check(scroll:GetVerticalScroll() == 0, "wheel up went past the top")

	local thumb = track.__children[#track.__children]
	local cy, down = 300, true
	local oldCursor, oldDown = GetCursorPosition, IsMouseButtonDown
	GetCursorPosition = function() return 0, cy end
	IsMouseButtonDown = function() return down end
	thumb:GetScript("OnMouseDown")(thumb, "RightButton")
	check(not thumb.dragging, "right button grabbed the thumb")
	thumb:GetScript("OnMouseDown")(thumb, "LeftButton")
	cy = 250
	thumb:GetScript("OnUpdate")(thumb)
	local v = scroll:GetVerticalScroll()
	check(v > 0 and v == math.floor(v), "dragging the thumb down didn't scroll to a whole pixel: " .. v)
	cy = -5000
	thumb:GetScript("OnUpdate")(thumb)
	check(scroll:GetVerticalScroll() == 1100, "drag past the end didn't stop at the bottom")
	down = false
	thumb:GetScript("OnUpdate")(thumb)
	check(not thumb.dragging, "drag kept going after the button was released")

	scroll.__vs = 0
	cy = 100 -- below the thumb (mock GetBottom is 400)
	track:GetScript("OnMouseDown")(track, "LeftButton")
	check(scroll:GetVerticalScroll() == 360, "clicking the track didn't jump a page: " .. scroll:GetVerticalScroll())
	GetCursorPosition, IsMouseButtonDown = oldCursor, oldDown

	child.__h = 300
	scroll.UpdateBar()
	check(not track:IsShown(), "bar shown with nothing to scroll")
	for _, w in ipairs(MOCK.widgets) do
		if w.__kind == "Slider" then check(not w.__scripts.OnMouseWheel, "a slider takes the mouse wheel") end
	end
end)

step("slash commands", function()
	SlashCmdList.WHACK("unlock")
	check(not ns.db.locked, "unlock failed")
	SlashCmdList.WHACK("lock")
	check(ns.db.locked, "lock failed")
	SlashCmdList.WHACK("test")
	MOCK.RunTimers()
	SlashCmdList.WHACK("status")
	SlashCmdList.WHACK("help")
	local all = table.concat(MOCK.log, " ")
	check(all:find("/whack unlock || lock", 1, true) and all:find("/whack reset outgoing || incoming", 1, true)
		and all:find("/whack test", 1, true) and all:find("/whack get [setting]", 1, true), "help: " .. all)
end)

step("feedback link", function()
	SlashCmdList.WHACK("feedback")
	local d = WhackFeedbackWindow
	check(d and d:IsShown(), "feedback window not shown")
	check(d.box:GetText() == ns.FEEDBACK_URL, "feedback box doesn't hold the URL")
	d.box:SetText("typed over")
	d.box:GetScript("OnTextChanged")(d.box, true)
	check(d.box:GetText() == ns.FEEDBACK_URL, "feedback URL can be edited away")
	d.box:GetScript("OnEscapePressed")(d.box)
	check(not d:IsShown(), "escape in the box didn't close the window")
	SlashCmdList.WHACK("bug")
	check(d:IsShown(), "/whack bug didn't show the window")
	d.box:GetScript("OnEnterPressed")(d.box)
	check(not d:IsShown(), "enter didn't close the window")
	ns.ShowFeedback()
	d:GetScript("OnKeyDown")(d, "A")
	check(d:IsShown(), "a normal key closed the window")
	d:GetScript("OnKeyDown")(d, "ESCAPE")
	check(not d:IsShown(), "escape didn't close the window")
	check(next(MOCK.popups) == nil, "a Blizzard StaticPopup was used")
end)

step("options window closes on Escape without UISpecialFrames", function()
	if WhackOptionsWindow and WhackOptionsWindow:IsShown() then WhackOptionsWindow:Hide() end
	ns.Options:Toggle()
	check(WhackOptionsWindow:IsShown(), "options window not shown")
	WhackOptionsWindow:GetScript("OnKeyDown")(WhackOptionsWindow, "A")
	check(WhackOptionsWindow:IsShown(), "a normal key closed the window")
	WhackOptionsWindow:GetScript("OnKeyDown")(WhackOptionsWindow, "ESCAPE")
	check(not WhackOptionsWindow:IsShown(), "escape didn't close the window")
	MOCK.combat = true
	ns.Options:Toggle()
	WhackOptionsWindow:GetScript("OnKeyDown")(WhackOptionsWindow, "ESCAPE")
	MOCK.combat = false
	check(not WhackOptionsWindow:IsShown(), "escape in combat didn't close the window")
end)

step("new options: defaults keep the old behaviour, old saved settings get them", function()
	check(ns.db.maxActive == 40, "maxActive default")
	local o, i = ns.db.areas.outgoing, ns.db.areas.incoming
	check(o.color[1] == 1 and o.color[2] == 1 and o.color[3] == 1, "outgoing colour default not white")
	check(i.color[1] == 1 and i.color[2] == 0.25 and i.color[3] == 0.25, "incoming colour default not the old red")
	check(i.healColor[1] == 0.35 and i.healColor[2] == 1, "heal colour default")
	-- a saved file from before these options: FillDefaults adds them without touching the rest
	local old = { version = 1, outgoingMode = "all", areas = { outgoing = { fontSize = 30 }, incoming = {} } }
	ns.Util.FillDefaults(old, ns.DEFAULTS)
	check(old.outgoingMode == "all" and old.areas.outgoing.fontSize == 30, "old values overwritten")
	check(old.maxActive == 40 and old.areas.incoming.color[2] == 0.25 and old.areas.outgoing.color[2] == 1, "new defaults missing")
end)

step("slash settings: every subcommand works, settings set and reply", function()
	MOCK.log = {}
	SlashCmdList.WHACK("outgoing.fontsize 22")
	check(ns.db.areas.outgoing.fontSize == 22, "fontsize not set")
	check(MOCK.log[#MOCK.log]:find("Outgoing font size: 22", 1, true), "no reply: " .. tostring(MOCK.log[#MOCK.log]))
	SlashCmdList.WHACK("outgoing.fontsize 400")
	check(ns.db.areas.outgoing.fontSize == 22, "out of range accepted")
	check(MOCK.log[#MOCK.log]:find("Example: /whack outgoing.fontsize", 1, true), "no example: " .. MOCK.log[#MOCK.log])
	SlashCmdList.WHACK("incoming.style arc")
	check(ns.db.areas.incoming.style == "arc", "style not set")
	SlashCmdList.WHACK("incoming.outline none")
	check(ns.db.areas.incoming.outline == "", "outline none")
	SlashCmdList.WHACK("incoming.healcolor 00ff00")
	check(ns.db.areas.incoming.healColor[2] == 1 and ns.db.areas.incoming.healColor[1] == 0, "heal colour")
	SlashCmdList.WHACK("mode all")
	check(ns.db.outgoingMode == "all", "mode")
	SlashCmdList.WHACK("maxtexts 25")
	check(ns.db.maxActive == 25, "maxtexts")
	for _ = 1, 60 do ns.Combat:TestOne("outgoing") end
	check(active("outgoing") <= 25, "maxtexts not used: " .. active("outgoing"))
	clear()
	SlashCmdList.WHACK("outgoing.enabled off")
	check(ns.db.areas.outgoing.enabled == false, "enabled off")
	SlashCmdList.WHACK("outgoing.enabled on")
	SlashCmdList.WHACK("reset incoming")
	check(ns.db.areas.incoming.style == "arc" and MOCK.log[#MOCK.log]:find("/whack reset incoming again within 10 s", 1, true), "reset didn't ask first")
	SlashCmdList.WHACK("reset incoming")
	check(ns.db.areas.incoming.style == "scroll" and ns.db.areas.incoming.outline == "OUTLINE", "reset")
	SlashCmdList.WHACK("reset")
	check(MOCK.log[#MOCK.log]:find("/whack reset outgoing || incoming", 1, true), "reset without an area: " .. MOCK.log[#MOCK.log])
	SlashCmdList.WHACK("reset incomming")
	check(MOCK.log[#MOCK.log]:find("Did you mean /whack reset incoming?", 1, true), "reset typo: " .. MOCK.log[#MOCK.log])
	SlashCmdList.WHACK("set outgoing.fontsize 23")
	check(ns.db.areas.outgoing.fontSize == 23 or ns.db.areas.outgoing.fontsize == 23, "set")
	SlashCmdList.WHACK("get outgoing.fontsize")
	check(MOCK.log[#MOCK.log]:find("23", 1, true), "get: " .. MOCK.log[#MOCK.log])
	SlashCmdList.WHACK("off outgoing.enabled")
	check(ns.db.areas.outgoing.enabled == false, "off <setting>")
	SlashCmdList.WHACK("outgoing.enabled on")
	SlashCmdList.WHACK("outgoing.fontsiz 30")
	check(MOCK.log[#MOCK.log]:find("Did you mean /whack outgoing.fontsize 30?", 1, true), "typo: " .. MOCK.log[#MOCK.log])
	SlashCmdList.WHACK("tset")
	check(MOCK.log[#MOCK.log]:find("Did you mean /whack test?", 1, true), "command typo: " .. MOCK.log[#MOCK.log])
	SlashCmdList.WHACK("move")
	check(not ns.db.locked, "move didn't unlock")
	SlashCmdList.WHACK("move")
	check(ns.db.locked, "move didn't lock")
	MOCK.log = {}
	SlashCmdList.WHACK("settings")
	check(#MOCK.log > 20, "settings list too short")
	SlashCmdList.WHACK("nonsense")
	check(MOCK.log[#MOCK.log]:find("/whack help", 1, true), "unknown command reply")
	ns.db.maxActive, ns.db.outgoingMode = 40, "smart"
	ns:ResetArea("outgoing")
end)

step("the window updates when a setting changes from chat; the position is saved", function()
	ns.Options:ShowPage("outgoing")
	SlashCmdList.WHACK("outgoing.fontsize 31")
	local found
	for _, w in ipairs(MOCK.widgets) do
		if w.__kind == "EditBox" and w.__text == "31" then found = true end
	end
	check(found, "the slider box doesn't show the new size")
	WhackOptionsWindow:GetScript("OnDragStop")(WhackOptionsWindow)
	check(type(ns.db.window) == "table", "window position not saved")
	WhackOptionsWindow:Hide()
	ns:ResetArea("outgoing")
end)

step("no taint: Blizzard globals left alone", function()
	local allowed = { WhackDB = true, SLASH_WHACK1 = true, LibStub = true } -- LibStub: the embedded library loader
	for k in pairs(globalWrites) do
		check(allowed[k], "addon assigned the global " .. tostring(k))
	end
	check(next(UISpecialFrames) == nil, "addon added to UISpecialFrames")
	check(next(StaticPopupDialogs) == nil, "addon added to StaticPopupDialogs")
end)

step("settings search finds area options on both pages, by keyword too", function()
	local app = ns.app
	app:Open("general")
	local r = app:Search("dodge")
	check(#r == 2, "'dodge' should find Show misses in both areas, found " .. #r)
	local paths = r[1].entry.path .. " | " .. r[2].entry.path
	check(paths:find("Outgoing", 1, true) and paths:find("Incoming", 1, true), "paths: " .. paths)
	r = app:Search("incoming font size")
	check(#r >= 1 and r[1].entry.info.key == "incoming.fontsize", "'incoming font size' not first: " .. tostring(r[1] and r[1].entry.info.key))
	app:Search("")
	app:Close()
end)

------------------------------------------------------------------------
-- Notifications (Notify.lua)
------------------------------------------------------------------------
-- The game's format strings, as the client has them (enUS). Whack must only ever use these, never English.
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
LOOT_ITEM_CREATED_SELF = "You create: %s."
LOOT_ITEM = "%s receives loot: %s."
CURRENCY_GAINED = "You receive currency: %s."
CURRENCY_GAINED_MULTIPLE = "You receive currency: %s x%d."
SKILL_RANK_UP = "Your skill in %s has increased to %d."
FACTION_STANDING_INCREASED = "Your %s reputation has increased by %d."
FACTION_STANDING_INCREASED_ACH_BONUS = "Your %s reputation has increased by %d. (+%.1f bonus)"
FACTION_STANDING_DECREASED = "Your %s reputation has decreased by %d."
COMBATLOG_HONORAWARD = "You have been awarded %d honor points."
ERR_QUEST_ADD_ITEM_SII = "%s: %d/%d"
ERR_QUEST_ADD_KILL_SII = "%s slain: %d/%d"
ERR_INV_FULL = "Inventory is full."
LEVEL_GAINED = "Level %d"
XP = "XP"
HONOR = "Honor"
ITEM_QUALITY_COLORS = {
	[0] = { hex = "|cff9d9d9d" }, [1] = { hex = "|cffffffff" }, [2] = { hex = "|cff1eff00" },
	[3] = { hex = "|cff0070dd" }, [4] = { hex = "|cffa335ee" },
}
local ITEMS = {
	[2589] = { "Linen Cloth", 1, "icon-linen" },
	[2934] = { "Ruined Leather Scraps", 0, "icon-scraps" },
	[6070] = { "Wolfskin Bracers", 2, "icon-bracers" },
}
GetItemInfo = function(link)
	local id = tonumber(tostring(link):match("item:(%d+)"))
	local d = id and ITEMS[id]
	if not d then return nil end
	return d[1], link, d[2], 10, 5, "Trade Goods", "Cloth", 20, "", d[3]
end
local money, xp, xpMax, level = 5000, 100, 1000, 10
GetMoney = function() return money end
UnitXP = function() return xp end
UnitXPMax = function() return xpMax end
UnitLevel = function() return level end

local function link(id, colorHex)
	return colorHex .. "|Hitem:" .. id .. "::::::::|h[" .. ITEMS[id][1] .. "]|h|r"
end
local LINEN, SCRAPS, BRACERS = link(2589, "|cffffffff"), link(2934, "|cff9d9d9d"), link(6070, "|cff1eff00")
local function nactive() return active("notify") end
local function ntext(i)
	local a = ns.Display:GetArea("notify")
	local t = a.active[i or #a.active]
	return t and t.text:GetText(), t
end
-- run C_Timer.After callbacks only (MOCK.RunTimers would also tick the test ticker left from /whack test)
local function settle()
	for _ = 1, 30 do
		advance(0.2)
		local t = MOCK.timers
		MOCK.timers = {}
		for _, fn in ipairs(t) do fn() end
	end
end
local function nclear()
	settle()
	ns.Display:Clear("notify")
	ns.Notify:Clear()
	advance(5)
end

step("notify: off by default; loot and skill-ups ticked, the rest not", function()
	local o = ns.db.notify
	check(ns.db.areas.notify.enabled == false, "notifications should start off")
	check(o.loot and o.skill, "loot and skill-ups should be ticked")
	check(not (o.money or o.currency or o.rep or o.xp or o.honor or o.level or o.quest or o.bagsFull), "the rest should be off")
	check(o.quality == 0, "every quality by default")
	MOCK.Fire("CHAT_MSG_LOOT", "You receive loot: " .. LINEN .. ".", "", "", "", "Tester")
	settle()
	check(nactive() == 0, "loot shown while notifications are off")
end)

step("notify: format strings become patterns (positional, %%, floats)", function()
	local N = ns.Notify
	local pat = N.ToPattern("You receive loot: %sx%d.")
	check(pat == "^You receive loot: (.+)x(%-?%d+)%.$", "pattern: " .. pat)
	local _, order = N.ToPattern("%2$s gains %1$d (100%%)")
	check(order[1] == 2 and order[2] == 1, "positional order")
	check(("Bob gains 5 (100%)"):match((N.ToPattern("%2$s gains %1$d (100%%)"))) == "Bob", "%% and positional don't match")
	local which, args = N.Match("Your Stormwind reputation has increased by 25. (+2.5 bonus)", N.REP_UP)
	check(which == "FACTION_STANDING_INCREASED_ACH_BONUS" and args[1] == "Stormwind" and args[2] == "25", "rep bonus: " .. tostring(which))
	ERR_QUEST_UNKNOWN_COMPLETE = "Objective Complete."
	which, args = N.Match("Objective Complete.", N.QUEST_FORMATS)
	check(which == "ERR_QUEST_UNKNOWN_COMPLETE" and args and args[1] == nil, "a format with no arguments")
	-- another language: only the global changes
	local saved = LOOT_ITEM_SELF
	LOOT_ITEM_SELF = "Ihr erhaltet Beute: %s."
	which, args = N.Match("Ihr erhaltet Beute: " .. LINEN .. ".", N.LOOT_FORMATS)
	check(which == "LOOT_ITEM_SELF" and args[1] == LINEN, "localised loot string not matched")
	LOOT_ITEM_SELF = saved
end)

step("notify: /whack loot on turns the area on; loot shows icon, quality colour and count", function()
	SlashCmdList.WHACK("loot on")
	check(ns.db.areas.notify.enabled, "/whack loot on didn't turn notifications on")
	MOCK.Fire("CHAT_MSG_LOOT", "You receive loot: " .. BRACERS .. ".", "", "", "", "Tester")
	check(nactive() == 1, "loot not shown: " .. nactive())
	local text, t = ntext()
	check(text == "|cff1eff00Wolfskin Bracers|r", "text: " .. tostring(text))
	check(t.icon:IsShown() and t.entry.icon == "icon-bracers", "icon: " .. tostring(t.entry.icon))
	advance(2)
	MOCK.Fire("CHAT_MSG_LOOT", "You receive item: " .. LINEN .. "x4.", "", "", "", "Tester")
	check(ntext() == "|cffffffffLinen Cloth|r|cffcccccc \195\1514|r", "count: " .. tostring(ntext()))
	nclear()
end)

step("notify: someone else's loot and roll messages are ignored", function()
	MOCK.Fire("CHAT_MSG_LOOT", "Member2 receives loot: " .. LINEN .. ".", "", "", "", "Member2")
	MOCK.Fire("CHAT_MSG_LOOT", "Need Roll - 54 for " .. LINEN .. " by Member2", "", "", "", "")
	check(nactive() == 0, "not my loot shown")
end)

step("notify: the same item within a second merges into one line", function()
	MOCK.Fire("CHAT_MSG_LOOT", "You receive loot: " .. LINEN .. "x2.", "", "", "", "Tester")
	advance(0.4)
	MOCK.Fire("CHAT_MSG_LOOT", "You receive loot: " .. LINEN .. "x3.", "", "", "", "Tester")
	check(nactive() == 1, "merged loot made " .. nactive() .. " lines")
	check(ntext():find("\195\1515", 1, true), "merged count: " .. ntext())
	local _, t = ntext()
	check(t.pulse, "a merged line should pulse")
	advance(1.5) -- too late to merge
	MOCK.Fire("CHAT_MSG_LOOT", "You receive loot: " .. LINEN .. ".", "", "", "", "Tester")
	check(nactive() == 2, "loot after the merge window should be a new line")
	nclear()
end)

step("notify: mass loot is throttled and capped, nothing lost to the merge", function()
	local saved = ITEMS
	for id = 9000, 9019 do ITEMS[id] = { "Thing " .. id, 1, "icon" } end
	for id = 9000, 9019 do
		MOCK.Fire("CHAT_MSG_LOOT", "You receive loot: " .. link(id, "|cffffffff") .. ".", "", "", "", "Tester")
	end
	check(nactive() == 1, "a mass loot should show one line at once, not " .. nactive())
	-- the same item again while it waits in the queue joins its queued line
	MOCK.Fire("CHAT_MSG_LOOT", "You receive loot: " .. link(9003, "|cffffffff") .. "x2.", "", "", "", "Tester")
	local t = MOCK.timers; MOCK.timers = {}; for _, fn in ipairs(t) do fn() end -- too soon: the gap holds the next line back
	check(nactive() == 1, "throttle ignored")
	settle()
	check(nactive() == 10, "expected 1 + 8 queued + one '+N more' line, got " .. nactive())
	local found3, more
	for i = 1, nactive() do
		local s = ntext(i)
		if s:find("Thing 9003", 1, true) then found3 = s end
		if s:find("+11 more", 1, true) then more = true end
	end
	check(found3 and found3:find("\195\1513", 1, true), "queued merge: " .. tostring(found3))
	check(more, "no '+11 more' line")
	nclear()
end)

step("notify: minimum quality hides cheaper items", function()
	SlashCmdList.WHACK("loot.quality uncommon")
	check(ns.db.notify.quality == 2, "quality not set by name: " .. tostring(ns.db.notify.quality))
	MOCK.Fire("CHAT_MSG_LOOT", "You receive loot: " .. SCRAPS .. ".", "", "", "", "Tester")
	MOCK.Fire("CHAT_MSG_LOOT", "You receive loot: " .. LINEN .. ".", "", "", "", "Tester")
	settle()
	check(nactive() == 0, "grey/white shown at uncommon and up")
	MOCK.Fire("CHAT_MSG_LOOT", "You receive loot: " .. BRACERS .. ".", "", "", "", "Tester")
	check(nactive() == 1, "green hidden at uncommon and up")
	-- unknown item: quality from the link's colour, or from the newer |cnIQ form
	check(ns.Notify.ParseItem("|cff0070dd|Hitem:99999::|h[Mystery]|h|r").quality == 3, "quality from colour")
	check(ns.Notify.ParseItem("|cnIQ4:|Hitem:99998::|h[Epic Thing]|h|r").quality == 4, "quality from |cnIQ")
	SlashCmdList.WHACK("loot.quality 0")
	nclear()
end)

step("notify: money formatting with coin icons", function()
	local F = ns.Notify.FormatMoney
	local G, S_, C = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t", "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t", "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
	check(F(12345) == "1" .. G .. " 23" .. S_ .. " 45" .. C, "12345: " .. F(12345))
	check(F(50000) == "5" .. G, "50000: " .. F(50000))
	check(F(105) == "1" .. S_ .. " 5" .. C, "105: " .. F(105))
	check(F(7) == "7" .. C, "7: " .. F(7))
	check(F(0) == "0" .. C, "0: " .. F(0))
end)

step("notify: money gains from PLAYER_MONEY merge; spending shows nothing", function()
	SlashCmdList.WHACK("money on")
	ns.Notify:ReadMoney()
	money = money + 150; MOCK.Fire("PLAYER_MONEY")
	check(nactive() == 1, "money gain not shown")
	money = money + 10000; MOCK.Fire("PLAYER_MONEY")
	check(nactive() == 1 and ntext():find("^1|T"), "money didn't merge: " .. tostring(ntext()))
	advance(3)
	money = money - 500; MOCK.Fire("PLAYER_MONEY")
	check(nactive() == 1, "spending shown")
	nclear()
end)

step("notify: skill-ups, reputation, XP, honour, level, quest, bags full", function()
	SlashCmdList.WHACK("rep on"); SlashCmdList.WHACK("xp on"); SlashCmdList.WHACK("honor on")
	SlashCmdList.WHACK("levelup on"); SlashCmdList.WHACK("quest on"); SlashCmdList.WHACK("bagsfull on")
	MOCK.Fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 112.")
	check(ntext() == "Mining 112", "skill: " .. tostring(ntext()))
	advance(0.3)
	MOCK.Fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 113.")
	check(ntext() == "Mining 113" and nactive() == 1, "skill should update in place: " .. tostring(ntext()))
	advance(2)
	MOCK.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Your Stormwind reputation has increased by 25.")
	check(ntext() == "+25 Stormwind", "rep: " .. tostring(ntext()))
	advance(2)
	MOCK.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Your Defias Brotherhood reputation has decreased by 5.")
	check(ntext() == "-5 Defias Brotherhood", "rep loss: " .. tostring(ntext()))
	advance(2)
	ns.Notify:ReadXP()
	xp = 440; MOCK.Fire("PLAYER_XP_UPDATE", "player")
	check(ntext() == "+340 XP", "xp: " .. tostring(ntext()))
	advance(2)
	level, xp = 11, 60; MOCK.Fire("PLAYER_LEVEL_UP", 11); MOCK.Fire("PLAYER_XP_UPDATE", "player")
	settle()
	local all = {}
	for i = 1, nactive() do all[#all + 1] = ntext(i) end
	all = table.concat(all, " | ")
	check(all:find("Level 11", 1, true), "level up: " .. all)
	check(all:find("+620 XP", 1, true), "xp across a level: " .. all)
	advance(2)
	MOCK.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 12 honor points.")
	check(ntext() == "+12 Honor", "honor: " .. tostring(ntext()))
	advance(2)
	MOCK.Fire("UI_INFO_MESSAGE", 1, "Turtle Meat: 3/10")
	check(ntext() == "Turtle Meat: 3/10", "quest: " .. tostring(ntext()))
	advance(0.3)
	local n = nactive()
	MOCK.Fire("UI_INFO_MESSAGE", 1, "Turtle Meat: 4/10")
	check(ntext() == "Turtle Meat: 4/10" and nactive() == n, "quest progress should update its line")
	MOCK.Fire("UI_INFO_MESSAGE", 1, "Mailbox: you have mail") -- not a quest message
	check(nactive() == n, "non-quest info shown")
	advance(2)
	MOCK.Fire("UI_ERROR_MESSAGE", 3, "Inventory is full.")
	check(ntext() == "Inventory is full.", "bags full: " .. tostring(ntext()))
	advance(1)
	MOCK.Fire("UI_ERROR_MESSAGE", 3, "Inventory is full.")
	check(nactive() == n + 1, "bags full repeated too often")
	SlashCmdList.WHACK("rep off")
	advance(2)
	MOCK.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Your Stormwind reputation has increased by 25.")
	check(nactive() == n + 1, "rep shown while off")
	nclear()
end)

step("notify: secret messages and totals are never parsed or compared", function()
	-- a secret loot message: shown as it is only when the readable GUID says it's mine
	local guid = UnitGUID("player")
	MOCK.Fire("CHAT_MSG_LOOT", S("You receive loot: x."), "", "", "", "Tester", "", 0, 0, "", 0, 0, guid)
	check(nactive() == 1, "my secret loot not shown raw")
	local _, t = ntext()
	check(MOCK.isSecret(t.text:GetText()), "raw secret not shown as it is")
	MOCK.Fire("CHAT_MSG_LOOT", S("Member2 receives loot: x."), "", "", "", "Member2", "", 0, 0, "", 0, 0, "Player-1-Member2")
	MOCK.Fire("CHAT_MSG_LOOT", S("?"), "", "", "", S("?"), "", 0, 0, "", 0, 0, S(guid))
	check(nactive() == 1, "secret loot shown when it may not be mine")
	advance(2)
	SlashCmdList.WHACK("rep on")
	MOCK.Fire("CHAT_MSG_SKILL", S("Your skill in Mining has increased to 114."))
	MOCK.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", S("Your Stormwind reputation has increased by 25."))
	MOCK.Fire("UI_INFO_MESSAGE", 1, S("Turtle Meat: 5/10"))
	MOCK.Fire("UI_ERROR_MESSAGE", 3, S("Inventory is full."))
	settle()
	check(nactive() == 3, "secret skill/rep should show raw, quest/bags nothing; got " .. nactive())
	-- secret totals: no maths, no text, and the next readable total starts over
	local oldMoney, oldXP = GetMoney, UnitXP
	GetMoney = function() return S(money + 999) end
	UnitXP = function() return S(xp + 5) end
	MOCK.Fire("PLAYER_MONEY"); MOCK.Fire("PLAYER_XP_UPDATE", "player")
	GetMoney, UnitXP = oldMoney, oldXP
	money = money + 1; xp = xp + 1
	MOCK.Fire("PLAYER_MONEY"); MOCK.Fire("PLAYER_XP_UPDATE", "player")
	settle()
	check(nactive() == 3, "a secret total made text: " .. nactive())
	check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n"))
	nclear()
end)

step("notify: chat commands, test, reset, search, the window page", function()
	MOCK.log = {}
	SlashCmdList.WHACK("notify off")
	check(ns.db.areas.notify.enabled == false, "notify off")
	SlashCmdList.WHACK("notify test")
	check(MOCK.log[#MOCK.log]:find("/whack notify on", 1, true), "test while off should say how to turn it on")
	SlashCmdList.WHACK("notifications on")
	check(ns.db.areas.notify.enabled, "notifications on")
	SlashCmdList.WHACK("notify test")
	settle()
	check(nactive() >= 6, "test notifications: " .. nactive())
	nclear()
	SlashCmdList.WHACK("notify.fontsize 20")
	check(ns.db.areas.notify.fontSize == 20, "notify.fontsize")
	SlashCmdList.WHACK("reset notify"); SlashCmdList.WHACK("reset notify")
	check(ns.db.areas.notify.fontSize == 15 and ns.db.areas.notify.enabled == false and ns.db.notify.money == false
		and ns.db.notify.rep == false, "reset notify")
	check(not ns.app:GetSetting("notify.critscale") and not ns.app:GetSetting("notify.showmisses"), "hit-only options on notify")
	for _, word in ipairs({ "loot", "items", "skill", "profession", "reputation", "rep", "xp", "money", "gold", "quest" }) do
		local r = ns.app:Search(word)
		local hit
		for _, x in ipairs(r) do
			if x.entry.path:find("Notifications", 1, true) then hit = true end
		end
		check(hit, "search '" .. word .. "' doesn't find a notifications setting")
	end
	ns.app:Search("")
	ns.Options:ShowPage("notify")
	ns.Options:Refresh()
	ns.app:Close()
	-- unlock shows the notifications area too
	ns.Display:SetLocked(false)
	check(ns.Display:GetArea("notify").mover:IsShown(), "notify mover hidden while unlocked")
	ns.Display:SetLocked(true)
end)

step("no Lua errors reported", function()
	check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n"))
end)

print(("\n%d passed, %d failed"):format(passes, #failures))
return #failures

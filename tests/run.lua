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
	clear()
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

step("no taint: Blizzard globals left alone", function()
	local allowed = { WhackDB = true, SLASH_WHACK1 = true }
	for k in pairs(globalWrites) do
		check(allowed[k], "addon assigned the global " .. tostring(k))
	end
	check(next(UISpecialFrames) == nil, "addon added to UISpecialFrames")
	check(next(StaticPopupDialogs) == nil, "addon added to StaticPopupDialogs")
end)

step("no Lua errors reported", function()
	check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n"))
end)

print(("\n%d passed, %d failed"):format(passes, #failures))
return #failures

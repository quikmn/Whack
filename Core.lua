-- Whack: core (helpers, theme, settings, slash command).
local ADDON, ns = ...
ns.name = ADDON

local UI = LibStub("EverlookUI-1")
ns.UI = UI
local U = UI.Util
ns.Util = U

function ns:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffff9933Whack|r: " .. tostring(msg))
end

-- The shared EverlookUI look with Whack's orange accent (the movers use it too).
ns.ACCENT = { 1.000, 0.600, 0.200 }
ns.Theme = UI.MakeTheme(ns.ACCENT)

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
ns.FONTS = {
	{ value = "friz",     text = "Friz Quadrata (game default)", path = "Fonts\\FRIZQT__.TTF" },
	{ value = "arialn",   text = "Arial Narrow (clean)",         path = "Fonts\\ARIALN.TTF" },
	{ value = "skurri",   text = "Skurri (chunky)",              path = "Fonts\\SKURRI.TTF" },
	{ value = "morpheus", text = "Morpheus (fantasy)",           path = "Fonts\\MORPHEUS.TTF" },
}

local AREA = {
	enabled = true,
	x = 0, y = 0, width = 180, height = 260,
	style = "scroll",       -- scroll | arc | cascade | burst
	direction = "up",       -- up | down
	align = "center",       -- left | center | right
	font = "friz",
	fontSize = 18,
	critScale = 1.5,
	outline = "OUTLINE",    -- "" | OUTLINE | THICKOUTLINE
	shadow = true,          -- soft drop shadow behind the text (on top of the outline)
	showIcon = true,
	iconSide = "left",      -- left | right
	duration = 1.8,
	numberFormat = "short", -- short (12.3k) | full (12,345)
	colorSchool = true,
	showMisses = true,
	showHeals = true,       -- incoming only
	critBang = true,        -- outgoing crits get a "!"
	color = { 1, 1, 1 },    -- plain hits (outgoing white, incoming red); spell schools have their own colours
	healColor = { 0.35, 1, 0.45 }, -- incoming only
}

local function Area(over)
	local t = U.CopyTable(AREA)
	for k, v in pairs(over) do t[k] = v end
	return t
end

ns.DEFAULTS = {
	version = 1,
	locked = true,
	hideBlizzardDamage = true, -- the game's own damage numbers over your target, while Whack's outgoing area is on
	outgoingMode = "smart", -- smart | all
	maxActive = 40,         -- most texts on screen per area
	areas = {
		outgoing = Area({ x = 260, y = 40 }),
		incoming = Area({ x = -260, y = 40, direction = "down", fontSize = 16, critScale = 1.35, color = { 1, 0.25, 0.25 } }),
		-- loot, skill-ups and the rest (Notify.lua): off until you turn it on; calmer and slower than the hits
		notify = Area({ enabled = false, x = 0, y = 210, width = 320, height = 150, fontSize = 15, duration = 3,
			critScale = 1.3 }),
	},
	-- weapon procs (Procs.lua): a short "boom" in the middle-top of the screen when Fiery Weapon & co. go off
	procs = {
		enabled = true, -- the big splash
		sound = true, glow = true,
		scroll = true,  -- the proc's own hit in the outgoing text: bigger, named, school colour
		blink = true,   -- and it blinks as it scrolls
		size = 30, x = 0, y = 250,
	},
	-- what the notifications area shows (once it is on): loot and skill-ups, the rest when you tick them
	notify = {
		loot = true, quality = 0, money = false, currency = false,
		skill = true, rep = false, xp = false, honor = false, level = false,
		quest = false, bagsFull = false,
	},
}
ns.AREA_DEFAULTS = AREA

function ns:ResetArea(key)
	ns.db.areas[key] = U.CopyTable(ns.DEFAULTS.areas[key])
	ns.Display:Layout(key)
end

------------------------------------------------------------------------
-- Boot
------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, event, name)
	if name ~= ADDON then return end
	self:UnregisterEvent("ADDON_LOADED")
	WhackDB = WhackDB or {}
	ns.db = U.FillDefaults(WhackDB, ns.DEFAULTS)
	ns.db.locked = true -- always start locked
	ns.Display:Init()
	ns.Combat:Init()
	ns.Procs:Init()
	ns.Notify:Init()
	self:RegisterEvent("PLAYER_LOGIN")
	self:RegisterEvent("PLAYER_LOGOUT")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:SetScript("OnEvent", function(_, ev)
		if ev == "PLAYER_LOGOUT" then ns.ApplyBlizzardDamage(true)
		elseif ev == "PLAYER_LOGIN" or ns.fctPending then ns.ApplyBlizzardDamage() end
	end)
end)

------------------------------------------------------------------------
-- Blizzard's floating damage numbers (the CVar floatingCombatTextCombatDamage): with Whack's outgoing area on they
-- would show every hit twice, so Whack switches them off. What you had comes back when the setting or the outgoing
-- area is turned off, and at every logout (so with Whack disabled the game's numbers are there); the next login
-- switches them off again.
------------------------------------------------------------------------
local FCT = "floatingCombatTextCombatDamage"
local function getCVar(k)
	local f = (C_CVar and C_CVar.GetCVar) or GetCVar
	if not f then return nil end
	local ok, v = pcall(f, k)
	if ok and type(v) == "string" then return v end
	return nil
end
local function setCVar(k, v)
	local f = (C_CVar and C_CVar.SetCVar) or SetCVar
	if f then pcall(f, k, v) end
end
ns.FCT_CVAR = FCT

-- leaving: logging out (put the player's value back, remember to hide again next login).
function ns.ApplyBlizzardDamage(leaving)
	local db = ns.db
	if not db then return end
	if leaving then
		if db.savedFCT ~= nil then setCVar(FCT, db.savedFCT) end
		return
	end
	if InCombatLockdown and InCombatLockdown() then ns.fctPending = true return end
	ns.fctPending = nil
	local want = db.hideBlizzardDamage and db.areas.outgoing.enabled
	local now = getCVar(FCT)
	if want then
		if now == nil then return end -- this client has no such setting
		if db.savedFCT == nil then db.savedFCT = now end
		if now ~= "0" then setCVar(FCT, "0") end
	elseif db.savedFCT ~= nil then
		setCVar(FCT, db.savedFCT)
		db.savedFCT = nil
	end
end

-- Feedback link (opens in Whack's own small window; see EverlookUI.LinkWindow).
ns.FEEDBACK_URL = "https://everlookdb.com/whack.html#feedback"

function ns.ShowFeedback()
	return ns.app:ShowFeedback()
end

SLASH_WHACK1 = "/whack" -- ns.app:RegisterSlash would need the app, which Options.lua makes after this file
SlashCmdList.WHACK = function(msg) ns.app:HandleSlash(msg) end
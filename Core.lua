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
	outgoingMode = "smart", -- smart | all
	maxActive = 40,         -- most texts on screen per area
	areas = {
		outgoing = Area({ x = 260, y = 40 }),
		incoming = Area({ x = -260, y = 40, direction = "down", fontSize = 16, critScale = 1.35, color = { 1, 0.25, 0.25 } }),
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
end)

-- Feedback link (opens in Whack's own small window; see EverlookUI.LinkWindow).
ns.FEEDBACK_URL = "https://everlookdb.com/whack.html#feedback"

function ns.ShowFeedback()
	return ns.app:ShowFeedback()
end

SLASH_WHACK1 = "/whack"
SlashCmdList.WHACK = function(msg) ns.app:HandleSlash(msg) end
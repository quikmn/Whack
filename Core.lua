-- Whack: core (helpers, theme, settings, slash command).
local ADDON, ns = ...
ns.name = ADDON

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local U = {}
ns.Util = U
U.WHITE = "Interface\\Buttons\\WHITE8X8"

function U.CopyTable(src)
	if type(src) ~= "table" then return src end
	local t = {}
	for k, v in pairs(src) do t[k] = U.CopyTable(v) end
	return t
end

function U.FillDefaults(dst, defaults)
	for k, v in pairs(defaults) do
		if dst[k] == nil then
			dst[k] = U.CopyTable(v)
		elseif type(v) == "table" and type(dst[k]) == "table" then
			U.FillDefaults(dst[k], v)
		end
	end
	return dst
end

function U.Font() return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" end

function U.SetFont(fs, size, flags)
	local ok = fs:SetFont(U.Font(), size or 11, flags or "")
	if not ok then fs:SetFontObject(GameFontHighlightSmall) end
end

function U.Solid(parent, layer, r, g, b, a, sublevel)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
	t:SetTexture(U.WHITE)
	t:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
	return t
end

function U.Border(parent, size, r, g, b, a, layer)
	size = size or 1
	local border = {}
	local function edge()
		local t = parent:CreateTexture(nil, layer or "BORDER", nil, 7)
		t:SetTexture(U.WHITE)
		t:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
		return t
	end
	border.top = edge()
	border.top:SetPoint("TOPLEFT")
	border.top:SetPoint("TOPRIGHT")
	border.top:SetHeight(size)
	border.bottom = edge()
	border.bottom:SetPoint("BOTTOMLEFT")
	border.bottom:SetPoint("BOTTOMRIGHT")
	border.bottom:SetHeight(size)
	border.left = edge()
	border.left:SetPoint("TOPLEFT")
	border.left:SetPoint("BOTTOMLEFT")
	border.left:SetWidth(size)
	border.right = edge()
	border.right:SetPoint("TOPRIGHT")
	border.right:SetPoint("BOTTOMRIGHT")
	border.right:SetWidth(size)
	function border:SetColor(r2, g2, b2, a2)
		for _, key in ipairs({ "top", "bottom", "left", "right" }) do
			self[key]:SetVertexColor(r2, g2, b2, a2 or 1)
		end
	end
	return border
end

function ns:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffff9933Whack|r: " .. tostring(msg))
end

------------------------------------------------------------------------
-- Theme (same palette as Lattice)
------------------------------------------------------------------------
ns.Theme = {
	bg        = { 0.071, 0.078, 0.094, 0.97 },
	sidebar   = { 0.055, 0.060, 0.074, 1 },
	surface   = { 0.105, 0.114, 0.137, 1 },
	surfaceHi = { 0.137, 0.149, 0.180, 1 },
	border    = { 0.180, 0.196, 0.235, 1 },
	text      = { 0.902, 0.910, 0.933, 1 },
	muted     = { 0.553, 0.580, 0.639, 1 },
	accent    = { 1.000, 0.600, 0.200, 1 },
	accentDim = { 1.000, 0.600, 0.200, 0.18 },
	danger    = { 0.937, 0.365, 0.365, 1 },
	ok        = { 0.384, 0.812, 0.533, 1 },
	fontSmall = 10,
	font      = 12,
	fontTitle = 14,
	fontHuge  = 18,
	pad = 16,
	rowGap = 10,
}

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
	showIcon = true,
	iconSide = "left",      -- left | right
	duration = 1.8,
	numberFormat = "short", -- short (12.3k) | full (12,345)
	colorSchool = true,
	showMisses = true,
	showHeals = true,       -- incoming only
	critBang = true,        -- outgoing crits get a "!"
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
	areas = {
		outgoing = Area({ x = 260, y = 40 }),
		incoming = Area({ x = -260, y = 40, direction = "down", fontSize = 16, critScale = 1.35 }),
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

-- Feedback link. Addons can't open a browser, so show the link selected in a box to copy.
ns.FEEDBACK_URL = "https://everlookdb.com/whack.html#feedback"
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["WHACK_FEEDBACK"] = {
	text = "Report a bug or suggest an idea.\nPress Ctrl+C to copy the link, then paste it in your browser.",
	button1 = CLOSE or "Close",
	hasEditBox = true,
	editBoxWidth = 320,
	OnShow = function(self)
		local eb = self.EditBox or self.editBox
		if not eb then return end
		eb:SetText(ns.FEEDBACK_URL)
		eb:SetFocus()
		eb:HighlightText()
	end,
	EditBoxOnTextChanged = function(eb)
		if eb:GetText() ~= ns.FEEDBACK_URL then
			eb:SetText(ns.FEEDBACK_URL)
			eb:HighlightText()
		end
	end,
	EditBoxOnEnterPressed = function() StaticPopup_Hide("WHACK_FEEDBACK") end,
	EditBoxOnEscapePressed = function() StaticPopup_Hide("WHACK_FEEDBACK") end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function ns.ShowFeedback()
	StaticPopup_Show("WHACK_FEEDBACK")
end

SLASH_WHACK1 = "/whack"
SlashCmdList.WHACK = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "unlock" or msg == "lock" or msg == "move" then
		ns.Display:SetLocked(msg == "lock" or (msg == "move" and not ns.db.locked))
	elseif msg == "test" then
		ns.Combat:Test()
	elseif msg == "status" then
		ns.Combat:Status()
	elseif msg == "feedback" or msg == "bug" then
		ns.ShowFeedback()
	elseif msg == "help" then
		ns:Print("/whack - options, /whack unlock | lock - move the areas, /whack test - fake numbers, /whack status, /whack feedback - link for bugs and ideas")
	else
		ns.Options:Toggle()
	end
end

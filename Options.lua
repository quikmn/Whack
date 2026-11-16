-- Whack: options window (/whack).
local _, ns = ...
local U, T, W = ns.Util, ns.Theme, ns.Widgets
local O = {}
ns.Options = O

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end
local WIDTH, HEIGHT = 520, 600

local window
local tabs, pages = {}, {}
local current

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

------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------
local function BuildArea(stack, key)
	local function get(k) return function() return ns.db.areas[key][k] end end
	local function set(k) return function(v) ns.db.areas[key][k] = v; ns.Display:Layout(key) end end
	local function opt(k, extra)
		extra.get, extra.set = get(k), set(k)
		return extra
	end
	local outgoing = key == "outgoing"

	W.Header(stack, outgoing and "Outgoing" or "Incoming",
		outgoing and "Your auto attacks, wand shots and spells landing on your target."
			or "Damage and heals you take.")

	local row = CreateFrame("Frame")
	W.Button(row, "Show test numbers", function() ns.Combat:Test(key) end, 160, "accent"):SetPoint("LEFT")
	local reset = W.Button(row, "Reset this area", function()
		ns:ResetArea(key)
		O:Refresh()
	end, 140)
	reset:SetPoint("LEFT", 170, 0)
	stack:Add(row, 26, 14)

	W.Toggle(stack, opt("enabled", { label = "Show " .. key .. " text" }))

	W.Header(stack, "Motion")
	W.Dropdown(stack, opt("style", { label = "Style", items = STYLES, width = 300 }))
	W.Dropdown(stack, opt("direction", { label = "Direction", items = DIRECTIONS, width = 300,
		desc = "Which way scroll, arc and cascade texts travel. Burst ignores this." }))
	W.Slider(stack, opt("duration", { label = "Time on screen (seconds)", min = 0.6, max = 5, step = 0.1, fmt = "%.1f" }))

	W.Header(stack, "Text")
	W.Dropdown(stack, opt("font", { label = "Font", items = ns.FONTS, width = 300 }))
	W.Slider(stack, opt("fontSize", { label = "Font size", min = 8, max = 48 }))
	W.Slider(stack, opt("critScale", { label = "Critical hits: size multiplier", min = 1, max = 3, step = 0.05, fmt = "%.2f" }))
	W.Dropdown(stack, opt("outline", { label = "Outline", items = OUTLINES, width = 300 }))
	W.Toggle(stack, opt("shadow", { label = "Drop shadow behind the text",
		desc = "A soft shadow under the letters. With an outline as well the edges get heavier; turn it off for a cleaner, sharper look." }))
	W.Dropdown(stack, opt("align", { label = "Alignment inside the area", items = ALIGNS, width = 300 }))
	W.Dropdown(stack, opt("numberFormat", { label = "Numbers", items = NUMBERS, width = 300 }))
	W.Toggle(stack, opt("colorSchool", { label = "Colour by spell school (fire orange, shadow purple...)" }))
	W.Toggle(stack, opt("showMisses", { label = "Show misses, dodges, parries and resists" }))
	if outgoing then
		W.Toggle(stack, opt("critBang", { label = "Add \"!\" to critical hits" }))
	else
		W.Toggle(stack, opt("showHeals", { label = "Show heals you receive" }))
	end

	if outgoing then
		W.Header(stack, "Icon")
		W.Toggle(stack, opt("showIcon", { label = "Show the spell / weapon icon" }))
		W.Dropdown(stack, opt("iconSide", { label = "Icon position", items = SIDES, width = 300 }))
	end

	W.Header(stack, "Area", "Drag it on screen with Unlock (bottom left), or set it exactly here.")
	W.Slider(stack, opt("x", { label = "Horizontal position (0 = screen centre)", min = -1200, max = 1200 }))
	W.Slider(stack, opt("y", { label = "Vertical position", min = -700, max = 700 }))
	W.Slider(stack, opt("width", { label = "Width", min = 60, max = 600 }))
	W.Slider(stack, opt("height", { label = "Height (how far text travels)", min = 40, max = 700 }))
end

local function BuildGeneral(stack)
	W.Header(stack, "General")
	W.Dropdown(stack, {
		label = "Outgoing: whose hits to show", items = MODES, width = 320,
		get = function() return ns.db.outgoingMode end,
		set = function(v) ns.db.outgoingMode = v end,
		desc = "The game only tells addons that your target was hit, not by whom. Whack matches hits to your own swings and casts. Solo, everything on your target is shown either way.",
	})
	W.Note(stack, "How it knows what you hit: this client gives addons no combat log, so Whack watches hits on your target and pairs them with your own swings, wand shots and casts. Solo that is exact. In a group, \"Only mine\" drops hits it cannot pair with something you did, which also drops your damage-over-time ticks. Hits on mobs you are not targeting are not shown.")
	stack:Space(6)
	W.Note(stack, "Commands: /whack (this window), /whack unlock, /whack lock, /whack test, /whack status, /whack feedback")
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local function CreateWindow()
	local f = CreateFrame("Frame", "WhackOptionsWindow", UIParent)
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()

	local bg = U.Solid(f, "BACKGROUND", rgba(T.bg))
	bg:SetAllPoints()
	U.Border(f, 1, rgba(T.border))

	local title = W.Text(f, T.fontHuge, T.text)
	title:SetPoint("TOPLEFT", T.pad, -14)
	title:SetText("Whack|cffff9933!|r")
	local sub = W.Text(f, T.fontSmall, T.muted)
	sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
	sub:SetText("scrolling combat text")

	local close = CreateFrame("Button", nil, f)
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", -8, -8)
	local x = W.Text(close, T.fontTitle, T.muted)
	x:SetPoint("CENTER")
	x:SetText("x")
	close:SetScript("OnEnter", function() x:SetTextColor(rgba(T.text)) end)
	close:SetScript("OnLeave", function() x:SetTextColor(rgba(T.muted)) end)
	close:SetScript("OnClick", function() f:Hide() end)

	-- Tabs
	local order = { { "outgoing", "Outgoing" }, { "incoming", "Incoming" }, { "general", "General" } }
	for i, def in ipairs(order) do
		local id = def[1]
		local b = CreateFrame("Button", nil, f)
		b:SetSize(100, 28)
		b:SetPoint("TOPLEFT", T.pad + (i - 1) * 104, -46)
		b.bg = U.Solid(b, "BACKGROUND", rgba(T.surface))
		b.bg:SetAllPoints()
		b.bar = U.Solid(b, "ARTWORK", rgba(T.accent))
		b.bar:SetHeight(2)
		b.bar:SetPoint("BOTTOMLEFT")
		b.bar:SetPoint("BOTTOMRIGHT")
		b.text = W.Text(b, T.font, T.muted)
		b.text:SetPoint("CENTER")
		b.text:SetJustifyH("CENTER")
		b.text:SetText(def[2])
		b:SetScript("OnClick", function() O:ShowPage(id) end)
		tabs[id] = b
	end

	local content = CreateFrame("Frame", nil, f)
	content:SetPoint("TOPLEFT", T.pad, -88)
	content:SetPoint("BOTTOMRIGHT", -T.pad, 52)
	f.content = content

	local unlock = W.Button(f, "Unlock areas", function()
		ns.Display:SetLocked(not ns.db.locked)
	end, 140)
	unlock:SetPoint("BOTTOMLEFT", T.pad, 14)
	f.unlock = unlock
	local test = W.Button(f, "Test both", function() ns.Combat:Test() end, 120)
	test:SetPoint("LEFT", unlock, "RIGHT", 8, 0)
	local feedback = W.Button(f, "Feedback / report a bug", function() ns.ShowFeedback() end, 170)
	feedback:SetPoint("BOTTOMRIGHT", -T.pad, 14)

	f:SetScript("OnHide", function() W.ClosePopup() end)
	W.CloseOnEscape(f) -- not UISpecialFrames, see there
	return f
end

local BUILDERS = {
	outgoing = function(s) BuildArea(s, "outgoing") end,
	incoming = function(s) BuildArea(s, "incoming") end,
	general = BuildGeneral,
}

function O:ShowPage(id)
	W.ClosePopup()
	for pid, p in pairs(pages) do p.scroll:SetShown(pid == id) end
	if not pages[id] then
		local scroll = W.ScrollPage(window.content)
		local width = WIDTH - 2 * T.pad - 24 -- the scroll bar takes the right edge
		local stack = W.Stack(scroll.child, width)
		scroll.child:SetWidth(width)
		BUILDERS[id](stack)
		pages[id] = { scroll = scroll, stack = stack }
		scroll.UpdateBar()
	end
	for tid, b in pairs(tabs) do
		local on = tid == id
		b.bar:SetShown(on)
		b.text:SetTextColor(rgba(on and T.text or T.muted))
	end
	current = id
	pages[id].stack:RefreshAll()
end

function O:Refresh()
	if not window then return end
	window.unlock:SetText(ns.db.locked and "Unlock areas" or "Lock areas")
	if current and pages[current] then pages[current].stack:RefreshAll() end
end

function O:Toggle()
	window = window or CreateWindow()
	if window:IsShown() then window:Hide() return end
	window:Show()
	self:ShowPage(current or "outgoing")
	self:Refresh()
end

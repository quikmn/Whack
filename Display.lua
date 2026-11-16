-- Whack: the two text areas, their movers and the four animation styles.
--
-- Amounts from the game are "secret" in combat: we can hand them to
-- SetFormattedText / AbbreviateNumbers but never do math or comparisons on
-- them, and we never ask a secret-carrying string for its width. All layout
-- below uses only our own numbers (font size, area size, time).
local _, ns = ...
local U, T = ns.Util, ns.Theme
local D = {}
ns.Display = D

local MAX_ACTIVE = 40 -- default; the "Most texts on screen" option (ns.db.maxActive) overrides it
local areas = {}
local driver = CreateFrame("Frame")
driver:Hide()

local function cfg(key) return ns.db.areas[key] end

local function FontPath(id)
	for _, f in ipairs(ns.FONTS) do
		if f.value == id then return f.path end
	end
	return U.Font()
end

------------------------------------------------------------------------
-- Areas and movers
------------------------------------------------------------------------
local LABELS = { outgoing = "Outgoing (your hits)", incoming = "Incoming (hits on you)" }

local function SavePosition(a)
	local cx, cy = a:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if not (cx and ux) then return end
	local c = cfg(a.key)
	c.x = math.floor(cx - ux + 0.5)
	c.y = math.floor(cy - uy + 0.5)
	D:Layout(a.key)
	if ns.Options.Refresh then ns.Options:Refresh() end
end

function D:GetArea(key)
	local a = areas[key]
	if a then return a end
	a = CreateFrame("Frame", "WhackArea_" .. key, UIParent)
	a.key = key
	a.active = {}
	a.pool = {}
	a.spawned = 0
	a:SetFrameStrata("HIGH")
	a:SetMovable(true)
	a:SetClampedToScreen(true)

	local m = CreateFrame("Frame", nil, a)
	m:SetAllPoints()
	m:SetFrameLevel(a:GetFrameLevel() + 20)
	local bg = U.Solid(m, "BACKGROUND", T.accent[1], T.accent[2], T.accent[3], 0.18)
	bg:SetAllPoints()
	U.Border(m, 1, T.accent[1], T.accent[2], T.accent[3], 0.9)
	m.label = m:CreateFontString(nil, "OVERLAY")
	U.SetFont(m.label, 12, "OUTLINE")
	m.label:SetPoint("TOP", 0, -6)
	m.label:SetText(LABELS[key] or key)
	m.hint = m:CreateFontString(nil, "OVERLAY")
	U.SetFont(m.hint, 10, "OUTLINE")
	m.hint:SetPoint("BOTTOM", 0, 6)
	m.hint:SetTextColor(0.8, 0.8, 0.8, 1)
	m.hint:SetText("drag to move")
	m.arrow = m:CreateFontString(nil, "OVERLAY")
	U.SetFont(m.arrow, 20, "OUTLINE")
	m.arrow:SetPoint("CENTER")
	m:EnableMouse(true)
	m:RegisterForDrag("LeftButton")
	m:SetScript("OnDragStart", function() a:StartMoving() end)
	m:SetScript("OnDragStop", function()
		a:StopMovingOrSizing()
		SavePosition(a)
	end)
	m:Hide()
	a.mover = m

	areas[key] = a
	return a
end

local ARROWS = { up = "^", down = "v" }

function D:Layout(key)
	local a, c = self:GetArea(key), cfg(key)
	a:ClearAllPoints()
	a:SetPoint("CENTER", UIParent, "CENTER", c.x, c.y)
	a:SetSize(c.width, c.height)
	a.mover:SetShown(not ns.db.locked)
	a.mover.arrow:SetText(c.style == "burst" and "*" or ARROWS[c.direction] or "")
	a.mover.label:SetText((LABELS[key] or key) .. (c.enabled and "" or " - OFF"))
	a:SetShown(c.enabled or not ns.db.locked)
	if not c.enabled then self:Clear(key) end
end

function D:LayoutAll()
	for key in pairs(ns.db.areas) do self:Layout(key) end
end

function D:SetLocked(locked)
	ns.db.locked = locked and true or false
	self:LayoutAll()
	if not locked then ns:Print("Areas unlocked: drag them, then /whack lock (or the Lock button).") end
	if ns.Options.Refresh then ns.Options:Refresh() end
end

function D:Init()
	self:LayoutAll()
end

------------------------------------------------------------------------
-- Text objects
------------------------------------------------------------------------
local function Release(a, i)
	local t = table.remove(a.active, i)
	t:Hide()
	t:ClearAllPoints()
	a.pool[#a.pool + 1] = t
end

function D:Clear(key)
	local a = areas[key]
	if not a then return end
	for i = #a.active, 1, -1 do Release(a, i) end
end

local function Acquire(a)
	local t = table.remove(a.pool)
	if not t then
		t = CreateFrame("Frame", nil, a)
		t:SetSize(1, 1)
		t.text = t:CreateFontString(nil, "OVERLAY")
		t.text:SetWordWrap(false)
		t.icon = t:CreateTexture(nil, "OVERLAY")
		t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	t:Show()
	return t
end

local function FormatAmount(amount, how)
	local fn = how == "full" and BreakUpLargeNumbers or AbbreviateNumbers
	if fn then
		local ok, s = pcall(fn, amount)
		if ok and s ~= nil then return s end
	end
	return amount
end

-- Lay the text and icon out inside the text frame. Nothing here reads the
-- string's width, so it is safe with secret text.
local function Arrange(t, c, size, hasIcon)
	local text, icon = t.text, t.icon
	text:ClearAllPoints()
	icon:ClearAllPoints()
	local justify = c.align == "left" and "LEFT" or c.align == "right" and "RIGHT" or "CENTER"
	text:SetJustifyH(justify)
	local gap = 4
	local shift = 0
	if hasIcon then
		if justify == "LEFT" and c.iconSide == "left" then shift = size + gap end
		if justify == "RIGHT" and c.iconSide == "right" then shift = -(size + gap) end
	end
	text:SetPoint(justify, t, "CENTER", shift, 0)
	if hasIcon then
		icon:SetSize(size, size)
		if c.iconSide == "right" then
			icon:SetPoint("LEFT", text, "RIGHT", gap, 0)
		else
			icon:SetPoint("RIGHT", text, "LEFT", -gap, 0)
		end
		icon:Show()
	else
		icon:Hide()
	end
end

-- spec: { amount = <maybe secret>, fmt = "%s", text = "plain", color = {r,g,b},
--         icon = texture, crit = bool }
function D:Spawn(key, spec)
	local c = cfg(key)
	if not c or not c.enabled then return end
	local a = self:GetArea(key)
	if #a.active >= (ns.db.maxActive or MAX_ACTIVE) then Release(a, 1) end

	local t = Acquire(a)
	local size = math.floor(c.fontSize * (spec.crit and c.critScale or 1) + 0.5)
	if not t.text:SetFont(FontPath(c.font), size, c.outline or "") then
		t.text:SetFont(U.Font(), size, c.outline or "")
	end
	if c.shadow == false then
		t.text:SetShadowOffset(0, 0)
		t.text:SetShadowColor(0, 0, 0, 0)
	else
		t.text:SetShadowOffset(1, -1)
		t.text:SetShadowColor(0, 0, 0, 0.8)
	end
	local col = spec.color or { 1, 1, 1 }
	t.text:SetTextColor(col[1], col[2], col[3], 1)
	if spec.amount ~= nil then
		t.text:SetFormattedText(spec.fmt or "%s", FormatAmount(spec.amount, c.numberFormat))
	else
		t.text:SetText(spec.text or "")
	end
	local hasIcon = c.showIcon and spec.icon ~= nil
	if hasIcon then t.icon:SetTexture(spec.icon) end
	Arrange(t, c, size, hasIcon)

	a.spawned = a.spawned + 1
	t.born = GetTime()
	t.dur = c.duration
	t.crit = spec.crit
	t.lineH = math.floor(c.fontSize * 1.3 + 0.5)
	t.bump = 0
	t.slot = 0
	t.slotY = nil
	t.side = (a.spawned % 2 == 0) and 1 or -1
	t.jx = (math.random() - 0.5) * c.width * 0.6
	t.jy = (math.random() - 0.5) * c.height * 0.5
	a.active[#a.active + 1] = t

	self:MakeRoom(a, c)
	self:Place(a, c, t, t.born)
	driver:Show()
	return t
end

------------------------------------------------------------------------
-- Animation styles
------------------------------------------------------------------------
local function Travel(c, t) return math.max(0, c.height - t.lineH) end

-- How far along its path a scroll/arc text is, in pixels from the start edge.
local function Distance(c, t, now)
	local p = math.min(1, (now - t.born) / t.dur)
	return Travel(c, t) * p + t.bump
end

-- New text must not sit on top of the previous one: push older texts ahead.
function D:MakeRoom(a, c)
	local n = #a.active
	if c.style == "cascade" then
		for i = 1, n - 1 do a.active[i].slot = a.active[i].slot + 1 end
		return
	end
	if c.style ~= "scroll" and c.style ~= "arc" then return end
	local now = GetTime()
	local prev = Distance(c, a.active[n], now)
	for i = n - 1, 1, -1 do
		local t = a.active[i]
		local d = Distance(c, t, now)
		local need = prev + a.active[i + 1].lineH
		if d < need then
			t.bump = t.bump + (need - d)
			d = need
		end
		prev = d
	end
end

local function Fade(p, from)
	if p <= from then return 1 end
	return math.max(0, (1 - p) / (1 - from))
end

-- Returns false when the text is finished.
function D:Place(a, c, t, now)
	local age = now - t.born
	local p = age / t.dur
	if p >= 1 then return false end
	local half = c.height / 2
	local sign = c.direction == "down" and -1 or 1
	local baseX = c.align == "left" and -c.width / 2 or c.align == "right" and c.width / 2 or 0
	local x, y, alpha, scale = baseX, 0, 1, 1

	if c.style == "scroll" or c.style == "arc" then
		local d = Distance(c, t, now)
		if d > Travel(c, t) + t.lineH then return false end
		y = sign * (-half + t.lineH / 2 + d)
		if c.style == "arc" then
			local q = math.min(1, d / math.max(1, Travel(c, t)))
			x = x + t.side * c.width * 0.35 * math.sin(q * math.pi)
		end
		alpha = Fade(p, 0.7)
	elseif c.style == "cascade" then
		local target = t.slot * t.lineH
		if target > c.height - t.lineH then return false end
		t.slotY = t.slotY and (t.slotY + (target - t.slotY) * math.min(1, (now - (t.last or now)) * 14)) or target
		y = sign * (-half + t.lineH / 2 + t.slotY)
		alpha = Fade(p, 0.75)
	else -- burst
		x = (c.align == "center" and 0 or baseX) + t.jx
		y = t.jy + age * 12
		local pop = 1 - math.min(1, age / 0.12)
		scale = 1 + 0.6 * pop
		alpha = Fade(p, 0.6)
	end
	t.last = now

	if t.crit and c.style ~= "burst" then
		scale = scale * (1 + 0.45 * (1 - math.min(1, age / 0.15)))
	end
	t:SetScale(scale)
	t:ClearAllPoints()
	t:SetPoint("CENTER", a, "CENTER", x / scale, y / scale)
	t:SetAlpha(alpha)
	return true
end

driver:SetScript("OnUpdate", function()
	local now = GetTime()
	local any = false
	for key, a in pairs(areas) do
		local c = cfg(key)
		for i = #a.active, 1, -1 do
			if not D:Place(a, c, a.active[i], now) then Release(a, i) end
		end
		if #a.active > 0 then any = true end
	end
	if not any then driver:Hide() end
end)

function D:ActiveCount(key)
	local a = areas[key]
	return a and #a.active or 0
end

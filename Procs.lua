-- Whack: weapon procs. A short "boom" (splash, screen-edge glow, sound) when an enchant on your weapon goes off.
--
-- No combat log here, so a proc is pieced together from what the client does give:
--   * your weapons' enchants: the enchant ID in the item links of slots 16 and 17 (item:ID:enchantID:...), looked up
--     in ProcData.lua (generated from the client's tables by tools/gen_procs.py);
--   * "hit" procs (Fiery Weapon, Lifestealing, Demonslaying): a UNIT_COMBAT on your target in the enchant's school
--     (a wound, or a resist / immune / absorb of it) that lands just after one of your own hits connected, and that
--     none of your own casts waiting for their hit explains (a caster's Fireball stays a Fireball);
--   * "buff" procs (Crusader): the proc's aura showing up on you (UNIT_AURA, added or refreshed);
--   * "debuff" procs (Icy Weapon, Unholy Weapon): their aura showing up on your target from you, or a resist of it.
-- Amounts are never touched (they are secret in combat); aura data is only read when it is readable.
local _, ns = ...
local P = {}
ns.Procs = P

local MAINHAND, OFFHAND = 16, 17
local AFTER_HIT = 0.5   -- a proc lands within this of the hit that caused it
local MERGE = 0.3       -- procs this close together make one boom
local BOOM = 0.8        -- how long the splash lasts

-- a fitting built-in spell impact per school (file IDs that exist in this client: checked with ForeverMiner's list)
P.SOUNDS = {
	[1] = 569770,  -- holyimpactdduber (no physical procs so far)
	[2] = 569770,  -- holy: directdamage/holyimpactdduber
	[4] = 568461,  -- fire: fireballimpacta
	[8] = 568516,  -- nature: lightningboltimpact
	[16] = 569358, -- frost: iceblastimpact
	[32] = 569474, -- shadow: shadowfury_impact_base
	[64] = 569631, -- arcane: arcanemissileimpact1a
}

-- the schools each class has damage spells in: only those classes' casts can explain a hit of that school
local CLASS_SCHOOLS = {
	MAGE = { [4] = true, [16] = true, [64] = true },
	WARLOCK = { [4] = true, [32] = true },
	PRIEST = { [2] = true, [32] = true },
	SHAMAN = { [4] = true, [8] = true, [16] = true },
	DRUID = { [8] = true, [64] = true },
	PALADIN = { [2] = true },
	HUNTER = { [4] = true, [8] = true, [64] = true, [16] = true },
	ROGUE = { [8] = true },
	WARRIOR = {},
}

local function readable(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end
local function num(v) if readable(v) and type(v) == "number" then return v end end

------------------------------------------------------------------------
-- Your weapons
------------------------------------------------------------------------
P.equipped = {}   -- [slot] = enchant definition
local bySchool = {} -- hit / debuff procs by school
local bySpell = {}  -- buff / debuff procs by aura spell ID

local function EnchantOf(slot)
	local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
	if not readable(link) or type(link) ~= "string" then return nil end
	return tonumber(link:match("item:%-?%d+:(%d+)"))
end

function P:ScanWeapons()
	wipe(self.equipped); wipe(bySchool); wipe(bySpell)
	local data = ns.PROC_ENCHANTS or {}
	for _, slot in ipairs({ MAINHAND, OFFHAND }) do
		local def = data[EnchantOf(slot) or 0]
		if def then
			self.equipped[slot] = def
			if def.kind ~= "buff" then bySchool[def.school] = def end
			if def.kind ~= "hit" then bySpell[def.spell] = def end
		end
	end
end

function P:HasAny() return next(self.equipped) ~= nil end

-- Detection runs while there is something to show it for (the boom, or the outgoing text).
function P:Watching()
	return self:HasAny()
end

function P:Icon(def)
	if C_Spell and C_Spell.GetSpellTexture then
		local ok, tex = pcall(C_Spell.GetSpellTexture, def.spell)
		if ok and readable(tex) and tex and tex ~= 136235 then return tex end -- 136235: the "temp" icon
	end
	return def.icon
end

------------------------------------------------------------------------
-- Hit procs (called from Combat.lua's Flush)
------------------------------------------------------------------------
local lastHit -- when one of your own hits last connected (a swing, or a physical hit from one of your attacks)
local CAN_FAIL = { RESIST = true, IMMUNE = true, ABSORB = true }

-- Could this hit on your target be one of your procs? Returns its definition.
function P:Candidate(hit)
	local def = hit.school and bySchool[hit.school]
	if not def then return nil end
	if def.kind == "hit" and (hit.action == "WOUND" or CAN_FAIL[hit.action]) then return def end
	if def.kind == "debuff" and CAN_FAIL[hit.action] then return def end -- the slow itself makes no hit; a resist does
	return nil
end

-- Remember when your own melee hits connect (white swings, Heroic Strike and the like); wand shots don't proc.
function P:NoteHit(hit, src, channel)
	if not src or hit.action ~= "WOUND" or src == channel or src.wand then return end
	if src.melee or hit.school == 1 or hit.school == nil then lastHit = hit.t end
end

function P:IsProc(hit, def)
	if not lastHit or hit.t - lastHit > AFTER_HIT or lastHit - hit.t > 0.1 then return false end
	local _, class = UnitClass("player")
	local mine = readable(class) and type(class) == "string" and CLASS_SCHOOLS[class] or nil
	-- one of your casts that could be this hit (a wand's school is anything) is still waiting: it is that cast
	local waiting = ns.Combat:PendingCast(hit.t, function(cast)
		return cast.wand or mine == nil or mine[def.school] or false
	end)
	return not waiting
end

------------------------------------------------------------------------
-- Aura procs
------------------------------------------------------------------------
local known = {} -- [unit] = { [auraInstanceID] = { def, expires } }
known.player, known.target = {}, {}

local function Field(aura, k)
	local v = aura[k]
	if readable(v) then return v end
end

local function FromMe(aura)
	local mine = Field(aura, "isFromPlayerOrPlayerPet")
	if mine == true then return true end
	local src = Field(aura, "sourceUnit")
	return src == "player" or src == "pet"
end

local function AuraProc(unit, aura, isNew)
	if not readable(aura) or type(aura) ~= "table" then return end
	local id = num(Field(aura, "spellId"))
	local def = id and bySpell[id]
	if not def then return end
	if unit == "player" and def.kind ~= "buff" then return end
	if unit == "target" and (def.kind ~= "debuff" or not FromMe(aura)) then return end
	local inst = num(Field(aura, "auraInstanceID"))
	local expires = num(Field(aura, "expirationTime"))
	local old = inst and known[unit][inst]
	if inst then known[unit][inst] = { def = def, expires = expires } end
	if isNew or (old and expires and old.expires and expires > old.expires + 0.05) then
		P:Proc(def, GetTime())
	end
end

function P:OnAura(unit, info)
	if unit ~= "player" and unit ~= "target" then return end
	if not next(bySpell) then return end
	if not readable(info) or type(info) ~= "table" then return end -- a full update: nothing to tell what is new
	if Field(info, "isFullUpdate") then wipe(known[unit]) return end
	local added = Field(info, "addedAuras")
	if type(added) == "table" then
		for _, aura in ipairs(added) do AuraProc(unit, aura, true) end
	end
	local updated = Field(info, "updatedAuraInstanceIDs")
	if type(updated) == "table" and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
		for _, inst in ipairs(updated) do
			inst = num(inst)
			if inst and known[unit][inst] then
				local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, inst)
				if ok then AuraProc(unit, aura, false) end
			end
		end
	end
	local removed = Field(info, "removedAuraInstanceIDs")
	if type(removed) == "table" then
		for _, inst in ipairs(removed) do
			inst = num(inst)
			if inst then known[unit][inst] = nil end
		end
	end
end

------------------------------------------------------------------------
-- Counting
------------------------------------------------------------------------
P.count = 0
P.byName = {}
local combatSince, combatTime = nil, 0

local function CombatSeconds()
	return combatTime + (combatSince and (GetTime() - combatSince) or 0)
end

-- A proc happened: count it and boom (procs within MERGE of each other make one boom).
function P:Proc(def, t)
	self.count = self.count + 1
	self.byName[def.name] = (self.byName[def.name] or 0) + 1
	self:Boom(def, t or GetTime())
end

function P:Status()
	local names = {}
	for _, d in pairs(self.equipped) do names[#names + 1] = d.name end
	table.sort(names)
	local secs = CombatSeconds()
	local rate = secs >= 1 and ("%.1f per minute in combat"):format(self.count * 60 / secs) or "no combat yet"
	ns:Print(("weapon procs: %s; %d this session (%s)%s"):format(
		#names > 0 and table.concat(names, ", ") or "no proc enchant on your weapons",
		self.count, rate, ns.db.procs.enabled and "" or ", boom off"))
end

------------------------------------------------------------------------
-- The boom: splash in the middle-top, a soft glow on the screen edges, a sound
------------------------------------------------------------------------
local splash, edge, driver

local function Upper(s) return (s:upper()) end

local function MakeSplash()
	splash = CreateFrame("Frame", "WhackProcSplash", UIParent)
	splash:SetFrameStrata("HIGH")
	splash:SetSize(400, 80)
	splash:SetMovable(true)
	splash:SetClampedToScreen(true)
	splash.content = CreateFrame("Frame", nil, splash)
	splash.content:SetSize(400, 80)
	splash.content:SetPoint("CENTER")
	local c = splash.content
	c.burst = c:CreateTexture(nil, "BACKGROUND")
	c.burst:SetTexture("Interface\\Cooldown\\starburst")
	c.burst:SetBlendMode("ADD")
	c.burst:SetPoint("CENTER")
	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	c.text = c:CreateFontString(nil, "OVERLAY")
	c.text:SetWordWrap(false)
	c:SetAlpha(0)

	local m = CreateFrame("Frame", nil, splash)
	m:SetAllPoints()
	m:SetFrameLevel(splash:GetFrameLevel() + 20)
	local T = ns.Theme
	local bg = ns.Util.Solid(m, "BACKGROUND", T.accent[1], T.accent[2], T.accent[3], 0.18)
	bg:SetAllPoints()
	ns.Util.Border(m, 1, T.accent[1], T.accent[2], T.accent[3], 0.9)
	m.label = m:CreateFontString(nil, "OVERLAY")
	ns.Util.SetFont(m.label, 12, "OUTLINE")
	m.label:SetPoint("CENTER")
	m.label:SetText("Weapon proc boom - drag to move")
	m:EnableMouse(true)
	m:RegisterForDrag("LeftButton")
	m:SetScript("OnDragStart", function() splash:StartMoving() end)
	m:SetScript("OnDragStop", function()
		splash:StopMovingOrSizing()
		local cx, cy = splash:GetCenter()
		local ux, uy = UIParent:GetCenter()
		if cx and ux then
			ns.db.procs.x = math.floor(cx - ux + 0.5)
			ns.db.procs.y = math.floor(cy - uy + 0.5)
		end
		P:Layout()
		if ns.Options.Refresh then ns.Options:Refresh() end
	end)
	m:Hide()
	splash.mover = m

	-- the screen-edge glow: the game's own full-screen vignette, greyed and tinted to the school's colour
	edge = CreateFrame("Frame", "WhackProcGlow", UIParent)
	edge:SetFrameStrata("BACKGROUND")
	edge:SetAllPoints(UIParent)
	edge.tex = edge:CreateTexture(nil, "BACKGROUND")
	edge.tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
	edge.tex:SetDesaturated(true)
	edge.tex:SetBlendMode("ADD")
	edge.tex:SetAllPoints()
	edge:SetAlpha(0)
	edge:Hide()

	driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", function() P:Animate(GetTime()) end)
end

function P:Layout()
	if not splash then MakeSplash() end
	local c = ns.db.procs
	splash:ClearAllPoints()
	splash:SetPoint("CENTER", UIParent, "CENTER", c.x, c.y)
	local size = c.size
	splash:SetSize(math.max(260, size * 12), size * 2.6)
	splash.content:SetSize(math.max(260, size * 12), size * 2.6)
	local ct = splash.content
	if not ct.text:SetFont(ns.Util.Font(), size, "THICKOUTLINE") then ct.text:SetFont("Fonts\\FRIZQT__.TTF", size, "THICKOUTLINE") end
	ct.text:SetShadowOffset(2, -2)
	ct.text:SetShadowColor(0, 0, 0, 0.9)
	ct.icon:SetSize(size * 1.5, size * 1.5)
	ct.burst:SetSize(size * 7, size * 3.2)
	splash.mover:SetShown(not ns.db.locked)
	splash.mover.label:SetText("Weapon proc boom" .. (c.enabled and "" or " - OFF") .. " - drag to move")
	splash:Show()
end

-- Text and icon side by side, centred together (the text is our own, so its width can be read).
local function Arrange(ct, size)
	ct.text:ClearAllPoints()
	ct.icon:ClearAllPoints()
	local w = ct.text:GetStringWidth() or 0
	local iw, gap = size * 1.5, size * 0.3
	local total = iw + gap + w
	ct.icon:SetPoint("LEFT", ct, "CENTER", -total / 2, 0)
	ct.text:SetPoint("LEFT", ct.icon, "RIGHT", gap, 0)
end

local boom -- { def, born, n }

function P:Boom(def, t)
	local c = ns.db.procs
	if not c.enabled then return end
	if not splash then self:Layout() end
	local now = GetTime()
	if boom and now - boom.last < MERGE then
		-- merged: one boom; the same proc twice (both weapons) says x2, a re-pop shows it took
		boom.last = now
		if boom.def == def then
			boom.n = boom.n + 1
		else
			boom.def, boom.n = def, 1
		end
		boom.repop = now
		self:Paint()
		return
	end
	boom = { def = def, born = now, last = now, n = 1 }
	self.booms = (self.booms or 0) + 1
	self:Paint()
	if c.glow then
		local col = ns.Combat.SCHOOL[def.school] or { 1, 1, 1 }
		edge.tex:SetVertexColor(col[1], col[2], col[3], 1)
		edge:Show()
	end
	if c.sound and PlaySoundFile then
		pcall(PlaySoundFile, P.SOUNDS[def.school] or P.SOUNDS[4], "SFX")
	end
	driver:Show()
	self:Animate(now)
end

function P:Paint()
	local ct = splash.content
	local def = boom.def
	local col = ns.Combat.SCHOOL[def.school] or { 1, 1, 1 }
	ct.text:SetTextColor(col[1], col[2], col[3], 1)
	ct.text:SetText(Upper(def.name) .. "!" .. (boom.n > 1 and (" x" .. boom.n) or ""))
	ct.icon:SetTexture(self:Icon(def))
	ct.burst:SetVertexColor(col[1], col[2], col[3], 1)
	Arrange(ct, ns.db.procs.size)
end

-- scale-pop: 0.6 -> 1.25 in 0.08 s, settle to 1 by 0.18 s; hold; fade out over the last 0.35 s
function P:Animate(now)
	if not boom then driver:Hide() return end
	local age = now - boom.born
	local dur = BOOM + (boom.last - boom.born)
	if age >= dur then
		boom = nil
		splash.content:SetAlpha(0)
		edge:SetAlpha(0)
		edge:Hide()
		driver:Hide()
		return
	end
	local scale
	if age < 0.08 then scale = 0.6 + (1.25 - 0.6) * (age / 0.08)
	elseif age < 0.18 then scale = 1.25 - 0.25 * ((age - 0.08) / 0.1)
	else scale = 1 end
	if boom.repop then
		local q = (now - boom.repop) / 0.15
		if q >= 1 then boom.repop = nil else scale = scale * (1 + 0.15 * (1 - q)) end
	end
	local fadeFrom = dur - 0.35
	local alpha = age < fadeFrom and 1 or math.max(0, (dur - age) / 0.35)
	local ct = splash.content
	ct:SetScale(scale)
	ct:SetAlpha(alpha)
	ct.burst:SetAlpha(math.max(0, 0.8 * (1 - age / 0.45)))
	-- the edge glow: up fast, gone in half a second, soft
	local g = age < 0.08 and (age / 0.08) or math.max(0, 1 - (age - 0.08) / 0.45)
	edge:SetAlpha(0.45 * g)
end

function P:IsBooming() return boom ~= nil end

-- "/whack test proc": a fake one, with the proc on your weapon if you have one, else Fiery Weapon.
function P:Test()
	local def = self.equipped[MAINHAND] or self.equipped[OFFHAND] or (ns.PROC_ENCHANTS and ns.PROC_ENCHANTS[803])
	if not def then return end
	if not ns.db.procs.enabled then
		ns:Print("The proc boom is off: /whack proc on")
	end
	boom = nil
	self:Boom(def, GetTime())
	ns.Combat:Outgoing({ action = "WOUND", flag = "", amount = math.random(30, 60), school = def.school },
		{ icon = self:Icon(def), proc = def })
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
P.eventFrame = ev

function P:Init()
	self:Layout()
	self:ScanWeapons()
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	ev:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
	ev:RegisterUnitEvent("UNIT_AURA", "player", "target")
	ev:RegisterEvent("PLAYER_TARGET_CHANGED")
	ev:RegisterEvent("PLAYER_REGEN_DISABLED")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
end

ev:SetScript("OnEvent", function(_, event, a1, a2)
	if event == "UNIT_AURA" then
		P:OnAura(a1, a2)
	elseif event == "PLAYER_TARGET_CHANGED" then
		wipe(known.target)
	elseif event == "PLAYER_REGEN_DISABLED" then
		combatSince = GetTime()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if combatSince then combatTime = combatTime + (GetTime() - combatSince) end
		combatSince = nil
	else
		P:ScanWeapons()
	end
end)

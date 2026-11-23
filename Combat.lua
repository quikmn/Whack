-- Whack: turning game events into numbers.
--
-- This client gives addons no combat log. What it does give:
--   UNIT_COMBAT(unit, action, flagText, amount, schoolMask) for the player
--   and for the target; the amount is secret, everything else is readable.
--   PLAYER_SWING(duration, swingType) when you auto-attack (melee or ranged).
--   UNIT_SPELLCAST_SUCCEEDED / CHANNEL_START / CHANNEL_STOP for your casts.
-- Incoming = UNIT_COMBAT on "player".
-- Outgoing = UNIT_COMBAT on "target", matched against your own swings and
-- casts so the right icon shows, and so other people's hits are left out
-- when you are in a group ("smart" mode).
local _, ns = ...
local C = {}
ns.Combat = C

local MAINHAND, OFFHAND, RANGED = 16, 17, 18
local SWING_WINDOW = 0.45   -- a swing and its hit report land within this
local CAST_WINDOW = 2.2     -- a cast and its hit (incl. travel time)
local DEFER = 0.05          -- wait this long so same-frame events are all seen
local WAND_SPELLS = { [5019] = true, [75] = true } -- Shoot (wand), Auto Shot

local SCHOOL = {
	[1] = { 1.00, 1.00, 1.00 },  -- physical
	[2] = { 1.00, 0.90, 0.45 },  -- holy
	[4] = { 1.00, 0.50, 0.15 },  -- fire
	[8] = { 0.45, 1.00, 0.35 },  -- nature
	[16] = { 0.50, 0.85, 1.00 }, -- frost
	[32] = { 0.72, 0.45, 1.00 }, -- shadow
	[64] = { 1.00, 0.55, 1.00 }, -- arcane
}
local WHITE = { 1, 1, 1 }
local HURT = { 1, 0.25, 0.25 }
local HEAL = { 0.35, 1, 0.45 }
local GREY = { 0.7, 0.7, 0.7 }

local MISS = {
	MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", RESIST = "Resist",
	IMMUNE = "Immune", EVADE = "Evade", ABSORB = "Absorbed", DEFLECT = "Deflect", REFLECT = "Reflect",
}
local PARTIAL = { GLANCING = "glancing", CRUSHING = "crushing", ABSORB = "absorbed", BLOCK = "blocked", RESIST = "resisted" }

C.SCHOOL, C.MISS = SCHOOL, MISS

local function readable(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end
local function str(v) if readable(v) and type(v) == "string" then return v end return "" end
local function num(v) if readable(v) and type(v) == "number" then return v end return nil end

-- A hit with the absorb flag whose amount is secret (in combat): "Absorbed" when nothing got through, else
-- "Absorbed (-123)". The amount can't be compared, so the game's C_StringUtil does it: TruncateWhenZero gives "" for
-- 0, WrapString adds the brackets only around a non-empty number. nil when the client lacks them (old text then).
local function AbsorbedText(amount, minus)
	local SU = C_StringUtil
	if not (SU and SU.TruncateWhenZero and SU.WrapString) then return nil end
	local ok, digits = pcall(SU.TruncateWhenZero, amount)
	if not ok or digits == nil then return nil end
	local ok2, tail = pcall(SU.WrapString, digits, minus and " (-" or " (", ")")
	if not ok2 or tail == nil then return nil end
	local ok3, text = pcall(SU.WrapString, "Absorbed", nil, tail)
	if not ok3 or text == nil then return nil end
	return text
end
C.AbsorbedText = AbsorbedText

local function SchoolColor(c, school, fallback)
	if c.colorSchool and school and SCHOOL[school] then return SCHOOL[school] end
	return fallback
end

------------------------------------------------------------------------
-- Your recent actions
------------------------------------------------------------------------
local swings, casts = {}, {}
local channel -- { icon = ..., until = time }

local function Prune(list, now, window)
	for i = #list, 1, -1 do
		if now - list[i].t > window or list[i].used then table.remove(list, i) end
	end
end

local function SlotIcon(slot)
	return GetInventoryItemTexture and GetInventoryItemTexture("player", slot) or nil
end

local function SpellIcon(id)
	if C_Spell and C_Spell.GetSpellTexture then
		local ok, tex = pcall(C_Spell.GetSpellTexture, id)
		if ok then return tex end
	end
	if GetSpellTexture then return GetSpellTexture(id) end
end

local function IsHarmful(id)
	if C_Spell and C_Spell.IsSpellHarmful then
		local ok, harmful = pcall(C_Spell.IsSpellHarmful, id)
		if ok and readable(harmful) then return harmful and true or false end
	end
	return UnitExists("target") and UnitCanAttack("player", "target")
end

local function RecentWand(now)
	for i = #casts, 1, -1 do
		local e = casts[i]
		if e.wand and math.abs(now - e.t) < 0.3 then return true end
	end
	return false
end

function C:OnSwing(swingType)
	local now = GetTime()
	if swingType == 2 or swingType == "Ranged" then
		-- wand / bow shot: treat like a cast so it matches spell-school hits too
		if not RecentWand(now) then
			casts[#casts + 1] = { t = now, icon = SlotIcon(RANGED), wand = true }
		end
		return
	end
	local slot = (swingType == 1 or swingType == "OffHand") and OFFHAND or MAINHAND
	swings[#swings + 1] = { t = now, icon = SlotIcon(slot), melee = true }
	if #swings > 8 then table.remove(swings, 1) end
end

function C:OnCast(spellID)
	spellID = num(spellID)
	if not spellID then return end
	local now = GetTime()
	if WAND_SPELLS[spellID] then
		if not RecentWand(now) then
			casts[#casts + 1] = { t = now, icon = SlotIcon(RANGED) or SpellIcon(spellID), wand = true }
		end
		return
	end
	if not IsHarmful(spellID) then return end
	casts[#casts + 1] = { t = now, icon = SpellIcon(spellID) }
	if #casts > 8 then table.remove(casts, 1) end
end

-- Find which of your actions a hit on the target belongs to.
-- Returns a source table ({ icon = ... }) or nil when it is not yours.
function C:Attribute(hit)
	local now = hit.t
	Prune(swings, now, SWING_WINDOW + DEFER)
	Prune(casts, now, CAST_WINDOW + DEFER)

	local function take(list, window)
		for _, e in ipairs(list) do
			if not e.used and math.abs(now - e.t) <= window then
				e.used = true
				return e
			end
		end
	end

	local physical = hit.school == 1 or hit.school == nil
	local src
	if physical then
		src = take(swings, SWING_WINDOW) or take(casts, CAST_WINDOW)
	else
		src = take(casts, CAST_WINDOW)
		if not src and channel and now <= channel.till then src = channel end
		if not src then src = take(swings, SWING_WINDOW) end
	end
	return src
end

-- Is one of your casts still waiting for its hit? Weapon procs (Procs.lua) ask before taking a hit of their school:
-- a caster's own Fireball must stay a Fireball. school: the hit's school; fits(cast) says if the cast could be it.
function C:PendingCast(now, fits)
	for _, e in ipairs(casts) do
		if not e.used and math.abs(now - e.t) <= CAST_WINDOW and fits(e) then return true end
	end
	return false
end

------------------------------------------------------------------------
-- Building the text
------------------------------------------------------------------------
-- A weapon proc's hit: bigger, in its school colour, with its name ("Fiery Weapon 40"), blinking as it scrolls.
local function ProcSpec(c, hit, spec, proc)
	local name = proc.name:gsub("%%", "%%%%")
	spec.color = SCHOOL[proc.school] or spec.color
	spec.scale = 1.35
	spec.blink = ns.db.procs.blink
	if hit.action ~= "WOUND" then
		spec.text = proc.name .. " " .. (MISS[hit.action] or ""):lower()
		return
	end
	spec.amount = hit.amount
	spec.fmt = name .. " %s" .. ((spec.crit and c.critBang) and "!" or "")
end

function C:Outgoing(hit, src)
	local c = ns.db.areas.outgoing
	local flag = hit.flag
	local crit = flag == "CRITICAL"
	local spec = { crit = crit, icon = src and src.icon }
	if src and src.proc and ns.db.procs.scroll then
		ProcSpec(c, hit, spec, src.proc)
		ns.Display:Spawn("outgoing", spec)
		return
	end
	if hit.action == "WOUND" then
		spec.color = SchoolColor(c, hit.school, c.color or WHITE)
		local amt = num(hit.amount)
		local absorbed = amt == nil and flag == "ABSORB" and AbsorbedText(hit.amount, false)
		if amt == 0 and PARTIAL[flag] then
			spec.text = MISS[flag] or PARTIAL[flag]
			spec.color = GREY
		elseif absorbed then
			spec.raw = absorbed
		else
			spec.amount = hit.amount
			if crit then
				spec.fmt = c.critBang and "%s!" or "%s"
			elseif PARTIAL[flag] then
				spec.fmt = "%s (" .. PARTIAL[flag] .. ")"
			end
		end
	else
		if not c.showMisses then return end
		spec.text = MISS[hit.action]
		spec.color = GREY
		spec.crit = false
	end
	ns.Display:Spawn("outgoing", spec)
end

function C:Incoming(action, flag, amount, school)
	local c = ns.db.areas.incoming
	local crit = flag == "CRITICAL" or flag == "CRUSHING"
	local spec = { crit = crit }
	if action == "WOUND" then
		local amt = num(amount)
		local absorbed = amt == nil and flag == "ABSORB" and AbsorbedText(amount, true)
		if amt == 0 and PARTIAL[flag] then
			spec.text = MISS[flag] or PARTIAL[flag]
			spec.color = GREY
		elseif absorbed then
			spec.raw = absorbed
			spec.color = GREY
		else
			spec.amount = amount
			local hurt = c.color or HURT
			spec.color = (school and school ~= 1) and SchoolColor(c, school, hurt) or hurt
			spec.fmt = PARTIAL[flag] and flag ~= "CRUSHING" and ("-%s (" .. PARTIAL[flag] .. ")") or "-%s"
		end
	elseif action == "HEAL" then
		if not c.showHeals then return end
		spec.amount = amount
		spec.fmt = "+%s"
		spec.color = c.healColor or HEAL
	elseif MISS[action] then
		if not c.showMisses then return end
		spec.text = MISS[action]
		spec.color = GREY
		spec.crit = false
	else
		return
	end
	ns.Display:Spawn("incoming", spec)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local pending = {}
local flushQueued = false

local function yes(v) return readable(v) and v == true end

-- Is someone else fighting your target? Solo, the game still reports their hits on it. Two signs, both readable
-- outside instances: the target is tapped by someone else, or it is attacking another player (not you, not your
-- pet). Unknown (secret) counts as no.
function C:OthersOnTarget()
	if UnitIsTapDenied then
		local ok, denied = pcall(UnitIsTapDenied, "target")
		if ok and yes(denied) then return true end
	end
	if UnitExists and yes(UnitExists("targettarget")) then
		local me = UnitIsUnit("targettarget", "player")
		local pet = UnitIsUnit("targettarget", "pet")
		if readable(me) and readable(pet) and not me and not pet and yes(UnitIsPlayer("targettarget")) then return true end
	end
	return false
end

local function Flush()
	flushQueued = false
	local list = pending
	pending = {}
	local mode = ns.db.outgoingMode
	local grouped = IsInGroup and IsInGroup()
	-- A hit none of your swings or casts explains (a damage-over-time tick, your pet): solo it is yours, unless someone
	-- else is fighting your target. In a group "Only mine" drops it.
	local soloMine = not grouped and not C:OthersOnTarget()
	local P = ns.Procs
	-- Two passes: first every ordinary hit (so a white hit that arrives with its proc is matched first and counts as
	-- a landed hit), then the hits that could be a weapon proc.
	for _, hit in ipairs(list) do
		hit.procDef = P:Candidate(hit)
		if not hit.procDef then
			hit.src = C:Attribute(hit)
			P:NoteHit(hit, hit.src, channel)
		end
	end
	-- The hit's school hidden (a secret in combat): a second hit that came with one of your own landed hits, and that
	-- no swing or cast of yours explains, is your damage proc (Procs.lua decides if you have one).
	for _, hit in ipairs(list) do
		if not hit.procDef and not hit.src and hit.schoolHidden and hit.action == "WOUND" then
			hit.procDef = P:HiddenSchoolCandidate(hit)
		end
	end
	for _, hit in ipairs(list) do
		if hit.procDef then
			if P:IsProc(hit, hit.procDef) then
				hit.src = { icon = P:Icon(hit.procDef), proc = hit.procDef }
				P:Proc(hit.procDef, hit.t)
			else
				hit.src = C:Attribute(hit)
			end
		end
	end
	if P.Debug then for _, hit in ipairs(list) do P:Debug(hit) end end
	if not ns.db.areas.outgoing.enabled then return end
	for _, hit in ipairs(list) do
		if hit.src or mode == "all" or soloMine then
			C:Outgoing(hit, hit.src)
		end
	end
end
C.Flush = Flush

local seen = { player = 0, target = 0, other = 0, swing = 0, cast = 0 }
C.seen = seen

function C:OnUnitCombat(unit, action, flag, amount, school)
	local bucket = (unit == "player" or unit == "target") and unit or "other"
	seen[bucket] = seen[bucket] + 1
	action = str(action)
	flag = str(flag)
	local schoolHidden = school ~= nil and not readable(school)
	school = num(school)
	if unit == "player" then
		if ns.db.areas.incoming.enabled then self:Incoming(action, flag, amount, school) end
		return
	end
	if unit ~= "target" or not (ns.db.areas.outgoing.enabled or ns.Procs:Watching()) then return end
	if action ~= "WOUND" and not MISS[action] then return end
	if UnitIsUnit and UnitIsUnit("target", "player") then return end
	pending[#pending + 1] = { t = GetTime(), action = action, flag = flag, amount = amount, school = school, schoolHidden = schoolHidden }
	if not flushQueued then
		flushQueued = true
		C_Timer.After(DEFER, Flush)
	end
end

local ev = CreateFrame("Frame")
C.eventFrame = ev

function C:Init()
	ev:RegisterEvent("UNIT_COMBAT")
	ev:RegisterEvent("PLAYER_SWING")
	ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
	ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
	ev:RegisterEvent("PLAYER_TARGET_CHANGED")
end

ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
	if event == "UNIT_COMBAT" then
		C:OnUnitCombat(a1, a2, a3, a4, a5)
	elseif event == "PLAYER_SWING" then
		seen.swing = seen.swing + 1
		C:OnSwing(a2)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		seen.cast = seen.cast + 1
		C:OnCast(a3)
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		local id = num(a3)
		if id and IsHarmful(id) then
			channel = { icon = SpellIcon(id), till = GetTime() + 30 }
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if channel then channel.till = GetTime() + 0.3 end
	elseif event == "PLAYER_TARGET_CHANGED" then
		wipe(pending)
	end
end)

------------------------------------------------------------------------
-- Test and status
------------------------------------------------------------------------
local TEST_ICONS = {
	"Interface\\Icons\\Spell_Holy_HolySmite",
	"Interface\\Icons\\Spell_Shadow_ShadowWordPain",
	"Interface\\Icons\\INV_Wand_07",
	"Interface\\Icons\\Spell_Fire_FlameBolt",
	"Interface\\Icons\\INV_Sword_04",
}
local TEST_SCHOOLS = { 2, 32, 32, 4, 1 }

function C:TestOne(which)
	local i = math.random(#TEST_ICONS)
	local crit = math.random() < 0.2
	local amount = math.random(40, 400) * (crit and 2 or 1)
	if which ~= "incoming" then
		if math.random() < 0.1 then
			self:Outgoing({ action = "DODGE", flag = "" }, nil)
		else
			self:Outgoing({ action = "WOUND", flag = crit and "CRITICAL" or "", amount = amount, school = TEST_SCHOOLS[i] },
				{ icon = TEST_ICONS[i] })
		end
	end
	if which ~= "outgoing" then
		local r = math.random()
		if r < 0.25 then
			self:Incoming("HEAL", "", math.random(80, 300), 2)
		elseif r < 0.35 then
			self:Incoming("PARRY", "", 0, 1)
		else
			self:Incoming("WOUND", math.random() < 0.15 and "CRITICAL" or "", math.random(20, 180), math.random() < 0.7 and 1 or 32)
		end
	end
end

function C:Test(which)
	if self.testTicker then self.testTicker:Cancel() end
	local n = 0
	self.testTicker = C_Timer.NewTicker(0.22, function(tk)
		n = n + 1
		C:TestOne(which)
		if n >= 24 then tk:Cancel(); C.testTicker = nil end
	end)
end

function C:Status()
	ns:Print(("events seen since login - hits on you %d, hits on target %d, other units %d, your swings %d, your casts %d"):format(
		seen.player, seen.target, seen.other, seen.swing, seen.cast))
	ns:Print(("outgoing mode %s, in group %s, on screen now: outgoing %d, incoming %d"):format(
		ns.db.outgoingMode, tostring(IsInGroup and IsInGroup()),
		ns.Display:ActiveCount("outgoing"), ns.Display:ActiveCount("incoming")))
end

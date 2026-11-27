# Changelog

## v0.5.4 (2026-11-27)
- Whichever window you click now comes to the front.

## v0.5.3 (2026-11-26)
- Unlock areas: the Notifications box now starts under the weapon proc box instead of on top of it. If you never moved it, it moves there by itself.
- Settings search: the sidebar lights the page of the top result while you search.

## v0.5.2 (2026-11-26)
- Weapon procs page: the splash setting's description is shown in full (it was cut off with "...").

## v0.5.1 (2026-11-23)
- Weapon procs: found by their timing too when the game hides the damage type in combat.
- `/whack debug procs`: for two minutes, a chat line for every hit on your target and what Whack made of it.

## v0.5.0 (2026-11-23)
- Weapon procs go boom: when Fiery Weapon, Crusader, Lifestealing, Demonslaying, Icy Weapon, Unholy Weapon or another weapon enchant goes off, its name and icon pop up big in the middle-top of the screen ("FIERY WEAPON!"), with a short glow in its colour around the edges of the screen and a fitting sound: fiery for fire, icy for frost, dark for shadow, a chime for holy. Both weapons at once make one boom ("x2").
- The proc's own hit stands out in your outgoing text: bigger, in its colour, with its name ("Fiery Weapon 40"), and it blinks a few times as it scrolls.
- `/whack status` tells you which proc your weapons have and how many you had this session (and per minute in combat).
- A new Weapon procs page in the options: the splash, sound and glow on or off, the size, and where it shows (drag it with Unlock areas). From chat: `/whack proc off`, `/whack proc.sound off`, `/whack proc.size 40`; `/whack test proc` shows a fake one.

## v0.4.0 (2026-11-20)
- Settings window: switches, buttons and sliders use a softer shade of the accent colour, an on switch has a dark knob so it stands out, and boxes have cleaner rounded edges.

- Your hits no longer show twice: while Whack shows your outgoing hits, the game's own damage numbers over your target are switched off. A new setting on the General page (`/whack blizzarddamage off`) keeps them. Turning that setting or the outgoing area off, or logging out, gives you back the game's numbers as you had them.
- Solo, other players' hits on your target no longer show as yours. When someone else is fighting your target (it is tapped by them, or it attacks another player), Whack only shows the hits it can match to your own swings and spells. Your damage over time still shows when the target is fighting you.
- A hit that was fully absorbed (a shield, for one) now shows "Absorbed" instead of "-0 (absorbed)". A partly absorbed hit shows how much got through: "Absorbed (-57)".

## v0.3.0 (2026-11-18)

- Settings: an AI help button copies a description of every setting for an AI assistant, and `/whack apply` runs the commands it gives back.
- New **Notifications** area (off until you turn it on: `/whack notify on`, or the Notifications page): loot you get (icon, name in its quality colour, ×count; the same item within a second joins one line), skill-ups ("Mining 112"), and if you tick them money (with coin icons), currencies, reputation ("+25 Stormwind"), XP, honour, level up, quest progress and "Inventory is full". A minimum loot quality, its own place, motion and font, and a mass loot scrolls calmly instead of piling up. From chat: `/whack loot on`, `/whack rep on`, `/whack loot.quality uncommon`, `/whack notify test`, `/whack reset notify`.
- Chat commands now follow one pattern across all EverlookDB addons: `/whack help` (or `?`) lists them; `get` and `set <setting> <value>`; `/whack off outgoing.enabled`; `search <words>`; `status` and `version`; `/whack reset outgoing` asks first (type it again within 10 seconds); a mistyped command suggests the nearest one. `/whack move`, `lock` and `unlock` work as before.
- The settings window has a search box at the top: type to find any setting.

## v0.2.0 (2026-11-17)

- The options window has the new shared look: sections in a sidebar (Outgoing, Incoming, General), it remembers where you put it, and Whack has an entry under the game's Settings > AddOns that opens it. Every setting works from chat too: `/whack settings` lists them, `/whack outgoing.fontsize 20` sets one. New options: the colour of plain hits for each area, the colour of heals, and the most texts on screen per area (40, as before). `/whack reset outgoing|incoming`, `/whack help`.
- Options window: a proper scroll bar you can grab and drag, or click above or below it to jump a page. The mouse wheel no longer changes sliders, so scrolling down the page never changes a setting by accident (type a number in the box beside a slider for exact values). New Text option: Drop shadow behind the text (on by default, as before); turn it off for sharper numbers with an outline.
- `/whack feedback` and a Feedback button in the options show a link for reporting bugs and ideas.
- Fix: Whack could cause an error about a "secret number" in Blizzard windows (for example when closing the character window). Whack no longer touches Blizzard's pop-up dialogs or its Escape-to-close list. The feedback link now opens in a small Whack window, and Escape still closes the options window.
- Settings window: Escape closes an open dropdown list first, then the window; Escape in a text box puts the old text back; a number typed next to a slider snaps to the slider's steps; a Delete or Reset that asks for a second click no longer forgets it early.

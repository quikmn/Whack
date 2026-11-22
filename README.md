# Whack

Scrolling combat text for WoW Forever: your hits and the hits you take, where and how you want them.

## Use
- `/whack` opens the options (also under Settings > AddOns).
- `/whack unlock` lets you drag the text areas; `/whack lock` fixes them again.
- `/whack test` shows fake numbers so you can tune the look.
- `/whack test proc` shows a fake weapon proc.
- `/whack status` shows what it is doing.
- `/whack outgoing.fontsize 20` or `/whack set outgoing.fontsize 20` changes a setting from chat (`/whack get` lists them; `/whack outgoing.enabled off` switches an area off).
- `/whack reset outgoing` (or `incoming`) puts an area back to its defaults: type it twice within 10 seconds.
- `/whack search <words>` opens the options with the search box filled; `/whack version`; `/whack help` (or `?`) lists every command, and a mistyped one suggests the nearest.
- `/whack feedback` (or the Feedback button in the options) shows a link for reporting bugs and ideas.

## Features
- Two areas you can place anywhere: **Outgoing** (your auto attacks, wand shots and spells landing on your target) and **Incoming** (damage and heals you take).
- Several animations per area (scroll, arc, cascade, burst), with direction, font, size and alignment.
- Bigger critical hits (size multiplier), optional "!" on crits.
- Heals you receive can be shown or hidden.
- **Weapon procs**: when Fiery Weapon, Crusader, Lifestealing or another weapon enchant goes off, its name and icon pop up big in the middle of the screen, with a soft glow in its colour around the screen and a fitting sound (fiery for fire, icy for frost). Its hit shows bigger in your outgoing text, named ("Fiery Weapon 40") and blinking. `/whack status` counts your procs. Sound, glow, size and place are in the options (`/whack proc off` turns it off).
- Optional **Notifications** area: loot (icon, quality colour, ×count), skill-ups, and if you like money, currencies, reputation, XP, honour, level up, quest progress and bags full. `/whack notify on`, then `/whack loot on`, `/whack rep on`, ... pick what it shows.

## Install
WowUp: pick **World of Warcraft: Forever**, then Get Addons → Install from URL, and paste `https://github.com/quikmn/Whack`.

By hand: download the latest zip from Releases and unzip it into `World of Warcraft\_forever_\Interface\AddOns`.

## License

GPL-3.0-or-later (see LICENSE). Not affiliated with Blizzard Entertainment.

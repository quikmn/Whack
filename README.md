# Whack

Scrolling combat text for WoW Forever (interface 16001): your hits and the hits you take, where and how you want them.

Written from scratch. It embeds LibStub (public domain) to load EverlookUI, the settings-window library shared by these addons.

## Use
- `/whack` opens the options (also under Settings > AddOns).
- `/whack unlock` lets you drag the text areas; `/whack lock` fixes them again.
- `/whack test` shows fake numbers so you can tune the look.
- `/whack status` shows what it is doing.
- `/whack outgoing.fontsize 20` (any setting from `/whack settings`) changes a setting from chat; `/whack reset outgoing` puts an area back to its defaults; `/whack help` lists every command.
- `/whack feedback` (or the Feedback button in the options) shows a link for reporting bugs and ideas.

## Features
- Two areas you can place anywhere: **Outgoing** (your auto attacks, wand shots and spells landing on your target) and **Incoming** (damage and heals you take).
- Several animations per area (scroll, arc, cascade, burst), with direction, font, size and alignment.
- Bigger critical hits (size multiplier), optional "!" on crits.
- Heals you receive can be shown or hidden.

## Install
WowUp: pick **World of Warcraft: Forever**, then Get Addons → Install from URL, and paste `https://github.com/quikmn/Whack`.

By hand: download the latest zip from Releases and unzip it into `World of Warcraft\_forever_\Interface\AddOns`.

## License

GPL-3.0-or-later (see LICENSE). Not affiliated with Blizzard Entertainment.

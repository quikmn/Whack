# Changelog

## Unreleased

- The options window has the new shared look: sections in a sidebar (Outgoing, Incoming, General), it remembers where you put it, and Whack has an entry under the game's Settings > AddOns that opens it. Every setting works from chat too: `/whack settings` lists them, `/whack outgoing.fontsize 20` sets one. New options: the colour of plain hits for each area, the colour of heals, and the most texts on screen per area (40, as before). `/whack reset outgoing|incoming`, `/whack help`.
- Options window: a proper scroll bar you can grab and drag, or click above or below it to jump a page. The mouse wheel no longer changes sliders, so scrolling down the page never changes a setting by accident (type a number in the box beside a slider for exact values). New Text option: Drop shadow behind the text (on by default, as before); turn it off for sharper numbers with an outline.
- `/whack feedback` and a Feedback button in the options show a link for reporting bugs and ideas.
- Fix: Whack could cause an error about a "secret number" in Blizzard windows (for example when closing the character window). Whack no longer touches Blizzard's pop-up dialogs or its Escape-to-close list. The feedback link now opens in a small Whack window, and Escape still closes the options window.
- Settings window: Escape closes an open dropdown list first, then the window; Escape in a text box puts the old text back; a number typed next to a slider snaps to the slider's steps; a Delete or Reset that asks for a second click no longer forgets it early.

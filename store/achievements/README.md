# Achievements

Create these in the Play Console under **Play Games Services → Setup and management →
Achievements**, in this order, then put each one's ID next to its key in
`ACHIEVEMENTS` in `scripts/play_games.gd`. Keys without an ID are skipped.

| Key | Name | Description | Icon | Points | Type |
|---|---|---|---|---|---|
| `first_crown` | First Crown | Solve your first puzzle. | `first_crown.png` | 5 | Standard |
| `unaided` | On Your Own | Solve a puzzle without using a hint. | `unaided.png` | 10 | Standard |
| `hard` | Hard Win | Solve a Hard puzzle without using a hint. | `hard.png` | 25 | Standard |
| `big_board` | Full Court | Solve a 10×10 puzzle. | `big_board.png` | 15 | Standard |
| `weekly` | Weekly Winner | Solve a weekly challenge. | `weekly.png` | 20 | Standard |
| `streak_7` | Week of Crowns | Solve the daily puzzle 7 days in a row. | `streak_7.png` | 30 | Standard |
| `streak_30` | Monthly Monarch | Solve the daily puzzle 30 days in a row. | `streak_30.png` | 100 | Standard |
| `climb_10` | Base Camp | Clear 10 puzzles in one run of The Climb. | `climb_10.png` | 20 | Standard |
| `climb_25` | Summit | Clear 25 puzzles in one run of The Climb. | `climb_25.png` | 75 | Standard |
| `quick` | Quick Thinker | Solve a daily puzzle in under a minute without hints. | `quick.png` | 30 | Standard |
| `century` | Hundred Crowns | Solve 100 puzzles. | `century.png` | 50 | Standard |

All start **Revealed**. The points add up to 380 of the 1,000 Play Games allows,
leaving room for more later.

Names and descriptions can be translated in the Play Console, under each achievement's
translations; they aren't part of the game's own `.po` files.

The game checks every achievement against the saved progress after each solve and
when the player signs in, so progress made before an achievement existed still counts.

## Icons

`make_icons.py` redraws the SVGs and 512×512 PNGs (it needs `rsvg-convert`).

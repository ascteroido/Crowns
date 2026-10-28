# TODO

## Gaps
- [x] Save the board in progress (marks, timer, hints used) per puzzle
- [x] Touch controls for Android: double tap places a crown
- [x] Pause the timer when the window loses focus

## Puzzle quality
- [x] Difficulty grading: rate puzzles by the deduction steps a logic solver needs; offer Easy/Medium/Hard
- [x] Teaching hints: point out the next deduction instead of revealing a crown
- [ ] Boards up to 14×14 (on hold: generation takes seconds for Medium 12×12+ and minutes for Hard 13×13; see pre-made puzzles under Later)
- [x] Hard+ difficulty: puzzles that need the hardest deductions the hint system knows
- [x] Puzzle editor: draw regions, check for a single solution and grade it, share it as a code

## Daily and progress
- [x] The Climb (challenge mode): one life, no hints, puzzles ramp from 5×5 Easy to 10×10 Hard
- [x] Daily streaks and stats (current/longest streak, solves and average time per size)
- [x] Global leaderboards via Google Play Games
- [x] Daily archive to play past dailies
- [x] Daily reminder: optional Android notification so players keep their streak
- [x] Weekly challenge: one harder puzzle a week with its own leaderboard
- [x] Monthly calendar trophies: a crown on each solved day in the archive, and a badge for a fully solved month
- [x] Personal records: point out on the win panel when a solve beats the best for its size or difficulty
- [x] Speed mode: a short run of small boards against the clock
- [x] Solve history: a graph of recent solve times per size in Stats

## Google Play Games
- [x] Achievements: first Hard solve, 7-day streak, topping The Climb, a solve with no hints
- [x] Cloud save: stats, streaks and boards in progress follow the player to a new phone
- [ ] More achievements: perfect month, speed run under a minute, Hard+ solves, 100 dailies

## Reach
- [x] Web build for itch, playable in the browser
- [x] Puzzle codes: share or enter a seed so friends can play the same board
- [x] Right-to-left layout for Arabic and Hebrew translations
- [ ] More translations from native speakers (the game is ready for them)
- [ ] Steam or Flathub release for the desktop builds
- [x] Tablet and landscape layout: board on one side, controls on the other, for wide screens
- [x] Gamepad support: the keyboard cursor and marks on a controller (Steam Deck)

## Feel and polish
- [x] Redo (Ctrl+Shift+Z, and a button beside Undo)
- [x] Keyboard play: arrow keys to move, keys to place × and crown
- [ ] Pencil marks: a third mark (a dot) for "maybe a crown here"
- [x] Mistake check: say whether the board has an error so far, without a full hint (counts as a hint)
- [ ] Pinch to zoom on large boards on small phones
- [x] Win animation
- [x] Optional sound effects
- [x] Colour-blind support: region patterns setting
- [x] Untimed mode: a setting that hides the timer
- [x] Interactive tutorial: walk first-time players through the rules on a small board
- [x] Haptics: short vibration on Android when placing a crown and on a win
- [ ] Solve replay: watch a solve back move by move after winning

## Look and accessibility
- [x] Themes: a few colour palettes beyond light and dark, including high contrast, and custom colours
- [ ] Text size setting
- [ ] Screen reader labels for menus and buttons
- [x] Reduce motion setting: turn off the reveal, pop-ins and win wave
- [x] Android app icon variants to match the theme

## Later
- [ ] Pre-made puzzles: generate 11×11–14×14 boards offline and bundle them, so large sizes don't depend on generation speed

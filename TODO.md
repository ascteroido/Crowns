# TODO

## Gaps
- [x] Save the board in progress (marks, timer, hints used) per puzzle
- [x] Touch controls for Android: double tap places a crown
- [x] Pause the timer when the window loses focus

## Puzzle quality
- [x] Difficulty grading: rate puzzles by the deduction steps a logic solver needs; offer Easy/Medium/Hard
- [x] Teaching hints: point out the next deduction instead of revealing a crown
- [x] Boards up to 14×14 (11×11 to 14×14 come from the pre-made puzzle packs)
- [x] Hard+ difficulty: puzzles that need the hardest deductions the hint system knows
- [x] Puzzle editor: draw regions, check for a single solution and grade it, share it as a code
- [x] Technique drills: short sets of puzzles that each need one deduction from the tutorial, to practise it

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
- [x] Calendar heatmap in Stats: a year grid of the days played, coloured by solves
- [x] Save backup for builds without cloud save: copy progress as a backup code and restore it (in Settings)
- [x] Weekly archive: play past weekly challenges, like the daily archive
- [x] Stats export: save every solved puzzle as a CSV file (Stats → Export CSV)

## Google Play Games
- [x] Achievements: first Hard solve, 7-day streak, topping The Climb, a solve with no hints
- [x] Cloud save: stats, streaks and boards in progress follow the player to a new phone
- [x] More achievements: perfect month, speed run under a minute, Hard+ solves, 100 dailies

## Reach
- [x] Web build for itch, playable in the browser
- [x] Puzzle codes: share or enter a seed so friends can play the same board
- [x] Right-to-left layout for Arabic and Hebrew translations
- [ ] F-Droid release of the no-Google Android build (built from source, so SilentWolf needs handling)
- [x] Tablet and landscape layout: board on one side, controls on the other, for wide screens
- [x] Gamepad support: the keyboard cursor and marks on a controller (Steam Deck)
- [x] Android home screen widget: today's daily board, its status and the streak, tapping straight into the puzzle
- [x] Android app shortcuts: long-press the icon for Daily puzzle, Continue or Weekly challenge

## Feel and polish
- [x] Redo (Ctrl+Shift+Z, and a button beside Undo)
- [x] Keyboard play: arrow keys to move, keys to place × and crown
- [x] Mistake check: say whether the board has an error so far, without a full hint (counts as a hint)
- [x] Pinch to zoom on large boards on small phones (a setting, off by default, shown on touch screens)
- [x] Win animation
- [x] Optional sound effects
- [x] Colour-blind support: region patterns setting
- [x] Untimed mode: a setting that hides the timer
- [x] Interactive tutorial: walk first-time players through the rules on a small board
- [x] Haptics: short vibration on Android when placing a crown and on a win
- [x] Give up / show solution: reveal the answer to a stuck puzzle, without it counting as solved
- [x] Hints and mistake checks zoom out when pinched in, so the cells they point to are on screen
- [x] Dim finished lines: fade rows, columns and regions once they have their crown (a setting, off by default)

## Look and accessibility
- [x] Themes: a few colour palettes beyond light and dark, including high contrast, and custom colours
- [x] Text size setting: Small, Normal, Large and Larger
- [x] System theme: follow the device's light or dark mode (the default where the device has one)
- [x] Reduce motion setting: turn off the reveal, pop-ins and win wave
- [x] Android app icon variants to match the theme

## Later
- [x] Pre-made puzzles: generate 11×11–14×14 boards offline and bundle them, so large sizes don't depend on generation speed

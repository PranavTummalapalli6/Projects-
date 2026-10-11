# Visual QA captures

JPEG, quality 75, 1280 px tall. iOS Simulator, iOS 18.3, Reduce Motion off. How to reproduce them is in `../QA.md`.

## `after/` — the rebuilt app

One folder per device and text size, each with the same stops (named `NN-screen.jpg`):

| Folder | Device | Text size |
|---|---|---|
| `iphone-se-3rd-generation` | iPhone SE (3rd generation), 4.7″ — the smallest | default |
| `iphone-se-3rd-generation-ax3` | same | AX3 (third accessibility size) |
| `iphone-16` | iPhone 16, 6.1″ | default |
| `iphone-16-ax3` | same | AX3 |
| `iphone-16-pro-max` | iPhone 16 Pro Max, 6.9″ — the largest | default |
| `iphone-16-pro-max-ax3` | same | AX3 |

Stops: `01` Home (first run) · `02`–`03d` Buy-in empty, filled, the chip-set sheet (top, bottom) and the buy-in with a chip set · `04`–`05` Players · `06` Chip values · `07`–`07b` Suggested (top, another way to deal it, bottom) · `07c` the table card (landscape) · `08` Custom · `09`–`10b` the live night (running, on a break, after a rebuy, bottom) · `11` buy-in history · `12` the cash-out list · `13`–`14b` cash-out (empty; a photo counted; the photo review — checking, fixing a chip, adding one; counted by hand; bottom) · `15`–`16` bank check (top, bottom, resolved) · `17`–`17b` settle up · `18`–`19` result · `20`–`20b` Poker Health · `21` Home after a night · `22`–`23b` History and night detail · `24`–`24c` Stats · `25`–`25b` Poker Health from Stats (the four-week trend) · `26`–`27b` Settings (top, bottom, healthy play and the helpline) · `28` welcome · `29`–`30` email sign-in (empty, validation) · `31` Home with a night in progress. (`iphone-16-pro-max` was retaken on 11 October, after the photo-review tally was fixed on that phone and the Settings screen gained its *Camera tips* switch; the other five folders are from 9–10 October and don't show that switch.) `iphone-16/` also has `accessibility-audit.txt`, the audit's findings from the final run.

The stubbed backend returns canned answers and the Simulator has no camera, so the photo stops use the app's `-UITestMode` sample photo (27 chips laid out on a grid) rather than a real one, and the cash-out screen shows its "no camera" state. The table card (`07c`) is landscape; the image carries an orientation tag, which every normal viewer honours.

## `camera-guide/` — the camera screen on its stand-in camera

Six stops (`14` … `14f`): from above, not flat and ready; from the side, dark, too steep, tilted and ready. One folder per device and text size: `iphone-16` (default text) and `iphone-se-3rd-generation-ax3`. The Simulator has no camera, so the picture behind the words is the app's drawn sample piles, the advice is driven by scripted readings, and the "Next reading" button at the bottom of each shot exists only in the debug build the tests run (`-UITestGuidedCamera`).

## `live-activity/` — the Lock Screen and the Dynamic Island

`lock-screen-running`, `lock-screen-break` and `dynamic-island-expanded`, from the iPhone 16 Simulator (launched with `-UITestLiveNight`; the system asks once "Allow Live Activities?").

## `../appstore/screenshots/` — the App Store set

Six plain screens at the exact 6.9-inch size (1320 × 2868), from the iPhone 16 Pro Max simulator with the status bar set to 9:41, full battery and signal. See `../APPSTORE.md`.

## `before/` — the original UI

12 screens per device (`splash`, `start`, `auth`, `email`, `buyin`, `style`, `suggested`, `custom`, `timer`, `review`, `result`, `health`), captured from the checkpoint commit `61b37c5` before any of this work.

The original cannot get past its sign-in screen without real credentials, so these were captured with a **throwaway harness** (never committed): a launch flag that opens each screen directly with representative data (a $25 game for 6 players; a week of play for Poker Health). Screens that the original builds from live state show their empty or default look, so a few (Buy-in, for instance) are less "filled in" than their `after/` counterparts. The stops don't line up one to one — the rebuilt app added screens (Settings, Home's resume banner, the step indicator) that have no "before".

## `evidence/`

`section-labels-not-clipped.png` — 3× zoom of two section labels, one that Xcode's accessibility audit reports as clipped and one it doesn't. Both render completely. See `../QA.md`.

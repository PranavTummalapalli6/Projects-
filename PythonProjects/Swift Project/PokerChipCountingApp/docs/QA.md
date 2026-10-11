# QA

How the app is checked, what was run, and what wasn't. Evidence for each claim is in `PROGRESS.md`; screenshots are in `docs/qa/`.

## Running the checks

```bash
# unit tests — the model layer, the solver and planner, stores and sync against a scripted transport, view models,
# photo checks and cards, the built Info.plist, colour contrast
xcodebuild test -project PokerChipApp.xcodeproj -scheme PokerChipApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PokerChipAppTests

# UI tests — the real app against stubbed sign-in and network (-UITestMode)
xcodebuild test -project PokerChipApp.xcodeproj -scheme PokerChipApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PokerChipAppUITests/PokerChipAppUITests \
  -skip-testing:PokerChipAppUITests/PokerChipAppUITests/testLaunchPerformance

# screenshots of every screen; QA_TEXT_SIZE=AX1…AX5 sets an accessibility text size
TEST_RUNNER_QA_TEXT_SIZE=AX3 xcodebuild test -project PokerChipApp.xcodeproj -scheme PokerChipApp \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)' \
  -only-testing:PokerChipAppUITests/PokerChipAppVisualTour/testTourOfEveryScreen
xcrun xcresulttool export attachments --path <result>.xcresult --output-path <folder>   # names are NN-screen

# Xcode's accessibility audit over every screen, and over the camera guide on its stand-in camera
xcodebuild test … -only-testing:PokerChipAppUITests/PokerChipAppVisualTour/testAccessibilityAuditOfEveryScreen
xcodebuild test … -only-testing:PokerChipAppUITests/PokerChipAppVisualTour/testAccessibilityAuditOfTheCameraGuide

# backend: cd ChipVisionService && python -m pytest -q

# the App Store build, unsigned, both ways (docs/RELEASE.md): with an https address it must succeed with the widget
# and the privacy manifest inside; with the placeholder it must fail
xcodebuild archive -project PokerChipApp.xcodeproj -scheme PokerChipApp -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/x.xcarchive CODE_SIGNING_ALLOWED=NO API_BASE_URL=https://example.invalid
```

A full pass of the main UI class takes about 35–45 minutes on the Intel Mac this was developed on, and its log is written only at the end. Two simulator clones running side by side make a slow machine slower (the load average passed 100 during one run, and a UI-test runner then failed to start): pass `-parallel-testing-enabled NO` for the camera tests, and delete `~/Library/Developer/XCTestDevices` between runs, which also frees several gigabytes. The simulators available here run iOS 18.3–18.5. There is no iOS 16 runtime on this Mac, so the 16.4 floor is enforced by the compiler (the deployment target is 16.4, and iOS-17-only APIs would not build) but nothing has been run on iOS 16.

## What is automated

| Layer | Count | Covers |
|---|---|---|
| Backend `pytest` | 171 | endpoints, auth, validation, the nights API (idempotent last-writer-wins, transactions, tombstones that keep no personal data, incremental pulls, legacy import, five deliberate breakages each caught), photo detections and cleanup on delete, **side-view piles (drawn scenes, the camera's pose and roll, and a regression on the seven real photos)**, time-zone bucketing, signed URLs, metadata stripping, deletion, rate limit, readiness |
| iOS unit | 484 | **money and nights:** integer-cent rules, settlement over 4,000 random nights, the file store (atomic writes, quarantine, schema versions), sync against two phones and a rule-following fake server, golden JSON shared with pytest. **stats and healthy play:** a hand-computed eight-night fixture, CSV round trips, History filters, limits, nudges, breaks, reminders, helplines. **chips:** the solver's invariants over thousands of inputs, the planner (owned counts, printed values, fixed values, options, every failure and every alternative), blinds. **photos and cards:** the quality check (sharp, blurred, dark, bright, small), circle edits keeping counts in step over 600 random edits, several photos, no network for counting by hand, the table card and its PNG/PDF, share cards, orientation, break arithmetic. **side view:** the pose maths on the seven real photos' metadata, the request and decoding, pile edits keeping the counts in step. **Live Activity:** the state a night produces, the links, the break/resume actions. **camera guide:** the advice and its order of importance, the smoothing and hold times, the frame measurements, the camera model. Plus API client, view models, sign-in validation, the built `Info.plist`, **colour contrast of every text token** |
| iOS UI | 36 | a whole night from buy-in to Poker Health; overage split; recount; counting by hand; **kill the app mid-night and find the clock still running**; the clock stops when the game is called; resume after a mistaken end; delete; late players and rename; duplicate names; buy-in validation and quick-picks; "too small" explanation; same-as-last-game; custom chips; History, Stats, search, undo, empty states; a break; help; **another way to deal, a fixed value, the table card turning the screen and back, a chip set too small and what to do, a photo counted, circled, fixed and added to, a blurry photo held back, a break on the clock, share buttons ready**; **a photo from the side counted and corrected pile by pile; the camera guide on a stand-in camera (the side-view sequence, a photo taken while advice remains, from above with cancel, the Settings switch)**; sign out, delete account, email-form validation |
| Visual tour + audit | 5 | a screenshot of every screen on every device size and text size; Xcode's accessibility audit; the same two over the camera guide's six states |
| Release build | 2 | unsigned archives for the device SDK, both ways (docs/RELEASE.md), run by hand and written into CI |

## Visual QA

Captured with the visual tour: **51 stops** on each of three devices, each at the default text size and at **AX3**, with Reduce Motion off — `docs/qa/after/<device>[-ax3]/`. The tour walks the whole night (set-up, the chip set, suggestions and another way to deal, the table card, the live night and a break, buy-in history, the cash-out list, counting by hand and from a photo, the photo review, bank check, settle up, result, Poker Health), then History, night detail, Stats, Settings (including healthy play) and the sign-in screens. The original UI is in `docs/qa/before/` (12 screens per device, from the checkpoint commit via a throwaway harness; see `docs/qa/README.md`).

| Device | Default | AX3 |
|---|---|---|
| iPhone SE (3rd generation) — smallest | ✓ | ✓ |
| iPhone 16 | ✓ | ✓ |
| iPhone 16 Pro Max — largest | ✓ | ✓ |

Each run's *test* passed. A runner process sometimes reports "failed to initialize for UI testing" *after* the tour has finished, which makes `xcodebuild` exit non-zero; the screenshots are from the passing test.

The table card is landscape. The Simulator's screenshot tool gets a sideways app wrong, so that stop is taken from the screen rather than the app (`XCUIScreen.main.screenshot()`), and the JPEG carries an orientation tag that every normal viewer honours; the same artwork, rendered to the picture that is shared, was also checked directly.

The camera guide has its own tour (`testTourOfTheCameraGuide`, six stops: from above not flat and ready; from the side dark, too steep, tilted, ready), run at the default size on the iPhone 16 and at AX3 on the iPhone SE. It runs on the stand-in camera, so the picture behind the words is a drawn sample.

Not captured: Reduce Motion (the simulator can't toggle it from the command line), AX4–AX5, iPad (not supported), a physical device.

### Defects found by looking (Phase 1), and fixed

1. A pinned bottom bar was translucent, so card text scrolled behind it showed through the status line. Now opaque with a hairline.
2. The Timer found out the camera was missing only after a tap. It now knows up front, disables Take photo, explains why, and leads with Choose photo.
3. The Review screen needed almost two screens for five colours. Chip, name and stepper now share a line where there's room.
4. A Black chip is 1.04:1 against the backdrop and nearly vanished. Dark chips get a lighter rim.
5. "This buy-in is too small" now names the next amount that works.
6. At AX3 on the smallest phone: the quick-pick buttons broke "$100" across lines; the five chip toggles broke "White" into "Whit/e"; the Home header wrapped beside a tiny logo; Suggested rows wrapped "each" onto its own line; "20-hour limit" split at its hyphen; the Poker Health chart couldn't hold its labels. Each now switches layout at accessibility text sizes (rows instead of columns, stacked instead of side by side).
7. The email field's placeholder rendered in system blue. Placeholders now use one explicit colour.
8. Home was a lone button for a first-time player. It now explains the four steps.

### Defects found in the Phases 2–5 screens, and fixed

Found by the UI tests failing, by looking at the screenshots (above all at AX3 on the iPhone SE), and by the accessibility audit:

1. **The Players screen's pinned "Next" bar rode up with the keyboard and sat over the "Where?" field** — a test couldn't tap it, and a person could press Next instead. The bar now steps out of the way while a field is being typed in; the keyboard's own Next and Done keys carry on.
2. **Suggested at AX3:** "Recom-mended" and "An-other op-tion" broke mid-word beside the button; the blinds and their − / + buttons wrapped. The header and the blinds now stack, left-aligned.
3. **The Suggested/Custom rows ("Chip values") at AX3** broke "Suggest-ed" in a narrow column; at accessibility sizes the icon now sits above the words (this is the shared `ListRow`, so every row in the app gets it).
4. **Cash-out photo buttons at AX3** broke "Add photo" into "Add / phot / o" and "Choose" into "Cho / ose"; they now stack.
5. **The photo review at AX3** cut its own controls off ("Tap a circle to change i…", "A chip is missing — add…", "Not a chip — r…"). At large sizes the controls now scroll under the photo, the main action is full width, and the hint, zoom control and photo total stack.
6. **The photo in the photo review had no description for VoiceOver** (the audit's "element has no description"). The picture is now hidden from VoiceOver and the rings, which say everything it does, carry the description.
7. **Bank check at AX3:** "Money in" and "Chips cashed out" broke across lines beside their amounts, and the pinned bar's hint took a third of the screen. The rows stack, and the hint moves into the scrolling content (the disabled button keeps it as its accessibility hint). The "Recount a player's chips" option was a menu, whose label can't grow with the text size (the audit's "text clipped"); it is now a card that asks whose chips with a dialog.
8. **Settle up and the live night at AX3:** the note under the pinned button ("Closing saves the night…", "3 players still to cash out") took 30–45% of the screen; both moved into the content.
9. **Buy-in history at AX3:** the time wrapped ("6:00P/M") and "Rebuy" hyphenated; the time no longer wraps and the amount drops under the label.
10. **Stats tiles at AX3** hyphenated "AVER-AGE BUY-IN" in a two-column grid; they are one column at accessibility sizes.
11. **Not a layout defect, but wrong:** the Settings → Your data text still said "Other players are never recorded", which has been untrue since nights hold the names the person types. Rewritten to say what is kept, where, and what deleting removes.
12. **The share buttons never appeared** (a `.task` on an empty view never starts): found by a UI test, fixed.

A SwiftUI trap found along the way: an `accessibilityIdentifier` on a plain container replaces the identifiers of the elements inside it for XCUITest (it hid `settle.pay.*`, `settings.help.*` and `tablecard.*`). Identifiers now sit on headings or leaves, or on a real accessibility container.

### A defect found on 11 October in the largest phone's screenshots, and fixed

**On the iPhone 16 Pro Max the photo review's tally showed no numbers** — the chip icons were there, but each count (10, 7, 5, 3, 2) was cut to a sliver, so a person couldn't see how many chips of each colour the photo held. It was in the 9 October screenshots (`13c`–`13e`) and I did not see it. Cause: the legend chooses, with `ViewThatFits`, a one-row layout when everything fits; the stack shared the row between its flexible children, handed the tallies less room than they needed, and the numbers were truncated. It only appears on a phone wide enough for the one-row layout (the Pro Max; the iPhone 16 and the iPhone SE at AX3 choose the stacked one, which is why neither showed it). The tallies and the total now keep their own width (`fixedSize`), and the photo-review UI test asserts that every colour's tally is wider than a chip and a gap (28 pt broken, 35 pt fixed). **The lesson, applied:** every stop of the largest phone was looked at again (all 52, on 11 October), not only the smallest phone at large text.

### Defects found while building and checking the camera guide, and fixed

1. **"Hold the phone upright" would have been said from straight above**, where the turn of the phone is meaningless: gravity's lean across the screen is a hair and its direction noise, so a top-down shot would have been told to turn the phone at random. Found by working through the sensor maths; the tip is now for photos from the side only, and only while the camera looks out (a test pins both).
2. **An array taken for a pointer.** A unit test of "a picture too small to measure" got a number back: the pointer and array versions of `FrameAnalysis.measure` shared a name, an array argument converted to the pointer, and a short array was read past its end. The pointer version has its own label.
3. **The stand-in's picture made the layout wider than the phone**: Cancel sat at x = −293 and could not be tapped ("activation point invalid"). The picture is cropped to the screen. (Test-only code; the live preview fills the screen exactly.)
4. **The screen redrew ten times a second for values that hadn't changed**, and the stand-in redrew a freshly drawn 1,200 × 900 picture each time: on a loaded Mac the UI tests' 10-second waits ran out. The model now publishes only what changed (the tilt is rounded for display, and a unit test shakes the readings by a tenth of a degree and expects no redraw) and the picture is drawn once.
5. **Audit: hit areas and clipped text.** The camera's text buttons had their 44 pt frame *outside* the button, so the audit measured 55 × 20 pt. The frame and a content shape are now inside the label (the same fix as for the text-only quiet buttons, under Accessibility below).
6. **At AX3 on the iPhone SE** the advice filled half the screen, "Standard camera" was cut off to "Standard…" and the tilt readout ran over the dashed frame. A viewfinder can't give its picture to words (and the system camera ignores text size altogether), so the camera's text now stops growing at the first accessibility size, and the dashed frame takes whatever room the words and buttons leave.
7. **An interrupted camera would have stayed failed.** Backgrounding the app is not a failure now; a camera that gave up (a call) starts again when the app returns; the failure screen offers *Try again* as well as the standard camera. *Code-reviewed only* — the Simulator can't interrupt a camera.
8. **The photo delegate's lifetime.** Whether `AVCapturePhotoOutput` keeps its delegate alive until the photo arrives is not something I could confirm, so the camera holds each delegate itself until the last callback. *Code-reviewed only.*

## Accessibility

- **Contrast.** Measured two ways. (a) The token arithmetic in `docs/DESIGN.md`, enforced by `ContrastTests` on the real colour values (body text ≥ 4.5:1 on every surface, accents on cards, banner text on its tint, button labels). (b) The rendered screenshots: 153 text elements measured from pixels, median **9.7:1**; the unscrolled text samples I read out ranged 6.4–13.9:1. Xcode's audit disagrees (see next), but its contrast checker is unreliable here.
- **Xcode accessibility audit.** Run over all 51 stops of the tour on the iPhone 16 (a stop that times out is retried once). The gate covers hit areas, element descriptions, traits and clipped text; the categories left out are explained below. On the final code the audit **passes**: its report (`docs/qa/after/iphone-16/accessibility-audit.txt`) has 14 entries, all of them the allow-listed clipped-text false positives below. Its findings over the course of the work, and what was done:
  - *Hit area too small* — **real**: the text-only "quiet" buttons and "Select all" only responded on their glyphs. Fixed (the whole 44 pt row is the target).
  - *Label not human-readable* — **real**: money read as "$2.50". Now spoken as words ("2.50 US dollars").
  - *Potentially inaccessible text* — **not repeatable**: the first run reported 6–7 at the scrolled Review and Result stops, then none after the money-label fix; a later run of identical code reported 7 at the Result stop and an immediate rerun reported none. It relies on on-screen text recognition, so it is not part of the gate. (The Result screen's stack rows do expose their text to VoiceOver as one element each — "White chips, 2 at $0.25 each" — a possible trigger, since the on-screen text isn't an identical string to what VoiceOver reads; a manual VoiceOver pass would settle it.)
  - *Contrast failed* (171 findings) — **false positives**. It reports black text on the gold button and white text on cards as failing; measured from the rendered pixels 133 of 169 flagged elements are ≥ 4.5:1, and the rest are scrolled-away frames or the intentionally disabled Take-photo button. Contrast is excluded from the audit gate and covered by `ContrastTests` instead.
  - *Dynamic Type font sizes partially unsupported* (69) — **false positives** in everything I checked: chip names, row labels and section headers all scale in the AX3 screenshots. Not part of the gate.
  - *Text clipped* on small uppercase section and tile labels ("NUMBER OF PLAYERS", "CHIPS YOU HAVE", "COUNT THE CHIPS", "DAILY BREAKDOWN", "HOW A GAME NIGHT WORKS", "YOUR RESULT", "WIN RATE") and on the system search field's prompt ("Place, player or note") — **false positives**: at 3× zoom the rendered text is complete, identical in treatment to labels the audit doesn't flag (`docs/qa/evidence/`), and at AX3 on the iPhone SE each wraps in full. Allow-listed by exact label; anything else fails the test.
  - *Text clipped* on **real** text in the Phases 2–5 screens — the photo review's hint, its two buttons and its add-a-chip title, and the bank check's recount option: **real** (confirmed at AX3, where the photo review's controls were cut off and the recount option was a menu whose label can't grow). Fixed, not allow-listed.
  - *Element has no description* on the photo in the photo review — **real**: fixed (the picture is hidden; the rings describe it).
- **VoiceOver.** Labels, values and traits are set on custom controls (chip toggles, rows, the Result and Poker Health cards, the clock); money and durations are spoken as words. **A manual VoiceOver pass was not done** — this needs a person with the screen reader on.
- **Not verified:** Reduce Motion, Bold Text, Voice Control, Differentiate Without Colour (the letter cue is checked in a unit test, not on screen; the photo review's rings show the same letter when it is on), AX4–AX5, and a manual VoiceOver pass over the new screens (the photo review in particular: its rings are buttons labelled "Red chip, 3 of 27", but nobody has swiped through them).

## Performance

- **Solver:** worst case **8.5 ms** over 8,859 inputs in an optimized build (the old solver: 8.3 ms). In a Debug simulator build it stays under the 0.5 s budget the unit test enforces. It runs once, off the main thread, and is cached.
- **Launch:** `testLaunchPerformance` measured **3.3 s on average** (3.0–3.9 s over five launches) for the app launch metric. That is a Debug build on the iPhone 16 *simulator on an Intel Mac*, in `-UITestMode`, so it says nothing about the 1.5 s cold-start-to-Home budget, which is for a Release build on a device. **Not profiled with Instruments**; do that on a device before relying on any launch figure.
- **Photos:** resized to ≤ 1600 px on the long edge and JPEG-encoded off the main thread before upload.
- **Profiled with Instruments (11 October)** — `xcrun xctrace record` with the *App Launch* and *Time Profiler* templates on the iPhone 16 Simulator (iOS 18.3) of an **Intel Mac, running a Debug build in `-UITestMode`**. These are not device numbers; the *ratios* are what mean something.
  - **Launch.** The main thread is busy from the process's start until about 3.3 s (it agrees with `testLaunchPerformance`'s 3.3 s), and then quiet (5–15 ms of work a second on Home). The time goes to the system loading a Debug build: dyld applying fixups (113 ms) and running static initialisers (111 ms), and the Swift runtime looking up protocol conformances (about 260 ms). The app's own `PokerChipAppApp.init()` takes 39 ms. A Release build on a phone will be very different; **no device number exists yet**.
  - **Sign-in.** *Not profiled*: `-UITestMode` stubs sign-in, and a real Firebase sign-in needs an account whose password I won't type.
  - **The timer (the live night screen).** This found something. With the screen up for 16 seconds the main thread spent **15% of a core** — SwiftUI re-evaluating its view graph every frame — against almost nothing on Home. The cause was the clock's dot, which pulsed with a repeating animation, and a repeating animation redraws the screen every frame for as long as the night lasts (the app keeps the screen awake for the whole night, and on a ProMotion display a continuous animation should also keep the refresh rate up — not measured here). The dot now blinks once a second in step with the clock and is still under Reduce Motion: **1.3% of a core, about 11 times less**, measured the same way. Nothing else on that screen animates.

## Not verified

- The camera, on a physical device: capture, the permission prompt, denial and the Settings link, and the static frame the standard camera shows (`FramingGuideView`, code-reviewed only).
- **The camera guide's lens**: the live preview, the motion sensors, the brightness and sharpness readings of real frames (the advice thresholds are reasoned, not measured), the photo it takes against the system camera's, a call or the lock button interrupting it, VoiceOver. Everything else about it is tested on a stand-in camera.
- **The Live Activity on a physical phone** (it was driven in the Simulator on an iPhone 16, including the Lock Screen and the expanded Dynamic Island).
- The table card on a real iPhone: that it turns the screen and back, keeps it awake, and shares as a picture and a PDF. In the Simulator it turns and back (UI test); the share sheet itself is out of process and was not opened.
- The break reminder notification and its permission prompt (the scheduling is unit-tested with a fake notification centre).
- Sign-in persistence across a relaunch with a real Firebase account; password-reset email; Anonymous sign-in (needs the console switch); Sign in with Apple at runtime.
- Anything against a deployed backend, a real Firestore or a real bucket: the backend is tested against fakes and in a container with no credentials.
- Photo-counting accuracy on real photos. The service is classical computer vision and says so; the app always requires confirmation.
- The Release build on a physical device, TestFlight, App Store validation.

# Progress

Branch `release/v1-prep`. Nothing has been pushed. Open questions and owner-only steps: `QUESTIONS.md`. Plan: `PLAN.md`.

**Labels.** *Verified* = built, tested or run, with how. *Code-reviewed only* = read, not run. Compiling alone is never called working.

## Where things stand (11 October 2026)

Everything the owner has asked for is built, except what needs them (tournament mode, Crashlytics, App Check, the weekly widget — QUESTIONS A6–A8, A11) and what needs a phone (the camera lens, a physical-device pass — QUESTIONS B5). The build is green: backend **171** tests, iOS unit **484**, iOS UI **36**, the accessibility audit passes, and the unsigned App Store build succeeds with an https address and is refused with the placeholder.

| Since | What | State |
|---|---|---|
| 9 Oct | Phases 2–5: game nights, History, Stats, healthy play, chip planning, table card, photo review, breaks, share cards | built and tested (below) |
| 10 Oct | Unused images and the old single-player result model removed (A1, A4); helpline is 1-800-MY-RESET | done |
| 10 Oct | **Side-view counting**, from the owner's seven photos | built; an estimate, with measured limits (below) |
| 10 Oct | **Live Activity**: the night's clock on the Lock Screen and in the Dynamic Island | built; driven in the Simulator |
| 10–11 Oct | **Phase 6**: privacy manifest, one version for every target, icon variants, String Catalog, release guard, runbook, App Store text, legal drafts, deploy script, CI archive job | built; the App Store build is checked both ways |
| 11 Oct | **Camera guide** (the stretch goal): live tips on the photo screen | built and tested on a stand-in camera; **the lens is unverified** |

## Phases 2–5

Go-ahead given on 2026-10-09. The work landed as one commit per *layer* rather than per task (backend; app; docs), because the screens share files across tasks and a per-task split would have produced commits that don't build.

| Task | Status and evidence |
|---|---|
| **Phase 2 — Game Night** | |
| 2.1 Night model in integer cents, bank resolutions, settlement engine, property tests | **done** — 1,000 balanced + 2,000 unbalanced + 1,000 order-shuffled random nights |
| 2.2 Repository protocol, atomic file store, schema version + migration, `NightStore` | **done** — atomic files, quarantine, newer/older schema, stamping, queue, LWW merge, tombstones, relaunch |
| 2.3 Backend `PUT/GET/DELETE /v1/nights` (LWW, tombstones, incremental `since`), legacy import | **done** — backend tests; needs a Cloud Run redeploy (QUESTIONS B2) |
| 2.4 Client sync (outbox, pull, conflict rule) | **done** — scripted-transport tests incl. two phones against a server that follows the real rules, offline/401/422/429/5xx/404, clock-skew overlap, golden JSON shared with pytest |
| 2.5 UI: new night (names, regulars) → live night (rebuy + undo) → cash out → bank check → settle up → result | **done** — UI tests below |
| 2.6 Retire the single-player flow | **done** — `TimerView`, `PendingSaves`, `SessionModels` and (after A4) `SessionResult.swift` removed |
| 2.7 UI test: create → rebuy → cash out → bank check → settle | **done** — `testAWholeNightFromBuyInToSettlement` and eight more night-flow tests |
| **Phase 3 — History, stats, healthy play** | |
| 3.1 Tab shell, History (search, filters, undo-delete), night detail (notes, place, photos) | **done** |
| 3.2 Stats (net, bankroll, best/worst, streaks, month/place/weekday/stake, per-hour ≥ 10 nights) and CSV export | **done** — hand-computed eight-night fixture; CSV round-trips |
| 3.3 Poker Health from local nights, four-week trend, limits, break reminder, committed break, helplines | **done** |
| **Phase 4 — Chip setup and counting** | |
| 4.1 `ChipPlanner` (owned counts, printed values, fixed values, options, typed failures with alternatives), `BlindsPlanner` | **done** — property tests; with no limits it returns exactly the old solver's stack |
| 4.2 Chip-set screen, Suggested rebuilt on the planner (another option, fixed values, chips needed vs owned, why-these-values, blinds) | **done** |
| 4.3 Table card (landscape, shareable as picture and PDF, from Suggested and the live night) | **done** — landscape confirmed by UI test in the Simulator |
| 4.4 Photo counting: on-phone quality check, circles that can be corrected, several photos, prewarm | **done** — the lens is covered under "Camera guide" below |
| 4.5 Side-view counting | **done** (10 Oct) — below |
| **Phase 5 — Delight** | |
| 5.1 Breaks on the live clock | **done** |
| 5.2 Share cards (night summary, weekly recap) | **done** |
| 5.3 Live Activity | **done** (10 Oct) — below |
| 5.4 Tournament mode | **asked, not built** (A6) |

### Phase reports

**Phase 2 — Game night.** *Changed:* the single-player timer is now a multi-player night — names and regulars, rebuys as undoable events, a clock that survives the app being killed and ignores breaks, per-player cash-out by chips or amount, a bank check that makes any shortfall or overage a recorded choice, at most n − 1 payments with text and picture to share — stored on the phone in atomic versioned files and synced last-writer-wins to a new nights API. *Verified:* property tests over 4,000 random nights; store and sync tests including two phones against a rule-following fake server; UI tests from creating a night to the result, plus overage split, recount, kill-and-relaunch, delete, late joiners and duplicate names. *Not verified:* the nights API against a real Firestore (nothing is deployed); a VoiceOver pass. *Risks:* the backend must be redeployed before backup works.

**Phase 3 — History, stats, healthy play.** *Changed:* four tabs; History with search, filters and undo; Stats with CSV export; a Poker Health trend; limits, a break reminder, a committed break and a helpline card, all in the person's own hands. *Verified:* stats against a hand-computed eight-night fixture; CSV parsed back to the same rows for random tables; empty, loading and store-problem states for History and Stats; UI tests for the lists, search, the break and the help card. *Not verified:* the notification itself (needs a device), Poker Health at AX4–AX5.

**Phase 4 — Chips and counting.** *Changed:* chip values come from the chips you own (counts, printed values, values you fix), with other ways to deal the same buy-in, blinds you can step, a landscape table card to share, and photo counting that checks the photo first, circles every chip, lets you fix a circle (or add one) and adds a second photo. *Verified:* planner property tests (every option exact and well-shaped, never more of a colour than the set holds, every alternative offered really works); photo quality checked against nine real photos and their blurred copies; circle edits keep the cash-out counts in step over 600 random edits; counting by hand makes no network request; UI tests for the set-too-small path, another option, a fixed value, the table card (turns the screen and back), the photo flow end to end and a blurry photo. *Not verified:* a real photo against a deployed backend, top-view detection accuracy.

**Phase 5 — Delight.** *Changed:* a Take a break / Resume button on the live clock (time on a break is never played time, and the reminder pauses with it) and two share cards. *Verified:* break arithmetic by property test; cards render to pictures of the right size; UI tests for the break and for the share buttons being ready. *Not verified:* what the system share sheet shows (out of process).

## Since 10 October

### Side-view counting

*Changed.* The person says whether the chips are spread out ("from above") or standing in piles ("from the side"). A side photo goes to the same endpoint with the camera's tilt (read from the photo's own metadata, or from the motion sensors at the shutter — only those three numbers). The server finds each pile by the colour of the chips' edge-spots (Lab colour masks), counts a short pile from the rings of spots it can see and a tall stack from its height, and returns a box, a colour and a count per pile. The photo review draws a box and a count on every pile; each can be recounted, recoloured, removed, or added, and the cash-out counts move with it.

*Verified.*
- Backend: tests on drawn scenes (tall stacks counted within a chip when drawn to the model's own geometry; never "high" confidence; no pose → every count says so; boxes follow the camera roll; a colour not in play is renamed only when that makes sense) and a regression on the owner's seven real photos (kept out of git; it runs here and is skipped where the photos are absent).
- App: unit tests of the pose maths, the request, the decoding (tolerant of older servers) and 600 random pile edits keeping the counts in step; a UI test that takes a side photo, corrects a pile's count and colour, removes a pile, adds one, and checks the cash-out counts.
- **Measured on the seven real photos: 26 of 28 piles found, 18 of 28 exactly right.** The photos hold piles of one or two chips. Stacks of five or more are only proven on drawn scenes — the case the counter was built for has not been measured (QUESTIONS A13). A chip is named for the colour of its body, never its edge-spots, so your white chip with blue edges is always White (A12: the counter used to rename it to Blue in a night with no White; changed on 11 October by your rule and checked on the seven photos, where it comes out White every time it is found).

*Not verified.* Photos from the camera in portrait and landscape on a phone (roll was checked on landscape photos only); any real tall stack.

### The Lock Screen and the Dynamic Island

*Changed.* A night in progress shows its clock, the money on the table and the number of players on the Lock Screen and in the Dynamic Island, with one Break / Resume button that opens the app. The clock is not a number the app keeps sending: the system counts up from a date. A new Xcode target (`PokerChipWidgets`) carries it; three small files are shared with the app. There is no App Group, so the weekly-hours widget that was proposed with it is not built (A11).

*Verified.* Unit tests for the state a night produces (running, on a break, ended, a break begun and ended) and the links; in the Simulator on an iPhone 16, driven by launch flags: the clock counting on the Lock Screen and in the expanded island, the Break link opening the app with the clock stopped, and Resume (screenshots in `docs/qa/live-activity/`). The simulator asks once "Allow Live Activities?".

*Not verified.* A physical phone, the compact and minimal island on hardware, iPhone 14 Pro-class timing.

### Phase 6 — release engineering

| Piece | Evidence |
|---|---|
| Privacy manifest (`PrivacyInfo.xcprivacy`) | **verified present in the unsigned archive**, with the one required-reason API the app uses (UserDefaults, CA92.1) and the data it sends to its own service |
| One version for every target (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` at project level), `scripts/bump-build.sh` | **verified** — the archive's app and widget both say 1.0 (1) |
| Release guard extended: privacy manifest present, widget embedded, widget version equals the app's, plus the earlier placeholder / https / camera-text / local-network checks | **verified both ways** with unsigned Release archives for the device SDK, on the final code: an https address → *ARCHIVE SUCCEEDED*, widget and manifest inside; the placeholder → *Release build still contains development values: [placeholder value such as REPLACE_WITH_CLOUD_RUN_URL]* and nothing else. The first attempt failed on matching versions: Xcode's script sandbox refused to let the guard read the widget's `Info.plist`; it is now a declared input |
| App icon: dark and tinted variants | in the asset catalog and building; **not looked at on a Home Screen in dark or tinted mode** |
| String Catalog (`Localizable.xcstrings`, 300 keys) | the text SwiftUI takes from literals; English only; plain-`String` messages are not in it (DESIGN.md → Known gaps) |
| `docs/RELEASE.md` (signing, deploy, TestFlight, what the build checks), `docs/APPSTORE.md`, `docs/legal/` drafts, `ChipVisionService/deploy.sh` | written; the deploy script prints its plan and does nothing unless given `--apply`, which I never ran. Nothing was entered into App Store Connect, deployed, signed or pushed |
| CI | an unsigned-archive job added to `.github/workflows/ci.yml`; **the file has never run** (no remote) |
| Instruments | **done, labelled** — `xctrace` Time Profiler and App Launch on the iPhone 16 Simulator (Intel Mac, Debug build): launch is dominated by dyld and the Swift runtime, the app's own init is 39 ms (no device number); sign-in is stubbed so it wasn't profiled; **the live night screen used 15% of a core because its dot pulsed with a repeating animation — changed to a once-a-second blink, 1.3% (about 11× less)**. Details in `QA.md` → Performance |
| App Store screenshots | **done** — six plain 1320 × 2868 screens in `docs/appstore/screenshots/` from the iPhone 16 Pro Max simulator (status bar 9:41); three are thin because of the test data (a dimmed *New game*, a drawn sample photo, one night of stats) and `APPSTORE.md` says to retake them from a real phone. Choosing them is how the photo-review tally defect was found |

### Camera guide (the stretch goal)

*Changed.* The camera screen tells you, in a sentence at the top, how to hold the phone while it is open — flatter above the chips, or low and level for a photo from the side, straighter, steadier, more light, less glare — and turns green when it is right. It reads how the phone is tilted (the motion sensors), how bright and sharp the live picture is (the same measures the check on a finished photo uses) and how fast the phone is turning, and **never locks the shutter**. The photo it takes carries the tilt it was taken at. "Standard camera" is one tap away, Settings → *Camera tips* turns the guide off, and it falls back to the standard camera if the lens won't start. It is on by default (QUESTIONS, *Decisions I made*).

*Verified.* On a stand-in camera: unit tests of the advice (every message, the order of importance, the thresholds at their edges, a turned phone being fine from above, "turned" meaning nothing near straight down), the smoothing and hold times, the frame measurements (including a camera buffer's padded rows and a fine grain not being mistaken for sharpness), and the camera model (start-up, a camera that never answers, a failure, a photo that couldn't be taken, a restart after the app comes back, no redraw for a tremor); four UI flows (the side-view sequence dark → too steep → tilted → ready and a photo that is counted; a photo taken while the advice is still not ready; from above, cancel sending nothing; the setting) and Xcode's accessibility audit over the screen at every state, at the default size on the iPhone 16 and at AX3 on the iPhone SE.

*Not verified — needs a phone.* The lens, the motion sensors and the live brightness and sharpness readings (the Simulator has none); how the photo compares with the system camera's; a call or the lock button interrupting it; a VoiceOver pass. The advice thresholds are reasoned, not measured on real preview frames. If it ever feels worse than the Camera app, the Settings switch is the remedy.

## How to build and test

```bash
# iOS — unit tests, then the UI flows (the app runs against stubbed sign-in and network)
xcodebuild test -project PokerChipApp.xcodeproj -scheme PokerChipApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PokerChipAppTests
xcodebuild test -project PokerChipApp.xcodeproj -scheme PokerChipApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PokerChipAppUITests/PokerChipAppUITests \
  -skip-testing:PokerChipAppUITests/PokerChipAppUITests/testLaunchPerformance

# backend
cd ChipVisionService && python3 -m venv .venv && . .venv/bin/activate \
  && pip install -r requirements-dev.txt && python -m pytest -q

# the Release guard, unsigned, both ways (see docs/RELEASE.md)
xcodebuild archive -project PokerChipApp.xcodeproj -scheme PokerChipApp -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/x.xcarchive CODE_SIGNING_ALLOWED=NO \
  API_BASE_URL=https://example.invalid      # succeeds; leave API_BASE_URL out and it is refused
```

## Evidence

| Check | Result | How |
|---|---|---|
| Backend tests | **171 pass** | `pytest` in a clean venv, Firestore/Storage replaced by fakes (the nights API, detections, side view incl. the seven-photo regression, photo cleanup) |
| iOS unit tests | **484 pass**, no new warnings | `xcodebuild test`, iPhone 16 simulator (iOS 18.3), serial |
| iOS UI tests | **36 pass** | same, `-UITestMode`; includes the whole night to settlement, kill-and-relaunch mid-night, the table card turning the screen and back, a photo counted, circled, fixed and added to, **a photo from the side counted and corrected pile by pile**, a blurry photo held back, a break, share buttons, **the camera guide on its stand-in camera** |
| Visual tour | 51 stops × 3 devices × 2 text sizes (9–10 Oct; the Pro Max default set retaken on 11 October, all 52 stops looked at), plus the camera guide's six stops at the default size on the iPhone 16 and at AX3 on the iPhone SE | `docs/qa/after/` — the new screens were reviewed at AX3 on the iPhone SE and nine layout defects found and fixed (`docs/QA.md`); the camera guide's three more (below) |
| Accessibility audit | **passes** — the 51-stop walk on the iPhone 16 (14 entries, all allow-listed false positives; re-run on 11 October) and the camera guide's six stops (0 entries; default size on the iPhone 16 and AX3 on the iPhone SE) | Xcode's audit; its first runs on the new screens found real defects, fixed and re-run — `docs/QA.md` |
| Accessibility | contrast enforced on the colour tokens and measured on rendered pixels earlier (median 9.7:1); the audit's contrast category is unreliable here | `docs/QA.md` |
| Solver invariants | 0 violations in 8,859 inputs (old solver: 43); `ChipPlanner` with no limits returns the solver's stack exactly (300 random inputs) | old and new solver compiled side by side with `swiftc -O`; planner property tests |
| Photo check | sharp sample photos score 913–1,825; the same photos blurred by 8 px (at 1600 px wide) score 30–55 | the nine real sample photos, measured with the shipped Swift code (not committed — `PokerChipApp/test_photos/` is git-ignored) |
| Container | builds; runs as uid 10001; time zones resolve; `/healthz` 200; `/readyz` 503 with no credentials | `docker build` + `docker run`, then removed (Phase 1; not rerun) |
| Release guard | fails on the placeholder; passes with a real https address | unsigned Release archives for the device SDK, on the final code (11 October 2026), see Phase 6 above |
| `SIGN_IN_WITH_APPLE` | compiles (symbols present, `AuthenticationServices` linked) | build with the flag set (Phase 1); **not run** — needs the capability |

## The audit's defects

### P0 — launch blockers

| # | Defect | Status | Evidence |
|---|---|---|---|
| 1 | Forced sign-out every launch | **Fixed** | The `signOut()` in the app delegate is gone and `AuthViewModel` follows Firebase's own listener. *Code-reviewed only*: staying signed in across a relaunch needs a real Firebase account, and signing in with one needs credentials I won't enter. Please check it once on a device |
| 2 | Placeholder camera text; silent camera failure | **Fixed** | Unit test on the built `Info.plist`; Release archive plist shows the real text. UI test: with no camera (Simulator) the app explains, disables Take photo, leads with Choose photo. *Code-reviewed only*: the permission-denied path and the Settings link (needs a device) |
| 3 | No production backend config | **Fixed in the app; deploy is yours** | `API_BASE_URL` per configuration; Release archive fails on the placeholder and passes with an https address. The Cloud Run deploy needs your project (QUESTIONS B2) |
| 4 | Photos were public | **Fixed** | Private objects, 1-hour signed URLs, EXIF/GPS dropped by re-encode, deny-all rules written. Verified against fakes by backend tests; *not exercised against a real bucket* because nothing is deployed |
| 5 | Playtime double-counted on rebuys | **Fixed** | The client sends this round's seconds only. A 60 + 30 + 45 minute night sums to 135 in a unit test (client) and in a backend test run for `America/Los_Angeles` and `Asia/Kolkata`. *Not run end to end* against Firestore |
| 6 | Weekly summary bucketed by UTC | **Fixed** | Backend tests: an 8 pm Pacific game stays on its local day; a 23:30-local game; the total equals the sum of the bars |
| 7 | No sign-out / delete-account / password reset / guest / Apple | **Fixed in the app** | UI tests: sign out, delete account (stubbed 204), email form validation. Backend: `DELETE /v1/account` removes sessions, photos and the auth user (tests). Guest mode needs the Anonymous provider enabled (B1); Sign in with Apple needs the capability (B3); password-reset email *not exercised* (needs Firebase) |
| 8 | Game not durable; clock restarts | **Fixed** | UI test: start a game, kill the app, relaunch → Resume banner, and the clock includes the time the app was dead. UI test: back from Review doesn't restart it. Unit tests on the model |

### P1

| # | Defect | Status | Evidence |
|---|---|---|---|
| 9 | No tests | **Done** | the counts above |
| 10 | Solver ran inside `body` | **Fixed** | `SuggestedViewModel`: once, off the main thread, cached by input |
| 11 | Custom chips logic | **Fixed** | Running total, per-colour subtotal, counts used for the start stacks, players from the game. UI test |
| 12 | Hard-coded `$`, `Double(text)` | **Fixed** | `Money`; formatting/parsing tests including a comma-decimal locale |
| 13 | Accessibility and contrast | **Mostly fixed** | 44 pt targets (the audit found four controls that weren't — fixed — and later the camera's buttons, whose 44 pt frame sat outside the button), non-colour chip cues, contrast enforced and measured, money spoken as words, layouts that change at large text sizes (checked at AX3 on three devices; six breaks found and fixed). *Not done*: a manual VoiceOver pass, Reduce Motion, AX4–AX5 |
| 14 | Repo and asset hygiene | **Done** | `.gitignore` added; splash art replaced by a 330 KB seal; the unused image sets, `Archive.zip` (now in the Trash) and the unreferenced `pokerchip.imageset` deleted on your OK (A1, A10); the unused Firebase Analytics library unlinked (A9) |
| 15 | Forced splash; no timeouts or offline states | **Fixed** | Launch screen + splash once per version ≤ 0.8 s; 15 s/60 s timeouts, retry with backoff, token refresh, an unsent-games queue. Client tests |
| 16 | Backend hardening | **Fixed** | Persistent photo refs, idempotent `/complete`, size/pixel limits, non-root container with a healthcheck, structured logs, per-user rate limit |

## Problems found while verifying, and what was done

- The solver returned stacks whose counts rose with value for tiny buy-ins (43 of 8,859 inputs). It now finds a correct stack where one exists, and otherwise says "too small" and names the next buy-in that works. The "≈ $1.65" five-colour floor in the earlier notes was wrong; the real floor for a correct stack is **$3.15**.
- `/readyz` said "ready" with no credentials. Fixed and tested.
- The Docker image had no time-zone database, which would have silently broken the weekly summary. Added `tzdata`.
- A real archive failed once because iCloud had evicted asset-catalog files, and git's own index was evicted on 10 October. See QUESTIONS B4: this will happen again until the repo moves off the synced Desktop.
- Visual review of the first screenshots led to: opaque pinned bars (text had been ghosting through), a Timer that knows about the camera up front, compact Review rows, a visible rim on dark chips, "too small" naming the next working buy-in, and a first-run "how a game works" card.
- Reviewing at AX3 on the smallest phone found text broken mid-word (quick-pick buttons, chip names), a cramped Home header, wrapping Suggested rows and a chart that couldn't hold its labels. Each now has an accessibility-size layout.
- Xcode's accessibility audit found four controls with tap targets smaller than 44 pt and money read as "$2.50"; both fixed. Most of its other findings were false positives, documented in `QA.md` with the evidence.
- **Side view:** a dozen estimators for "one chip or two" (silhouette height, area, convexity, a generalised Hough transform, ellipse fits, seam profiles) failed on the real photos before the counter settled on rings of edge-spots for short piles and height for tall ones; a tab-splitting idea made things worse and was reverted; widening the black-chip search to two dimensions invented rings and was reverted. The README of the service says what is and is not known.
- **The unsigned Release archive failed on matching versions** — Xcode's script sandbox hid the widget's `Info.plist` from the new guard check, which then compared an empty string with "1.0". Declared as an input.
- **The photo review's chip tally showed no numbers on the iPhone 16 Pro Max** (only slivers), a defect in the 9 October build that I did not notice in its screenshots; found on 11 October while choosing App Store screenshots, fixed, and every stop of the Pro Max tour looked at again (details in `QA.md`).
- **Camera guide** (details in `QA.md`): "hold the phone upright" was being said from straight above, where a phone's turn is meaningless; an array was taken for a pointer and read past its end; the stand-in's picture made the layout wider than the phone; the screen redrew ten times a second for unchanged values; at AX3 the advice took half an iPhone SE's screen.

## Decisions

Portrait, iPhone only · USD only (formatting is currency-aware) · guest first · deployment target stays 16.4 · no new app dependencies; `pytest` and `httpx` test-only (approved, A2) · dark, purple/gold identity evolved, not replaced · the camera guide is on by default with the standard camera one tap away.

## Not done

**Waiting on you:** tournament mode (A6 — a description to decide from is in QUESTIONS), the weekly-hours widget (A11, until a paid team), photos of real stacks (A13), the release inputs (team and bundle ID, support email and URLs, App Store name), and the backend deploy (A14). **Decided:** Crashlytics in 1.1 after TestFlight (A7); App Check declined (A8). **Done on 11 October at your word:** the unused Firebase Analytics library removed (A9), `Archive.zip` moved to the Trash and the unreferenced `pokerchip.imageset` removed (A10), the white-chip colour rule (A12), and the project published to GitHub (A15, `docs/PUSH.md`). No VoiceOver pass, no physical-device test of the camera and its guide, the table card's rotation, the share sheets, the break reminder or the Live Activity (QUESTIONS B5). No TestFlight, no submission, no backend deploy.

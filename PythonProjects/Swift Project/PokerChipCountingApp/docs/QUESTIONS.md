# Questions and owner-only steps

Everything open is in plain words below, each with the answer I'd give. Nothing marked "open" has been done or deployed.

## Answered — thank you

| # | Question | Your answer | What happened |
|---|---|---|---|
| A1 | Delete the unused image sets | Yes | Done: the War Card Game assets, `StudioLogo`, the old splash and `pokerbackground` are gone (one commit, easy to revert). `Archive.zip` and the unreferenced `pokerchip.imageset` followed on your later yes (A10) |
| A2 | Keep `pytest` and `httpx` as test-only packages | Yes | Kept; they are in `requirements-dev.txt` only, not in the production image |
| A3 | Portrait only, except the table card | Yes | Unchanged |
| A4 | Delete the old single-player result model | Yes | Done: `SessionResult.swift` and its decoding test are gone. (The server's `/complete` and `/weekly-summary` endpoints are no longer called by the app; remove them once every installed copy has updated) |
| A5 | Live Activity / Lock Screen widget | Yes | **Built** — see the next section. The weekly-hours widget that goes with it needs an App Group (A11) and isn't built |
| — | Helpline | "Use 1-800-MY-RESET" | It is the only US number on the card (call, text and website), with the date the numbers were last checked |
| — | Camera tips on by default? | "Leave camera tips" | Kept on by default, with the standard camera one tap away and a switch in Settings |
| A7 | Crashlytics | Yes | Planned for **1.1, after TestFlight** (my recommendation, which I took your "yes" to mean). Not in 1.0. Tell me if you want it in 1.0 instead: it then needs the console switch, a privacy-label line ("Crash Data") and a rewrite of the "no analytics" sentence in the App Store text |
| A8 | Firebase App Check | No | Not built; left out of the plan |
| A9 | Remove the unused Firebase Analytics library | Yes | **Done (11 Oct).** `FirebaseAnalytics` is no longer linked (three entries in the Xcode project; no source used it). The unit tests (484) and a UI smoke run pass, and the Release archive builds without it and contains no Analytics or Measurement files. `GoogleService-Info.plist` still says analytics is off, which is now simply true |
| A10 | Delete `Archive.zip` and the unreferenced `pokerchip.imageset` | Yes | **Done (11 Oct).** `Archive.zip` is in the Trash, not emptied, as `Archive-<date>.zip` (macOS won't let me list the Trash, so look there if you want it back); the image set is removed with `git rm` and stays in history |
| A12 | What is the white chip with blue edge spots? | "It's a white chip. Any chip is counted as the colour it predominantly is" | **Done and checked (11 Oct).** The side-view counter names a pile for the colour of its chips' bodies and never for their tabs (`ChipVisionService/app/side_view.py`). On your seven photos, with Blue in play and White not, the white chip with blue edges comes out White in all five photos where it is found and never Blue (same detection as before; only the name changed); the 171 backend tests pass. The top-view counter is unchanged — it names a chip from the middle of its face, and I have no top-view photo of your chip to check it on |
| A11 | Weekly-hours widget and the App Group | "Will update when I do" | Waiting for you to have a paid Apple Developer team |
| A13 | Photos of real stacks | "Will send later" | Waiting |
| 7–9 | Team and bundle ID, support email and URLs, App Store name | "Will send info" | Waiting |
| A15 | Push the project to GitHub | "Push the entire code into a new folder in Swift projects", then "push to PokerChipCountingApp/ directory in swift projects" once you had deleted the folder you uploaded by hand; over SSH with your key | **Done (11 Oct).** In `PranavTummalapalli6/Projects-`, the folder `PythonProjects/Swift Project/PokerChipCountingApp/` holds the whole project (app, tests, backend, docs). The older copy directly in `Swift Project/` was not touched. How it was done, and how to undo it, is in `docs/PUSH.md` |

## Open — decisions I'd like from you

**A6. Tournament mode — what it would be, so you can decide.** A second kind of night for a one-table poker *tournament* instead of a cash game. Everyone buys in once for the same starting stack; the blinds go up on a timer by level (say every 15 minutes) with a "level up" alert; players are knocked out and the app records the finishing order; the prize pool is split by a payout table (say 50/30/20 for the top three); rebuys exist only while a late-registration window is open. It would reuse the chip planner (starting stacks), the table card (current blinds), the clock and breaks and the Lock Screen clock (showing the level). What is new: a blind-structure screen, a level clock with alerts, knock-out tracking and finishing positions, a payout calculator, a different settle-up (prizes instead of cash-out differences), and changes to the saved night, the sync format and the server's checks, with tests. That is roughly two to three weeks of careful work and a second set of rules to maintain. A smaller option: a **blind timer** on its own (levels, countdown, alert, shown on the table card) needs no change to saved nights or the server and is about three days. *I'd say: not in 1.0. Ship the cash-game app, see whether people ask for tournaments, then add the blind timer (1.1) and the full mode after it (1.2).*

**A14. May the backend be deployed on a billed Google Cloud project?** (Release input 10, unchanged.) You'd run it; I never will. `ChipVisionService/deploy.sh` prints the plan; `--apply` runs it.


## Things only you can do

### B1. Firebase console (project `pokerchipapp-f7a84`)
1. **Authentication → Sign-in method → Anonymous → Enable.** Guest mode, and the App Review demo, need it; until then "Continue as guest" shows "This sign-in option isn't turned on yet."
2. If you ship Sign in with Apple: enable the **Apple** provider (needs a paid team).
3. **Restrict the iOS API key** to the bundle ID: Google Cloud Console → APIs & Services → Credentials → the iOS key → Application restrictions → iOS apps.
4. Firestore and Storage weren't enabled when this work started (see `ChipVisionService/README.md`). Enable both.

### B2. Deploy the backend and lock down access
Everything is in `docs/RELEASE.md` → *Deploy the backend*, and `ChipVisionService/deploy.sh`. The app now depends on three things a backend deployed before this work doesn't have, so **deploy it again**:
- the **nights API** (`PUT/GET/DELETE /v1/nights…`) that backup and sync use. Until then the app keeps everything on the phone and Settings → Backup says "Backup isn't available yet";
- **`detections` and `stacks` on the photo response** (the circles, and the piles from the side). An older server still counts from above; the circles just don't appear, and a side photo is refused with a clear message instead of being miscounted;
- **deleting a night deletes its photos**.

Then the two one-off commands (rules, and the 30-day photo lifecycle), a **budget alert** (the runbook says how), and the Cloud Run URL into the Release `API_BASE_URL`.

### B3. Apple and App Store
- **Sign in with Apple.** Add the capability (paid team), then add `SIGN_IN_WITH_APPLE` to *Active Compilation Conditions*. Account deletion for Apple users should also revoke their Apple token; that backend step is **not written**.
- **App Store name, age rating, privacy label.** All drafted in `docs/APPSTORE.md`; the answers are yours. The age-rating gambling questions in particular: answer them from Apple's current definitions, not from my draft notes.
- **TestFlight and submission** — `docs/RELEASE.md`.

### B4. Your Mac
- **The repository lives on an iCloud-synced Desktop and the disk is ~99% full.** macOS "optimizes" storage by evicting files; during this work git's own files (including its index) and asset-catalog files have been evicted, and git and Xcode failed until they were read again. It will recur and it can lose work. Move the project to a folder iCloud doesn't sync (for example `~/Developer`), or free space. Until then, if git says "Operation timed out", re-read the file it names (`cat file > /dev/null`, or `brctl download file`).
- **The Debug backend address** is your Mac's LAN IP (`API_BASE_URL` Debug = `http://192.168.1.177:8000`). Update it if the IP changes; the Simulator can use `http://localhost:8000`.

### B5. Please try these on a real iPhone
I couldn't run these in the Simulator, so they are *code-reviewed only*:
- **Photo counting end to end** — the camera, the permission prompt, a real photo against a deployed backend, the circles lining up, a poor photo being caught, a second photo adding to the first.
- **The camera guide (Camera tips)** — new, and the one thing here I most want a person to try. Open *Take photo*: the words at the top should change as you tilt the phone (flat above the chips for a photo from above; low and level for one from the side; "Hold still", "It's dark in here"), turn green and say "Looks good" when it is right, and the shutter should always work whatever it says. The photo should look as sharp as the standard camera's; the piles' boxes should still land on the piles for a photo from the side. Try a phone call or the lock button while it is open and then come back (it should start again), and "Standard camera" (it should switch to the usual Camera screen). If anything feels worse than the Camera app, **Settings → Camera tips** turns it off. Everything about it except the lens was tested with a stand-in camera; the lens, the tilt sensors and the live brightness and sharpness readings were not, because the Simulator has none.
- **Side view** — a photo from the side in *portrait* and in *landscape*: the boxes should land on the piles (they follow the camera's roll; I could only check roll on landscape photos). Photos from the camera, and photos chosen from the library.
- **The table card** — turns the screen on its side when opened and upright again when closed, keeps the screen awake, shares as a picture and a PDF.
- **The Live Activity** — start a night, lock the phone: the clock counts on the Lock Screen and in the Dynamic Island (iPhone 14 Pro and later); tap **Break**: the app opens with the clock stopped; **Resume** starts it again. (Verified in the Simulator on iPhone 16, including the Lock Screen, the island, and the break link; the system asks once "Allow Live Activities?".)
- **The break reminder** — the notification permission prompt and the notification, and that it doesn't fire while the clock is on a break.
- **Share sheets** for the settle-up text and picture, the night summary and the weekly recap; the helpline links open the dialler and messages.

## Decisions I made that you may want to change

- **USD only for 1.0**, but all money formatting and parsing is currency-aware, so adding currencies is a data change.
- **Guest mode is the first choice** on the welcome screen; email sign-in second.
- **The result screen is deliberately restrained** ("Net result", "Up"/"Down", no celebration).
- **Offline:** everything works on the phone; changes are saved there at once and sent when there is a connection.
- **Photos are held in memory and sent; nothing is written to the phone.** Retention on the server is a fixed 30 days (B2), not a per-user setting. A night's photos are deleted when the night is.
- **Custom chips** can be started even when they don't add up to the buy-in ("Start anyway"), with a warning showing the difference.
- **Prototype-era local data is discarded at launch** (an unfinished single-player game, unsent saves, the last result). Games already on the server are imported as one-player nights.
- **A night is the one unit:** a single-player game is a one-player night; Poker Health, History and Stats are computed on the phone from the nights it holds.
- **The break is irrevocable** by design: once started (24 hours, 3 or 7 days) there is no "end early". Only *starting* a night is blocked; History, Stats, finishing a night in progress and Settings all work. Say if you'd rather it could be cancelled.
- **Limits are only ever the person's own.** Nothing is on by default except the 20-hour weekly time limit Poker Health already used.
- **Stats count a night only if the person played in it and it was closed;** per-hour rates need ten nights.
- **Chip-set rules:** a one-colour stack needs at least five chips; one cash-out takes at most four photos; a photo is called blurry below a sharpness of 250 (sharp samples score 760–1,800; heavily blurred ones, under 60).
- **Side-view counting is a beta, and says so.** It reads piles from the side or a low angle, uses the tilt the phone recorded in the photo (nothing else about the photo is sent), and always shows its answer as an estimate to check. It needs the chips' printed rim stripes, and at least one red, green or blue pile in the photo to learn the chip size from.
- **The Live Activity's Break button opens the app** and stops the clock there. On iOS 16 a Live Activity can't run an action without opening the app.
- **The share cards hold no names and no results** (the settle-up card does hold who pays whom, because that is its job). The week recap shares hours, never money.
- **The camera guide is on by default** and the standard camera is always one tap away, and a switch in Settings (*Camera tips*) turns it off. You asked for it only if it had no negative effects, and I can't prove that without a phone: I take the photo with Apple's standard photo capture (the main camera, balanced quality, no flash — I can't compare it with the system camera without a phone), never lock the shutter, fall back to the standard camera if the lens won't start, and used the photo check's own light limits (its sharpness limit is stricter than the guide's, on purpose, so the guide says "soft" only when it is sure). The cost of the guide being wrong is some nagging, not a lost photo. What it does lack, next to the system camera, is zoom, tap-to-focus, flash and lens switching (it focuses and exposes continuously by itself), so "Standard camera" is there for those too. Say if you would rather it were off until you have tried it.
- **Chip Counter is in the Utilities category** in the draft, not Games.

## Not done, and why

- **Crashlytics, App Check, a weekly-hours widget, tournament mode** — waiting on A6–A8, A11.
- **A real-photo regression for the top-view counter** — `PokerChipApp/test_photos/` holds real chip photos (git-ignored; taken at a home game), used to set the blur threshold and, for side view, the seven you sent. They have counts only for the side-view set.
- **VoiceOver and iOS 16 runs** — no physical device; the Simulators here are iOS 18 only. The accessibility audit (Xcode's) passes on the iPhone 16 with 14 documented false positives; AX4–AX5 text sizes weren't checked.
- **Phase 0 "before" screenshots** were rebuilt from the checkpoint commit with a throwaway flag (`docs/qa/README.md`), since the original can't get past its sign-in without real credentials.
- **CI** — `.github/workflows/ci.yml` is written but has never run (no remote).

# Questions and owner-only steps

Everything open is in plain words below, each with the answer I'd give. Nothing marked "open" has been done, deployed or pushed.

## Answered — thank you

| # | Question | Your answer | What happened |
|---|---|---|---|
| A1 | Delete the unused image sets | Yes | Done: the War Card Game assets, `StudioLogo`, the old splash and `pokerbackground` are gone (one commit, easy to revert). **Left alone on purpose:** `Archive.zip` (5.5 MB, repo root) — it isn't an image and it isn't in git, so deleting it can't be undone. Say "delete Archive.zip" and it goes. `pokerchip.imageset` (13 KB) is also unreferenced and wasn't on the list; say so if you want it gone too |
| A2 | Keep `pytest` and `httpx` as test-only packages | Yes | Kept; they are in `requirements-dev.txt` only, not in the production image |
| A3 | Portrait only, except the table card | Yes | Unchanged |
| A4 | Delete the old single-player result model | Yes | Done: `SessionResult.swift` and its decoding test are gone. (The server's `/complete` and `/weekly-summary` endpoints are no longer called by the app; remove them once every installed copy has updated) |
| A5 | Live Activity / Lock Screen widget | Yes | **Built** — see the next section. The weekly-hours widget that goes with it needs an App Group (A11) and isn't built |
| — | Helpline | "Use 1-800-MY-RESET" | It is the only US number on the card (call, text and website), with the date the numbers were last checked |

## Open — decisions I'd like from you

**A6. Tournament mode — yes or no?** It changes the night model (blind levels, a level clock, re-entries, a payout table), the sync format and the server's validator, and it is a different product from a cash-game ledger. If yes, which pieces: blind levels with a countdown and a "level up" alert; re-entries; fixed payout percentages; seating balance (I'd skip that). *I'd say: not for 1.0.*

**A7. Crashlytics — yes or no?** It reports crashes from phones in the wild. It uses the Firebase package you already have (no new package), but it needs a build-phase script to upload symbols, switching Crashlytics on in the Firebase console, and a line in the privacy label ("Crash Data"). Without it, the only crash signal after release is TestFlight's and what people tell you. *I'd say: yes, for 1.1, after you've seen how TestFlight goes.*

**A8. Firebase App Check — yes or no?** It lets the backend refuse requests that don't come from your genuine app (App Attest). Needs the `FirebaseAppCheck` product, the App Attest capability (a paid team), console enforcement and a backend check. The backend already requires a valid sign-in and limits each person to 60 photos an hour. *I'd say: after launch, if you see abuse.*

**A9. Remove the unused Firebase Analytics library?** It's linked but switched off in `GoogleService-Info.plist` and nothing calls it. Removing it makes "no analytics" true of the app's code too, and keeps Apple's privacy report shorter. *I'd say: yes.*

**A10. Delete `Archive.zip`?** See A1.

**A11. The weekly-hours widget and the App Group — yes or no, and do you have a paid Apple Developer account?** A Home Screen or Lock Screen widget showing this week's hours against your limit has to read what the app writes, which needs an **App Group** — and I believe App Groups need a paid developer team (a free "Personal Team" can't sign them; Xcode will tell you). I was also stopped from writing the two entitlement files by the assistant's own permission check, so I didn't try to get round it. What's built instead needs neither: the Live Activity gets everything it shows from the app directly. If you want the widget: it is about 150 lines (a timeline provider and two small views, already designed), plus adding the capability to both targets in Xcode (Signing & Capabilities → + Capability → App Groups → `group.Vanarp.PokerChipApp`). *I'd say: when you have the paid team.*

**A12. What do you call the white chip with blue edge spots?** In your seven photos it is the one chip that is neither red, green nor black. The counter names it **White** (that's its body) unless the night's colours don't include White, in which case it names it **Blue**. If your set has both a white chip and a blue chip, tell me which this is, and I'll make sure the counter doesn't confuse the two.

**A13. Photos of real stacks, please.** The side-view counter is only validated on piles of one or two chips (18 of 28 piles counted right across your seven photos). A stack of about 5, one of 10 and one of 20, shot low from the side, with the true counts, would let me measure the case it was really built for. Drop them in `PokerChipApp/test_photos/side_view/` with their counts, or send them here.

## Open — release inputs (you said to circle back)

7. **Apple Developer team and the final bundle ID.** The project uses team `NZZPYJZMR4` and `Vanarp.PokerChipApp` (the widget is `Vanarp.PokerChipApp.Widgets`).
8. **Support email, privacy-policy URL, terms URL.** Set them in `PokerChipApp/Views/Core/AppEnvironment.swift` (`SupportConfig`). Settings hides a row whose value is empty, so nothing placeholder ships — but App Store Connect needs the privacy-policy URL regardless. Drafts of both documents to publish are in `docs/legal/`.
9. **The App Store name.** The Home Screen name is "Chip Counter"; check it's free. A subtitle, description and keywords are drafted in `docs/APPSTORE.md`.
10. **May the backend be deployed on a billed Google Cloud project?** You'd run it; I never will. `ChipVisionService/deploy.sh` prints the plan; `--apply` runs it.

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

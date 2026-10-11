# Architecture

PokerChipApp is a SwiftUI iPhone app (iOS 16.4+, Xcode 16) plus a small FastAPI backend, **ChipVisionService**. The app never talks to Firestore or Storage directly — only to the backend, which uses the Firebase Admin SDK. Firebase Auth is the one thing the app uses directly.

```
iPhone app ──Firebase Auth (guest / email / Apple)──▶ Firebase Auth
    │
    └─ HTTPS + Bearer ID token ──▶ ChipVisionService (Cloud Run, FastAPI + OpenCV)
                                         ├─▶ Firestore   sessions/{uid}/nights/{nightId}   (and the legacy games/{sessionId})
                                         └─▶ Storage     chip-photos/{uid}/{sessionId}.jpg   (private; signed URLs)
```

`firestore.rules` and `storage.rules` deny every direct client request, so "who can read what" is decided in the backend's tested code.

The app is **local-first**: a night lives on the phone, in files, and is mirrored to the backend when there is a connection. Nothing in the app has to wait for the network except counting chips from a photo, and that has a by-hand alternative.

## The app

Three folders are Xcode *synchronized folders* — `PokerChipApp/Views/`, `PokerChipApp/Shared/` and `PokerChipWidgets/Sources/`: a new `.swift` file there compiles without editing the project file, and any non-source file placed there is bundled (so docs and images never go there). `Authentication/` and the test groups are classic groups with explicit entries, so a new test file has to be added to its test target.

```
PokerChipApp/
├─ PokerChipAppApp.swift       entry point; starts Firebase (not in UI-test mode); never signs anyone out;
│                              the app delegate answers "which orientations?" from OrientationLock
├─ ContentView.swift           root: splash + auth gate + the four-tab shell, each tab with its own NavigationStack and the routes;
│                              keeps the Live Activity in step with the night; opens chipcounter:// links
├─ PrivacyInfo.xcprivacy       privacy manifest (see "Releasing")
├─ Localizable.xcstrings       String Catalog: every user-facing string, English for now
├─ Shared/                     compiled into the app and the widget extension: NightActivityAttributes, NightLink, ActivityMoney
├─ Authentication/             Firebase Auth wrapper, AuthViewModel, welcome + email screens
└─ Views/
   ├─ Core/                    app-wide state with no screens
   │   ├─ GameSetup.swift          what the setup screens collect: buy-in, players, names, colours, chip set, fixed values
   │   ├─ Persistence.swift        JSONDefaultsStore, Stores (last setup, owned chip set), retired-key clean-up
   │   ├─ Money.swift              Money + DurationFormat: locale-aware formatting and parsing, spoken forms
   │   ├─ AppPreferences.swift     UserDefaults keys (PrefKey), SplashPolicy
   │   ├─ AppEnvironment.swift     -UITestMode / -ResetState / -UITestLiveNight / -UITestGuidedCamera flags, version string, SupportConfig
   │   ├─ OrientationLock.swift    portrait everywhere except the table card
   │   └─ PlatformHelpers.swift    LoadState, Haptics, ConnectivityMonitor
   ├─ Nights/
   │   ├─ Model/                   GameNight and the pure rules over it: NightMath, Settlement, NightCoding,
   │   │                           NightSummary, NightStats (weekly totals, WeekTrend), StatsEngine, NightCSV,
   │   │                           HistoryFilter, HealthyPlay (limits, nudges, breaks, helplines)
   │   ├─ Store/                   NightRepository + FileNightRepository, NightStore (+Setup), SessionReminders,
   │   │                           NightActivityController (the Live Activity)
   │   ├─ Sync/                    NightSync
   │   └─ Screens/                 Players, LiveNight, BankCheck, SettleUp, History, NightDetail, Stats,
   │                               ShareCards, banners (store problems, undo)
   ├─ Denominations/           DenominationEngine (solver + ChipPlanner), BlindsPlanner, ChipSetView,
   │                           CustomDenominationView, TableCard (card, export, full-screen view)
   ├─ Session/                 cash-out (ReviewCountsView + CashOutViewModel), PhotoQuality, PhotoReviewView,
   │                           ChipPhoto (+ PhotoAngle, StackMark), CameraPose, CameraSupport, GuidedCamera,
   │                           FramingAdvisor, FrameAnalysis, ResultView, PokerHealthView, WeeklySummary
   ├─ Networking/              ChipVisionAPIClient (+ DEBUG-only UI-test stubs), APIConfig, Prewarm, image preparation
   ├─ DesignSystem/            tokens, components, ChipView, PokerButton, FlowLayout, nav/tab-bar appearance (see DESIGN.md)
   ├─ Settings/                SettingsView (account, backup, healthy play, privacy)
   ├─ Auth/                    Sign in with Apple button (compiled only with the SIGN_IN_WITH_APPLE flag)
   └─ …                        Home (StartScreenView), BuyIn, DenominationStyle, Suggested (DenominationsView), Splash, Theme

PokerChipWidgets/              the Live Activity extension (Sources/: bundle, NightLiveActivity, WidgetPalette)
```

### Navigation

A `TabView` with four tabs — **Play, History, Stats, Settings** — each in its own `NavigationStack`. `NavigationCoordinator` owns the Play tab's `path: [AppRoute]` and the selected tab. Routes carry their data (`.chipStyle(GameSetup)`, `.cashOut(CashOutTarget)`, `.night(UUID)` …), so the stack is plain value types and `navigationDestination(for:)` — available on iOS 16 — maps a route to a screen. (`navigationDestination(item:)` and `sensoryFeedback` are iOS 17 and are not used.)

The Play flow is `Home → Buy-in → Players → Chip values → Suggested | Custom → Live night → Cash out → Bank check → Settle up → Result`. The tab bar is hidden on every screen of it (`.toolbar(.hidden, for: .tabBar)`), so setting up or running a night has the whole screen.

- Starting a night **replaces** the stack with `[.night(id)]`. Back from the night lands on Home, where the Resume card is, rather than on a setup screen that would start a second night.
- Signed out → a separate `NavigationStack { AuthenticationView }`. Signing in swaps the root; the path is reset on every sign-in or sign-out.
- A night is always opened by id and read from the store, so a screen never holds a stale copy.

### The night, start to finish

1. **Setup.** Buy-in, players (names, regulars suggested from past nights, where), chip colours, and — optionally — the chip set the person owns. `GameSetup` is remembered so "same as last time" is one tap.
2. **Chips.** `ChipPlanner` (below) proposes how to deal the buy-in; **Suggested** shows it, **Custom** lets the person type their own values. Either way, `NightStore.startNight(from:…)` creates the `GameNight` with everyone in for the buy-in and the clock running from `startedAt`.
3. **Live night.** The clock is **not a counter a view owns**: it is worked out as `now − startedAt − time on breaks` every time it is drawn (`TimelineView` for the ticking), so killing the app, a dead phone or navigating away can't lose or restart it. Rebuys are one tap with an undo window; each is its own `BuyInEvent`. A **break** records a `PauseInterval`; the clock holds still and the time isn't counted as played (a unit test builds a night of random breaks and checks played + break = the night to within a second).
4. **End the night.** Stops the clock (an open break ends there). The same screen becomes the cash-out list.
5. **Cash out**, one player at a time: count the chips (steppers by colour; or from photos — below) or type an amount. The total, "money in" and the net are shown as you go.
6. **Bank check.** Σ cash-outs must equal Σ buy-ins. A shortfall can be recorded as a tip/rake, put on one player, or shared out; chips can't turn up from nowhere, so an overage can only be put on someone or shared. The choice is stored with the amount it was made for.
7. **Settle up.** `Settlement` turns the nets into at most n − 1 payments; the screen offers text and picture to share. **Close the night** saves it to History; **Result** shows the person's own outcome.

### Money

All arithmetic is integer cents (`Money.cents`); `Double` appears only at the edges (a text field, an API field). Display goes through `Money.format`/`formatSigned`/`compact`/`spoken` (locale-aware, currency code `USD` for v1.0), and typed input through `Money.parse` (strict: `"25,5"` in a US locale is rejected, not read as 255).

### Game nights, the store and sync

A **night** (`Views/Nights/Model/GameNight.swift`) is the unit of everything: who played (`PlayerLedger`s with each buy-in or rebuy as its own `BuyInEvent`), when, the chips used, the pauses, how the bank was reconciled, and a `myPlayerID` saying which player is the person holding the phone. A single-player game is simply a one-player night. Money is whole minor units (cents) end to end; `NightMath.swift` holds the pure rules (totals, the bank check, resolutions, playtime) and `Settlement.swift` turns nets into at most n − 1 payments. Both are property-tested over thousands of random nights.

- **Bank resolutions** record the difference they were made for, so correcting a cash-out afterwards makes the night ask again instead of silently reusing a stale choice. Only a shortfall can be a tip/rake; "assign" treats one player's count as off by the difference; "split" shares it cent by cent (the first few people take the extra cent).
- **`NightStore`** (`Views/Nights/Store/`) is the only thing that changes a night. Every edit goes through `mutate`: the night is canonicalised (all dates at whole milliseconds, so memory = disk = wire), stamped strictly later than its previous version even if the clock was set back, written to disk at once, and queued for the server. Storage is a `NightRepository` — one JSON file per night in Application Support, written to a temporary file and renamed into place; an unreadable file is moved to `quarantine/` (never deleted); a night from a newer schema is left alone and not shown; an older one goes through the stepwise `NightMigrator`. A full disk is reported and retried, not swallowed.
- **`NightSync`** runs after a quiet moment on any change, on launch/foreground, and on sign-in: push every queued night (`PUT /v1/nights/{id}`, idempotent), then pull what changed since the cursor (starting 10 s before it, to survive clock skew between server instances) and merge last-writer-wins by each night's own `updatedAt`. If the server answers `applied: false` it has kept a later edit, which the app adopts. Failures never lose anything: offline, signed out, a refused night (kept on the phone and counted), a server without the endpoints (treated as "not available yet", not as breakage). Signing in as a different account queues every night on the phone for that account.
- **Deleting** keeps the full night locally for an Undo window (8 s), then reduces it to a marker; the server stores only the marker (no names, place or notes) from the start, and deletes the night's stored photos.
- **Server**: `sessions/{uid}/nights/{id}` with a server-assigned `serverUpdatedAt` that the pull is ordered by (a single-field index Firestore makes by itself). Writes run in a transaction. The rules live in the pure `ChipVisionService/app/nights.py`; the app's encoder and the server's validator are pinned to the same JSON by a golden string in both test suites.
- **Prototype-era state** (an unfinished single-player game, unsent saves, last result) is discarded at launch (`Stores.removeRetiredKeys`); single-player games already saved on the server are imported as one-player nights (`POST /v1/nights/import-legacy`).

### History, stats and healthy play

All of it is computed on the phone from the nights it holds, so it works offline and never needs the server.

- **History** lists nights newest first, grouped by month, searchable (place, player, note) and filterable (`HistoryFilter` is a pure value). Swipe to delete with Undo; a night that was never settled can be picked back up. **Night detail** shows the ledger, who paid whom, place and notes (editable), and the chip photos stored for that night.
- **Stats** (`StatsEngine`, pure and tested against a hand-computed eight-night fixture) counts only closed nights the person played in, in the latest currency: net, bankroll over time, best/worst night, streaks, and breakdowns by month, place, weekday (Monday first) and stake. A per-hour rate needs at least ten nights, because fewer says nothing; until then the screen says so. **Export CSV** (`NightCSV`, RFC 4180) round-trips: parsing the export gives back the same rows.
- **Poker Health** is the week's playtime, last week for comparison and the last four weeks beside the limit the person set. Its chip wears from gold to a skeleton as the limit is approached — for fun, with a spoken description.
- **Healthy-play tools** (`HealthyPlay`, Settings → *Healthy play*): a weekly time limit; an optional weekly loss limit; a reminder after N hours of *play* (breaks excluded; a local notification, permission asked only when it is switched on); and a **break** the person commits to (24 h / 3 days / 7 days) during which a new night can't be started. The break can't be shortened once chosen — that is the point of it. Nothing else is blocked: History, Stats and finishing a night all still work. Messages are plain ("You're close to the 20-hour limit you set") and a dismissed one doesn't come back that week unless it gets stronger. A card in Settings and on Poker Health links to a helpline for the person's region (`HelplineDirectory`; the US line changed in January 2026 — see QUESTIONS).

### Choosing chips

`DenominationEngine.swift` holds two layers, both pure:

- **The solver** (`calculateFlexibleChipDistribution`, unchanged in behaviour) — exact sum to the nearest nickel in cents; a clean value ladder (5¢, 10¢, then multiples of 25¢) with at most one nickel-safe exception on the lowest colour; values strictly rising and counts strictly falling with colour rank; 20–30 chips a player as a soft goal that yields to exactness and shape. These invariants are what the property tests check.
- **`ChipPlanner`** wraps it with what the person owns and wants. `ChipInventory` is how many chips of each colour are owned (presets of 100/200/300/500 split evenly, every count editable) and, if the values are printed on the chips, those values. `ChipConstraints` turns that into a per-player cap (owned ÷ players) and fixed values. The planner returns up to three **options** over the same buy-in (the balanced stack; fewer chips to count; a smaller smallest chip) and, when it can't, a typed **failure** with something that would work: *too small* (and the next buy-in that fits), *set too small* (play with fewer, lower the buy-in, or leave a colour out — each checked to really work), *no exact split* for printed values (the nearest amounts that do), *values conflict*, *no colours*. With no inventory and no fixed values its recommendation is exactly the solver's. A one-colour stack within a set needs at least five chips (fewer can't make change).
- **`BlindsPlanner`**: the small blind is a whole number of the smallest chip, the big blind twice that, and the stack comes out near 100 big blinds; the person can step them up or down.

The Suggested screen shows the option, lets the person fix any colour's value (the rest is worked out around it), shows chips needed against chips owned per colour, explains itself ("Why these values?"), and can show the **table card**.

### The table card

A full-screen landscape card with each colour, its value, how many each player starts with, and the blinds — large enough to read from across the table, and kept awake while it is up. `TableCardArtwork` is drawn to whatever size it is given, so the same view fills the phone and becomes the picture that is shared (PNG and PDF, via `ImageRenderer`, written to temporary files for the share sheet). It carries no names, places or dates.

Landscape is allowed in the Info.plist but the app delegate answers `OrientationLock.current` (portrait) everywhere; the card widens it to landscape while it is on screen and puts it back when it goes (`requestGeometryUpdate`, iOS 16+).

### Counting chips from a photo

Counting by hand never needs a network. A photo is an optional shortcut, and only ever a starting point:

1. A photo from the camera (which coaches the shot — "The camera guide" below) or the library is first looked at **on the phone** (`PhotoQuality`: sharpness as the variance of the Laplacian of a 256-pixel copy, mean brightness, size). A poor one asks the person to retake it or use it anyway; nothing is sent until they decide.
2. The photo is resized (≤1600 px), sent, and held in memory only. The server returns counts **and the position of every chip** (`detections`: centre and radius as fractions of the photo's width). An older server without `detections` still counts; there is just nothing to circle.
3. **Photo review** draws a circle on every chip. Tapping one changes its colour or removes it; "a chip is missing" adds one where the person taps. Every edit adjusts the cash-out counts by the same amount (the counts are the source of truth — the circles are a way of fixing them; steppers still work and stay in step). Chips in colours the night isn't using are left out and said so.
4. A second, third or fourth photo **adds** to the counts, for chips that won't fit in one frame; each chip should be in only one photo.
5. Opening a night or a cash-out wakes the counting service (`Prewarm`, at most every five minutes, `/healthz`, no sign-in), because a service that scaled to zero can take seconds to answer the first photo.

#### From the side

The person chooses how the chips are laid out — **from above** (spread on the table, each one a circle) or **from the side** (standing in piles). A side photo goes to the same endpoint with `view=side` and the camera's tilt (`pitch`, `roll`, `focal35`), which the app reads from the photo's own metadata (Apple's accelerometer reading in the maker note; `CameraPose`) or takes from the motion sensors at the shutter. Those three numbers are the only metadata ever read or sent.

The server (`side_view.py`, classical CV) finds each pile by the colour of the chips' edge-spots, counts a short pile from the number of rings of spots it can see and a tall stack from its height (a chip is about 0.085 of its diameter thick), and returns `stacks` — a box, a tilt, a colour and a count for each. **Photo review** draws a box with a count badge on every pile: tap one to change the count or colour, remove it, or add a pile the photo missed; the cash-out counts move by the same amount (a 600-edit random test holds them in step). A side count is only ever an estimate and is never reported with high confidence; the screen says so and asks the person to check every pile. An old server that answers a side photo as if it were a top view is recognised and refused with a notice rather than shown as piles. On seven real photos the counter found 26 of 28 piles and got 18 of them exactly right; see `ChipVisionService/README.md` for what is and is not known.

#### The camera guide

`CameraScreen` opens the **guided camera** unless the person turned it off (Settings → *Camera tips*), switched to the standard camera from inside it, or the phone can't run it — then it is the system camera with a static frame (`CameraPicker`, `FramingGuideView`). The guide reads three things, ten times a second: how the phone is tilted (`CoreMotion` gravity, the same maths as `CameraPose`), how bright the live picture is and how sharp (`FrameAnalysis`, the same measures `PhotoQuality` applies to a finished photo, on a 256-pixel copy), and how fast it is turning. `FramingAdvisor` (pure) turns a reading into one sentence — hold it flatter / lower / straighter / steadier, add light, move away from glare — with a fixed order of importance; from above only the pitch matters, from the side the horizon must be level too. `FramingCoach` smooths the readings and makes a change of advice hold for half a second (a second before "ready"), so the words don't flicker. A level line shows the horizon for side photos. It only ever advises: the shutter is never locked. The photo is taken with Apple's standard photo capture (`AVCapturePhotoOutput`, the main wide camera, balanced quality prioritisation, no flash); how it compares with the system camera's own output has not been checked on a phone. It has none of the system camera's extras — zoom, tap-to-focus, flash, lens switching — and focuses and exposes continuously by itself; the standard camera is one tap away for those.

The camera behind it is a `CameraBackend` (live AVFoundation, or in debug builds a stand-in that shows a still picture and walks through scripted readings — `-UITestGuidedCamera`), so everything but the lens is tested. If the camera can't start within six seconds, stops, or is taken over by a call, the guide offers the standard camera. **The live camera path has not been run** — the Simulator has no camera; it needs trying on a phone (QUESTIONS B5).

### The Lock Screen and the Dynamic Island

A night in progress shows its clock, the money on the table and the number of players on the Lock Screen and in the Dynamic Island (`PokerChipWidgets`, an App Extension embedded in the app; iOS 16.2+ ActivityKit). `NightActivityController` starts the activity with the night, updates it when a rebuy or a break changes what it shows, and ends it when play is called; if Live Activities are off or the system refuses, nothing else changes. **The clock is not a number the app keeps sending**: the state carries `clockStart` (the moment the clock would read zero had it never stopped), and the widget draws `Text(clockStart, style: .timer)`, which the system counts itself — so it is right with the app closed. On a break the state carries the played seconds instead and the clock is still. Buttons on it open `chipcounter://night`, `…/break` and `…/resume`; the app parses them with `NightLink` (shared with the widget) and acts on the night in progress (`NightStore.handle`), asking nothing it wouldn't ask in the app. The extension has no data of its own and no App Group; a weekly home-screen widget would need one (QUESTIONS A11) and is not built.

### Share cards

Pictures for the group chat, drawn with `ImageRenderer` and shared with `ShareLink`: the settle-up card (who pays whom), a **night summary** (date, place, players, time played, money in play, chip values — no names, no results) and a **weekly recap** (hours per day and against last week — never what was won or lost). The table card is the fourth.

### Networking

`ChipVisionAPIClient` is a struct of closures (`transport`, `baseURL`, `tokenProvider`, `sleep`), so tests script the network completely. Behaviour: 15 s idle / 60 s total timeouts; retry 502–504 and transient `URLError`s up to 3 attempts with 0.6 s / 1.5 s backoff; one forced token refresh on a 401; typed `ChipVisionAPIError`s with plain-language descriptions. Offline is reported immediately, not retried.

`APIConfig` reads `APIBaseURL` from Info.plist, which the `API_BASE_URL` build setting fills per configuration. A Release build with the `REPLACE_WITH_CLOUD_RUN_URL` placeholder, the old camera placeholder, a dev-only local-network string, or a non-HTTPS address fails the "Check Release configuration" build phase when archiving.

### Auth

`AuthViewModel` reflects Firebase's own state listener (`unknown → signedOut | signedIn`). Firebase keeps the user in the keychain, so a returning person stays signed in; the old forced sign-out on launch is gone. Guest mode is Firebase anonymous auth and can be upgraded in place (`link`), keeping the same uid and data. Account deletion calls `DELETE /v1/account` **first**; only on success is the device cleared and the user signed out — an offline attempt changes nothing.

### Releasing

`docs/RELEASE.md` is the runbook; the pieces in the code:

- `PrivacyInfo.xcprivacy` declares the one required-reason API the app uses (UserDefaults, reason CA92.1) and the data it sends to its own service — email, name, photos and the nights' content, linked to the account, none for tracking.
- `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are set once, on the project, so the app, the extension and the tests can't disagree (an App Store upload is refused if the extension's version differs); `scripts/bump-build.sh` raises the build number.
- The **Check Release configuration** build phase (`ACTION=install`, i.e. archives) fails on: the backend-address placeholder, a non-HTTPS address, the old camera placeholder text, a development-only local-network string, a missing privacy manifest, a missing widget extension, or a widget whose version differs from the app's. A local Release build only warns. (The phase declares the widget's `Info.plist` as an input: Xcode's script sandbox otherwise refuses to let it read the file, which once made the version check fail on matching versions.)
- The app icon has light, dark and tinted variants; there is no iPad support, and portrait is enforced at run time (the table card widens it).

### Testability

`-UITestMode` makes the app start with a stubbed signed-in guest and an in-process fake backend (`UITestStubs`, DEBUG builds only; its photo answer includes 27 chip positions — or five piles for a side photo — and a sample picture to match, because a UI test can't drive the camera or the library); `-ResetState` wipes saved state first; `-UITestLiveNight` starts a night in progress so the Lock Screen can be looked at; `-UITestGuidedCamera` swaps the guided camera's lens for the stand-in. Every interactive element has an `accessibilityIdentifier`.

**One SwiftUI trap, found the hard way:** an `accessibilityIdentifier` on a *container* replaces the identifiers of the elements inside it as far as XCUITest is concerned. Put identifiers on a heading or on the leaf, never on a card that holds other identified elements.

Unit tests are hosted by the app target (`@testable import PokerChipApp`).

## The backend

See `ChipVisionService/README.md`. Pure logic is separated so it can be tested without a network: `nights.py` (the sync rules), `weekly.py` (time-zone bucketing), `photos.py` (decode, limits, metadata stripping), `chip_detection.py` (the classical-CV counter for photos from above, which also returns where each chip is), `side_view.py` (piles seen from the side, with the camera's tilt), `ratelimit.py`. `firebase.py` is the only module that touches Firebase; tests replace Firestore and Storage with in-memory fakes (`tests/fakes.py`). The old per-game endpoints (`/complete`, `/weekly-summary`) are still served for older app versions; the app no longer calls them.

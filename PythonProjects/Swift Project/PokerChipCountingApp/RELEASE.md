# Release runbook — Chip Counter 1.0

Everything here is either something already verified (and says how) or an owner-only step (marked **Owner**). Nothing in this file has been run against your Apple or Google accounts: archiving, uploading, deploying and submitting need logins and, for Cloud Run, a billing account.

Open items and the questions that block them are in `docs/QUESTIONS.md`. App Store text, the privacy-label answers and the review notes are in `docs/APPSTORE.md`; the draft privacy policy and terms are in `docs/legal/`.

## The order things happen in

1. **Deploy the backend first** (it must understand everything the new app sends — the nights API, `view=side` photos, the circles and piles in the response). An old server refuses the nights fields it doesn't know with a `422`; the app then keeps the night safely on the phone, but backup stays off until the server is current.
2. Put the backend's URL into the app's Release build setting.
3. Archive, validate, upload, TestFlight, submit.
4. After release, watch for problems (below) and apply the optional hardening.

## What the project is

| | |
|---|---|
| App | **Chip Counter** (`CFBundleDisplayName`), bundle ID `Vanarp.PokerChipApp`, iPhone only, iOS 16.4 and later, dark only |
| Widget extension | `PokerChipWidgets`, bundle ID `Vanarp.PokerChipApp.Widgets` — the Live Activity (the night's clock and money on the Lock Screen and in the Dynamic Island). Embedded in the app; ships and signs with it |
| Team / signing | `DEVELOPMENT_TEAM = NZZPYJZMR4`, automatic signing |
| Version | `MARKETING_VERSION` **1.0**, `CURRENT_PROJECT_VERSION` **1** — one place each, at the top of the project's build settings, shared by the app and the extension. `scripts/bump-build.sh 2` raises the build number |
| Backend | Cloud Run service `chip-vision-service`, project `pokerchipapp-f7a84`, region `us-central1` |
| Link scheme | `chipcounter://night` (`/break`, `/resume`) — opened by the Lock Screen's Break button |

If you change the bundle ID, change it in three places, in this order: the app target, the extension target (`<app id>.Widgets`), and the Firebase console (a new iOS app entry, with its `GoogleService-Info.plist` replacing the one in `PokerChipApp/`). The Sign in with Apple capability and the API-key restriction follow the bundle ID.

## Before an archive: the checklist

Run these from the repository root. All of them were run for this release (see `docs/PROGRESS.md` for the numbers); re-run them if anything changed.

```bash
# Backend tests (create the venv once: python3 -m venv .venv && .venv/bin/pip install -r ChipVisionService/requirements-dev.txt)
cd ChipVisionService && ../.venv/bin/python -m pytest -q && cd ..
```

```bash
# iOS unit tests
xcodebuild test -project PokerChipApp.xcodeproj -scheme PokerChipApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PokerChipAppTests
```

```bash
# iOS UI tests (about 40 minutes: run them while you do something else)
xcodebuild test -project PokerChipApp.xcodeproj -scheme PokerChipApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PokerChipAppUITests
```

`xcodebuild test` leaves about 2 GB of simulator clones behind each run. Reclaim them with `xcrun simctl --set ~/Library/Developer/XCTestDevices delete all` (never during a run).

## Deploy the backend (Owner)

The exact commands are in `ChipVisionService/README.md → Deploying`; `ChipVisionService/deploy.sh` runs the same steps and, without `--apply`, only prints them. In outline:

1. Enable the APIs and create the `chip-vision-runner` service account with `storage.objectAdmin`, `datastore.user`, `firebaseauth.admin` and `iam.serviceAccountTokenCreator`.
2. Build the image and `gcloud run deploy chip-vision-service` (`--memory 1Gi --timeout 60 --min-instances 0 --max-instances 3`).
3. `firebase deploy --only firestore:rules,firestore:indexes,storage` — denies every direct client request.
4. Apply the 30-day photo lifecycle: `gcloud storage buckets update gs://pokerchipapp-f7a84.firebasestorage.app --lifecycle-file=ChipVisionService/storage-lifecycle.json`.
5. In the Firebase console: **Authentication → Sign-in method → Anonymous → Enable** (guest mode — and the App Review demo — need it), enable the **Apple** provider if you ship Sign in with Apple, and restrict the iOS API key to the bundle ID.
6. **Set a budget alert** so a surprise can't become a bill. Create a budget on the billing account first (console: Billing → Budgets & alerts → Create budget; for example $5 a month with alerts at 50%, 90% and 100%). The service is sized to stay inside the free tier — a game is two requests — so an alert that fires means something is wrong.

Check it: `curl https://<service url>/healthz` answers `{"status": "ok"}`; `curl https://<service url>/readyz` answers 200 once Firebase is reachable.

### Rolling the backend back

Cloud Run keeps every revision. To go back:

```bash
gcloud run revisions list --service chip-vision-service --region us-central1 --project pokerchipapp-f7a84
gcloud run services update-traffic chip-vision-service --to-revisions=<previous revision>=100 \
  --region us-central1 --project pokerchipapp-f7a84
```

The nights API is idempotent and last-writer-wins, so a rollback loses no one's night; a phone that talked to the newer revision simply sends its changes again.

## Point the app at the backend

Release builds refuse to archive for the App Store while `API_BASE_URL` is still the placeholder (the "Check Release configuration" build phase fails with a message). Either set the Release value of `API_BASE_URL` in Xcode (target PokerChipApp → Build Settings), or pass it on the command line as below. Nothing else in the project changes between a test build and a release.

The same phase also refuses an archive that has a non-https backend address, the old camera-permission placeholder text, the development-only local-network permission, no privacy manifest, no widget extension, or a widget whose version differs from the app's. (A local Release build only warns, so you can still profile one.) If you change the phase, remember that Xcode's script sandbox lets it read only the files listed as its inputs; the widget's `Info.plist` is one.

## Archive and upload (Owner)

```bash
xcodebuild archive -project PokerChipApp.xcodeproj -scheme PokerChipApp -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/PokerChipApp.xcarchive \
  API_BASE_URL="https://<your Cloud Run URL>"
```

Then either open the archive in Xcode (Window → Organizer → **Validate App**, then **Distribute App → App Store Connect**) or, from the command line, with `scripts/ExportOptions.plist` (it uploads, so it needs Xcode signed in to your Apple ID):

```bash
xcodebuild -exportArchive -archivePath build/PokerChipApp.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath build/export
```

**What was verified without your account.** An unsigned Release archive (`CODE_SIGNING_ALLOWED=NO`, a stand-in https URL) builds, passes the placeholder check, embeds `PokerChipWidgets.appex`, and contains the privacy manifest. A Release archive with the placeholder URL fails the check, by design. **What could not be:** signing, the App Store validation, and any behaviour that needs the provisioning profile (Sign in with Apple, push). Validation in Organizer is the first thing to run.

### Sign in with Apple (Owner)

The button is compiled out until the capability exists, because the capability breaks signing on a free Personal Team. With a paid team: Xcode → target PokerChipApp → Signing & Capabilities → **+ Capability → Sign in with Apple**, then add `SIGN_IN_WITH_APPLE` to *Active Compilation Conditions* (Debug and Release). Account deletion for someone who signed in with Apple should also revoke their Apple token; that backend step is not written (`docs/QUESTIONS.md` → Apple and App Store).

## TestFlight plan

1. **Internal build (you, plus up to 100 people on your team).** Upload build 1. Install on a real iPhone and go through the device checklist (`docs/QUESTIONS.md` → real-iPhone checklist): photo counting end to end, the camera guide (the live tips; Settings → Camera tips turns it off), the table card turning on its side, the break reminder, the Live Activity (start a night, lock the phone, tap Break), the share sheets, the helpline links. Take the side-view photos of real stacks and send them back with their counts.
2. **Fix anything that comes up**, bump the build number (`scripts/bump-build.sh 2`), upload again. Keep the same version (1.0) until it ships.
3. **External testing (optional).** One group of 5–10 friends who play. Add the *what to test* note from `docs/APPSTORE.md`. The first build in an external group goes through Beta App Review (about a day). Run it for a week or two of real games.
4. **Exit criteria for submitting:** no crash you can reproduce; a night survives killing the app mid-game; sign-in, guest mode and account deletion work against the deployed backend; every item in the device checklist ticked or knowingly deferred.

There is no crash reporter in the app (`docs/QUESTIONS.md` A7). Until there is, TestFlight's own crash reports (Xcode → Organizer → Crashes) and what testers tell you are the only signal.

## Submit (Owner)

Everything for the App Store Connect page is in `docs/APPSTORE.md`: name and subtitle, description, keywords, the privacy-label answers, the age-rating answers to consider, the review notes (demo access is **Continue as guest**), and the screenshot list. Submission itself, and the answers to Apple's questionnaires, are yours.

Choose **phased release** for the first version: it releases to a growing share of automatic-update users over seven days and can be paused.

## If something is wrong after release

- **Pause the phased release** (App Store Connect → the version → Pause) while you work out the problem.
- A bad build can't be recalled. Either *Remove from Sale* (new downloads stop; installed copies keep working), or submit a fixed build and ask for an expedited review (Contact Us → App Review → request an expedited review, saying why).
- Most problems are in the backend, and those roll back in a minute (above).
- The app never depends on the backend to count by hand, time a night, rebuy, cash out or settle up: a backend outage costs backup and photo counting, not a game.

## After release (optional hardening)

Neither is done, both need your approval and a console change, and both are recommended for 1.1 (`docs/QUESTIONS.md` A7, A8):

- **Crashlytics** — see what crashes in the wild. Adds the `FirebaseCrashlytics` product (same package as Auth; no new package), a dSYM upload build phase, enabling Crashlytics in the console, and a line in the privacy label (Crash Data).
- **Firebase App Check** (App Attest) — lets the backend refuse requests that don't come from your genuine app. Adds `FirebaseAppCheck`, the App Attest capability, console enforcement, and backend verification.

## Pre-flight, one more time

- [ ] `API_BASE_URL` (Release) is the https Cloud Run URL
- [ ] Support email, privacy-policy URL and terms URL are set in `PokerChipApp/Views/Core/AppEnvironment.swift` (`SupportConfig`) — Settings hides a row whose value is empty, so nothing placeholder ships, but App Store Connect needs the privacy-policy URL regardless
- [ ] The helpline numbers are still current (`HelplineDirectory.verifiedOn` says when they were last checked)
- [ ] Version and build number are what you mean to upload
- [ ] The backend you deployed is the one from this commit
- [ ] The age-rating and privacy-label answers are yours

# Chip Counter (PokerChipApp)

An iPhone app for the host of a home poker game: work out chip values and starting stacks for a buy-in from the chips you actually own, run the night (rebuys, breaks, a clock that survives the app closing and keeps counting on the Lock Screen), count each player's chips at the end (by hand, or from a photo — from above or from the side — that you can correct, with a camera that tells you how to hold the phone), check the bank, and settle up in a few simple payments. History and Stats keep the nights on the phone; healthy-play tools (your own limits, a reminder, a break you commit to, a helpline) keep poker fun. It tracks chips and time — it moves no money and takes no wagers.

- **App:** SwiftUI, iOS 16.4+, Xcode 16. Open `PokerChipApp.xcodeproj`. The Lock Screen / Dynamic Island clock is a small extension, `PokerChipWidgets/`.
- **Backend:** `ChipVisionService/` — FastAPI + OpenCV in a container, using Firebase Auth, Firestore and Storage. See its README.

## Run it

```bash
# app: pick an iPhone simulator in Xcode and run, or
xcodebuild test -project PokerChipApp.xcodeproj -scheme PokerChipApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PokerChipAppTests

# backend tests (no network or credentials needed)
cd ChipVisionService && python3 -m venv .venv && . .venv/bin/activate \
  && pip install -r requirements-dev.txt && python -m pytest -q
```

Photo counting and backup need the backend: run `docker compose up --build` in `ChipVisionService/` (see its README) and point the Debug `API_BASE_URL` build setting at it. Without a backend the app still works end to end — nights are kept on the phone and you count by hand.

Launch the app with `-UITestMode` to run it against a stubbed sign-in and backend (what the UI tests do); `-UITestGuidedCamera` also swaps the camera for a stand-in, since the Simulator has none.

## Documentation

| | |
|---|---|
| `docs/QUESTIONS.md` | **Start here:** what needs you — approvals, console steps, exact commands |
| `docs/RELEASE.md` | The release runbook: signing, the backend deploy, TestFlight, what the build checks for you |
| `docs/APPSTORE.md` | The App Store page: text, privacy answers, review notes, screenshots |
| `docs/legal/` | Drafts of the privacy policy and terms to publish |
| `docs/PROGRESS.md` | What was fixed, with evidence and what was and wasn't verified |
| `docs/PLAN.md` | Scope, phases, risks |
| `docs/ARCHITECTURE.md` | How the app and backend fit together |
| `docs/HOW_IT_WORKS.md` | **The logic and the maths in depth:** how chip values are worked out, how a chip's colour and a stack's size are read from a photo at any camera angle, the night, sync and healthy-play rules, and a log of every design decision |
| `docs/DESIGN.md` | Tokens, components, measured contrast, accessibility decisions |
| `docs/QA.md` | Test commands, device matrix, visual-QA findings |
| `ChipVisionService/README.md` | Backend endpoints, privacy model, deploy steps |

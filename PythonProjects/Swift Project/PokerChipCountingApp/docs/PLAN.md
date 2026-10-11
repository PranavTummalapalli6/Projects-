# Plan

Take PokerChipApp from a single-player prototype to a trustworthy, App Store–ready v1.0 for recreational home-game players. Current status and evidence are in `PROGRESS.md`; what needs the owner is in `QUESTIONS.md`.

## Scope

The first pass fixed the **verified defects** in the prototype and made the UI more professional (Phases 0 and 1). On 9 October 2026 the owner gave the go-ahead for Phases 2–5: the prototype's single-player timer became a multi-player **game night**, with History and Stats, healthy-play tools, chips chosen from what the person owns, and counting from photos that can be corrected. On 10 October the owner answered the first batch of questions (delete the unused images; keep the test packages; portrait except the table card; delete the old result model; yes to a Live Activity), sent seven photos for **side-view counting**, asked for the US helpline to be 1-800-MY-RESET, for Phase 6, and for a **camera that helps line up the shot** as a stretch goal — all of which are now built. What is deliberately **not built** needs the owner (QUESTIONS A6–A8, A11): tournament mode, Crashlytics, App Check, and the weekly-hours widget that needs an App Group.

| Phase | What | State |
|---|---|---|
| 0 | Branch, checkpoint commit, docs, baseline | done ("before" screenshots captured late via a harness — see QUESTIONS → *Not done, and why*) |
| 1 | The 16 defects in the audit + design tokens and components + a professional pass on every screen | done and verified — see PROGRESS |
| 2 | Game Night: players, rebuys as ledger events, cash-outs, bank check, settle-up, local-first store and sync | built and tested — see PROGRESS for what was run |
| 3 | History, Stats (+ CSV), tab shell, Poker Health trend, healthy-play tools | built and tested |
| 4 | Inventory-aware chip setup, blinds, Table Card, photo counting with a quality check, circles and multi-photo, **side-view counting** (from the owner's seven photos) | built and tested. Side view is an estimate and says so: 26 of 28 piles found and 18 exactly right on those photos; stacks taller than a few chips are only proven on drawn scenes |
| 5 | Breaks, share cards (night summary, weekly recap), **Live Activity** (Lock Screen and Dynamic Island clock with a Break button); tournament mode **asked, not built** (A6) | built and tested; the Live Activity was driven in the Simulator including the Lock Screen |
| 6 | Release engineering: privacy manifest, one version for every target, icon variants, String Catalog, release guard, runbook, App Store text, legal drafts, deploy script | built; the unsigned App Store build is checked both ways (see PROGRESS). Crashlytics and App Check wait on A7/A8; signing, the backend deploy, TestFlight and submission are the owner's |
| — | **Camera guide** (stretch goal): live prompts on the photo screen — hold flatter, lower, straighter, steadier, add light | built and tested on a stand-in camera; the real lens has not been run (the Simulator has none) |

## Defect list (from the audit)

**P0** — 1 forced sign-out every launch · 2 placeholder camera permission, silent camera failures · 3 no production backend config · 4 public photos · 5 rebuys double-count playtime · 6 weekly summary buckets by UTC · 7 no sign-out / delete-account / password-reset / guest mode · 8 the night isn't durable and the clock restarts on `onAppear`.

**P1** — 9 no tests · 10 solver runs inside `body` · 11 Custom chips screen logic wrong · 12 hard-coded `$` and `Double(text)` parsing · 13 accessibility and contrast · 14 asset hygiene · 15 forced 1.8 s splash, no timeouts/retry/offline states · 16 backend: in-memory photo refs, non-idempotent `/complete`, no limits, root container.

## Invariants (never regress)

- The denomination engine: exact sum (nearest nickel, in cents); clean ladder (0.05, 0.10, multiples of 0.25) with at most one nickel-safe exception; values strictly rise and counts strictly fall with colour rank; 20–30 chips as a *soft* goal that yields to exactness and shape. Locked by tests; `ChipPlanner` with no limits returns exactly the solver's answer.
- Money is integer cents everywhere in a night; settlements sum to zero; a bank resolution only applies to the difference it was made for.
- iOS 16.4: no `navigationDestination(item:)`, `sensoryFeedback`, SwiftData or unguarded `@Observable`.
- Dark-only, purple/gold identity, evolved not replaced.
- The app never touches Firestore or Storage directly.
- Counting by hand never needs the network or the camera.

## Risks

| Risk | Mitigation |
|---|---|
| iCloud evicts files from the synced Desktop (disk ~98% full): git and builds can fail | Safety snapshots outside iCloud; QUESTIONS B4 asks the owner to move the repo |
| The camera and the real counting service can't be verified in the Simulator | UI tests cover the "no camera" and manual paths; photo counting needs a physical device and a deployed backend |
| Cloud resources can't be touched without approval | Everything written and tested locally; deploy steps are exact commands in the README |
| Photo-counting accuracy from above is unmeasured on real photos, and from the side is measured on only seven | The app always shows editable counts and requires confirmation; the photo review lets every chip or pile be fixed or added; no photos are checked in |
| The nights API has never run against a real Firestore | The sync rules are pure code tested with fakes, a rule-following fake server and golden JSON shared by both test suites; the app keeps every night on the phone whatever the server does. Redeploy and try one night on a device (QUESTIONS B2, B5) |
| The camera (and the camera guide's lens), the table card's rotation, the share sheets and the break reminder can't be driven in the Simulator | Each is covered as far as the Simulator allows (the card does turn there; the share artwork is rendered and checked; the guide runs on a stand-in camera); a short device checklist is in QUESTIONS B5 |
| Side-view counts are weak on tall stacks | The app always shows the piles for correction, never reports "high" confidence for a side photo, and QUESTIONS A13 asks for the photos that would measure them. A chip is named for its body colour only: a white chip with blue edges is White (A12) |
| An Xcode Run Script phase is sandboxed to its declared inputs | The Release guard declares the widget's `Info.plist` as an input; found when an archive failed with matching versions |

## Deviations from the brief

- iPhone only, and portrait everywhere except the table card (the previous target allowed iPad and all orientations); approved in QUESTIONS A3.
- The US helpline is 1-800-MY-RESET (1-800-697-3738), not the 1-800-GAMBLER in the brief, which the national council retired on 29 January 2026; see QUESTIONS → *Answered*.
- "Before" screenshots (Phase 0) were captured after the rewrite, from the checkpoint commit with a throwaway harness, because the old UI cannot pass sign-in without real credentials.
- `pytest` and `httpx` were added as test-only dependencies before asking; the owner approved them afterwards (QUESTIONS A2).
- Display name is "Chip Counter"; the title inside the app is still "Poker Chip Counter" on the welcome screen.
- Side-view chip counting was first skipped, as the brief allowed, because no sample photos were supplied; it was built when the owner sent seven. It reads piles of one to a few chips from their rim stripes and the camera's tilt, cannot be trusted for tall stacks until it has been measured on some (QUESTIONS A13), and always asks the person to check.
- The Live Activity is built, the weekly-hours widget that goes with it is not: it would need an App Group, which needs a paid developer team (A11). I was also stopped by the assistant's permission check when writing the entitlement files and did not work round it.
- The camera guide is on by default and one tap from the standard camera. Its live lens path is code-reviewed only; if it ever feels worse than the Camera app, Settings → *Camera tips* turns it off.
- Phases 2–5 landed as a few large commits rather than one per task: the screens share files across tasks, so splitting them would have produced commits that don't build.

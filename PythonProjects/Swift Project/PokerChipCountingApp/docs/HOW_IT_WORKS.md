# How it works: the logic, the maths and the decisions

This is the long-form account of **why the app does what it does**: the arithmetic behind the chip values, how a photo becomes a count and a colour, what the camera angle does to all of that, and the design decisions (with the alternatives and the reasons) behind the rest of the project. It is written for the project's owner and for whoever maintains the code next.

| If you want… | Read |
|---|---|
| The map: folders, screens, data flow, a paragraph per subsystem | [`ARCHITECTURE.md`](ARCHITECTURE.md) |
| **The reasoning, the formulas and worked examples** | **this file** |
| What was tested, what wasn't, and the evidence | [`QA.md`](QA.md) |
| What is still undecided | [`QUESTIONS.md`](QUESTIONS.md) |
| Backend endpoints, privacy model, deploy steps | [`../ChipVisionService/README.md`](../ChipVisionService/README.md), [`RELEASE.md`](RELEASE.md) |
| Colours, type, spacing, accessibility | [`DESIGN.md`](DESIGN.md) |

**What it describes.** The project as it stands on 11 October 2026 (branch `release/v1-prep`): the code is the authority, and where this file and the code disagree the code wins and this file has a bug.

**How the numbers in this file were obtained.** Every figure comes from the code or from running it. The chip-value examples are the output of the app's real solver, compiled on its own; the camera-angle tables are computed from the formulas the counter uses and from the counter itself run on drawn scenes; the colour regions are read out of the detector's own function. The small tools that print them are in [`tools/`](tools/) and Appendix C says how to run each. Where the repository does not record *why* something was chosen, the text says *(inferred)* instead of inventing a motive. Where something is a limit or a weak spot, it is said where it arises and collected in section 17.

**Conventions.**
- *Money* is whole cents in an `Int` everywhere in the app's logic (`$25.00` is `2500`). `Double` appears only at the edges: a text field, a JSON field from an older server.
- *Chip colours* come in one fixed order, **White < Red < Blue < Green < Black**. A night uses some subset of them; the cheapest colour in use has *rank 0*, the next rank 1, and so on.
- *Image positions* are fractions of the photo's **width** (the height too), so a mark can be drawn at any size.
- *HSV* is OpenCV's scale (H 0–179, S and V 0–255). *Lab* is OpenCV's 8-bit Lab, rescaled so L runs 0–100 and a, b are centred on 0.
- *Elevation θ* is the angle between the camera's line of sight and the table: 0° looks along the table, 90° looks straight down. The phone reports *pitch*, which is the same angle at the centre of the picture.

## Contents

1. [The system on one page](#1-the-system-on-one-page)
2. [Chip values: the arithmetic](#2-chip-values-the-arithmetic)
3. [From a photo to a count: the pipeline](#3-from-a-photo-to-a-count-the-pipeline)
4. [Counting from above](#4-counting-from-above)
5. [How a chip's colour is decided](#5-how-a-chips-colour-is-decided)
6. [Counting from the side, at any angle](#6-counting-from-the-side-at-any-angle)
7. [The camera guide](#7-the-camera-guide)
8. [Reviewing and correcting what the photo found](#8-reviewing-and-correcting-what-the-photo-found)
9. [The night, the bank and settling up](#9-the-night-the-bank-and-settling-up)
10. [Keeping nights in step: storage and sync](#10-keeping-nights-in-step-storage-and-sync)
11. [Stats and healthy play](#11-stats-and-healthy-play)
12. [The backend, security and privacy](#12-the-backend-security-and-privacy)
13. [Interface and accessibility decisions](#13-interface-and-accessibility-decisions)
14. [How it is tested](#14-how-it-is-tested)
15. [Release engineering](#15-release-engineering)
16. [Decision log](#16-decision-log)
17. [Limits, weak spots and open questions](#17-limits-weak-spots-and-open-questions)
- [Appendix A: every threshold in one place](#appendix-a-every-threshold-in-one-place)
- [Appendix B: glossary](#appendix-b-glossary)
- [Appendix C: reproducing the numbers](#appendix-c-reproducing-the-numbers)

---

## 1. The system on one page

```
 ┌─────────────────────────────── iPhone ───────────────────────────────┐
 │  Chip Counter (SwiftUI, iOS 16.4+)                                   │
 │   · a night and its ledger, kept in files on the phone               │
 │   · chip planner, blinds, table card         (pure arithmetic)       │
 │   · camera guide → photo check → photo review (counts you can edit)  │
 │   · history, stats, healthy-play tools        (computed on the phone)│
 │  Lock Screen / Dynamic Island clock (ActivityKit extension)          │
 └───────┬─────────────────────────────────────────────┬────────────────┘
         │ Firebase Auth (guest / email / Apple)       │ HTTPS + Bearer ID token
         ▼                                             ▼
   Firebase Auth                  ChipVisionService (Cloud Run: FastAPI + OpenCV)
                                    · photo → counts (above) or piles (side)
                                    · nights sync, legacy import, account delete
                                         │ Admin SDK              │ Admin SDK
                                         ▼                        ▼
                                  Firestore                 Cloud Storage
                          sessions/{uid}/nights/{id}   chip-photos/{uid}/{session}.jpg
                          (rules deny every client)    (private; one-hour signed links)
```

### 1.1 Principles that settle most questions

These are not slogans; each one explains a group of decisions made later in this file.

1. **The phone is the source of truth.** A night is written to a file on every change and mirrored to the server later. No screen waits for the network, except counting from a photo, which has a by-hand alternative. (§10)
2. **Money is integers.** Cents everywhere, so totals reconcile to the cent and a settlement always sums to exactly zero. (§9)
3. **Pure logic, thin shells.** The solver, the night rules, the settlement, the statistics, the healthy-play rules, the camera advice, and on the server the sync rules and the two photo counters are all functions of their inputs with no I/O. That is what makes them testable without a phone, a camera or a network. (§14)
4. **A photo is a suggestion; the count is the person's.** The counts shown after a photo are always editable, always confirmed by the person, and every edit moves the counts by exactly the same amount. Nothing is ever reported as certain. (§8)
5. **Say what you don't know.** Confidence labels are coarse and conservative; a side-view count is never "high"; an old server's answer that can't be trusted is refused with a message, not shown. (§4, §6)
6. **Advise, never block.** The camera guide never disables the shutter. The healthy-play tools never lock anyone out of their history or out of finishing a night; the one thing that *does* hold is a break the person chose for themselves. (§7, §11)
7. **Private by default.** No analytics, no advertising, no tracking; photos are private and expire after 30 days once the lifecycle rule is applied at deploy; the database and storage rules deny every direct client request; deleting a night or an account deletes what was stored for it. (§12)
8. **Prove it with checks that can fail.** Property tests over thousands of random nights, golden files shared by the Swift and Python test suites, fakes that follow the real rules, and a real-photo regression with a floor set just below what was measured. (§14)

### 1.2 Platform decisions

| Decision | What was chosen | Why (as recorded) |
|---|---|---|
| OS floor | iOS 16.4, Xcode 16 | 16.4 is the project's floor and raising it is the owner's call (the Live Activity itself needs 16.2). Code avoids newer APIs on purpose: no `navigationDestination(item:)`, no `sensoryFeedback`, no SwiftData, no unguarded `@Observable`. |
| Devices | iPhone only | A deliberate v1 simplification (QUESTIONS A3). iPad is excluded. |
| Orientation | Portrait everywhere except the **table card** | The card is read across a table, so it widens to landscape while it is on screen and goes back after. |
| Appearance | Dark only, purple and gold | It evolves the existing identity (the badge icon and gold seal) instead of replacing it; the room is dim and the phone is at arm's length. (§13) |
| Third-party code | Firebase Auth (through the Firebase iOS SDK package) is the only dependency in the app | Analytics was linked once and removed because nothing used it. |
| Language | English; money, numbers and dates follow the device locale | A String Catalog holds the literal text; messages built in code are not in it yet. (§17) |
| Currency | USD in v1.0 | Formatting is already currency-aware, so adding more is a data change. |

### 1.3 Where state lives

| State | Where | Notes |
|---|---|---|
| Nights (the ledger, clock, pauses, bank resolution) | One JSON file per night in Application Support | Written to a temporary file then renamed into place; an unreadable file is moved to `quarantine/`, never deleted |
| Sync queue and cursor | A small state file beside them | Survives a relaunch, so a dropped connection loses nothing |
| Preferences and limits | `UserDefaults` | Weekly limit, reminder hours, break-until date, camera tips, haptics |
| Last set-up and the chip set the person owns | `UserDefaults` (JSON) | So "same as last time" is one tap |
| The signed-in user | Firebase, in the keychain | A returning person stays signed in |
| Photos | In memory only on the phone | Never written to disk on the phone; the server keeps a private copy (30-day lifecycle rule, applied at deploy) |
| Everything else | Nowhere | There is no analytics store, no advertising ID and no location |

### 1.4 Cross-cutting design decisions

- **The clock is derived, not counted.** A running night's elapsed time is `now − startedAt − time on breaks`, computed every time it is drawn. Killing the app, a dead battery or navigating away cannot lose or restart it. The Lock Screen clock works the same way: the activity carries the moment the clock *would* have read zero (`clockStart`, the start plus the breaks) and the system counts up from it by itself, so it is right with the app closed. A break stores the played seconds instead (`frozenSeconds`) and the clock holds still.
- **Rebuys are events, not a counter.** Each buy-in or rebuy is its own `BuyInEvent`, so one can be undone, the history is complete, and the old double-counting of play time on rebuys cannot recur. A player always keeps their first buy-in.
- **One JSON shape for a night, on the phone and on the wire.** Dates are ISO-8601 with whole milliseconds and keys are sorted, so the same night always produces the same bytes. The app's encoder and the server's validator are pinned to one golden string in both test suites.
- **Identity by value.** Navigation routes are plain values carrying their data; a night is always opened by id and read from the store, so a screen never holds a stale copy.
- **Idempotent everything on the wire.** Saving a night is a `PUT` that can be repeated; deleting is repeatable; importing old sessions is repeatable. A retry after a dropped connection costs nothing.

---

## 2. Chip values: the arithmetic

**The question.** The host says "$25 buy-in, six players, I have white, red, blue, green and black chips". The app has to say what each colour is worth and how many of each colour every player starts with, so that each stack is worth exactly $25 and can be handed out and checked at a glance.

The code is `PokerChipApp/Views/Denominations/DenominationEngine.swift` and `BlindsPlanner.swift`. There are two layers, both pure (no UI, no I/O):

- **The solver**, `calculateFlexibleChipDistribution(buyIn:players:availableColors:)`, finds values and counts from nothing but those three inputs.
- **The planner**, `ChipPlanner.plan(...)`, wraps the solver with what the person actually owns and prints on the chips: it caps counts by the chips owned, honours values that are fixed, offers up to three alternative stacks, and when it cannot deliver it says *why* and what would work. With no inventory and no fixed values its recommendation is exactly the solver's (a tested property).

**Notation used below.**

```
B    the buy-in in cents, rounded to the nearest 5 (ties away from zero), never below 5
P    the number of players
m    the number of colours in use, c₀ < c₁ < … < c(m−1), cheapest first, in the order W R B G K
vᵢ   the value of colour cᵢ in cents          nᵢ   how many chips of it each player gets
T    the target total number of chips         a = B / T   the average value of one chip
```

### 2.1 The rules

| # | Rule | Kind | Held by |
|---|---|---|---|
| R1 | **Exact sum.** Σ nᵢ·vᵢ = B | hard, never negotiable | construction (§2.7) and a test on every case |
| R2 | **Values strictly rise** with colour: v₀ < v₁ < … | hard | construction and a test |
| R3 | **Counts strictly fall** with colour: n₀ > n₁ > … ≥ 1, never a tie | hard: if impossible the answer is "too small" | the shape check (§2.8) and a test |
| R4 | **Clean values.** Every vᵢ is on the clean ladder (§2.3), except that the *cheapest* colour may, as a last resort, be any multiple of 5¢ | hard, with that one exception | the escalation tiers (§2.9) and a test |
| R5 | **20 to 30 chips** per player in total, nearer 30 with few players and nearer 20 with many | **soft**: it yields to R1–R4 | measured as a rate (≥ 90 % of realistic five-colour games) |

The order of priority is written into the code's comments and is deliberate: the exact sum is never negotiable; below it, keeping every colour's count strictly below the one before matters more than landing in the 20–30 window. A stack that hits 20–30 chips but ties two colours' counts is rejected in favour of one that keeps the shape even if its total lands outside the window. **"Too small to split" is a better answer than chips that don't follow the rule**, so when no stack satisfies R1–R4 the solver returns nothing.

### 2.2 Why these rules

| Rule | Reason recorded in the code or the tests |
|---|---|
| Exact sum | The bank check at the end of the night compares what was put in with what was cashed out; stacks that aren't worth the buy-in would start every night with a discrepancy. |
| Clean ladder | "So players can check their stacks with easy mental math instead of odd values like $0.35 or $2.35." |
| Strictly falling counts | A real set racks many low chips and few high ones. The counts follow a negative-exponential curve by rank (§2.6). A tie or an inversion (more black chips than white) reads as a mistake. |
| 20–30 chips | A stack a person can count and handle; "more players means less felt per player", so the target slides from 30 chips with two players to 20 with ten. |
| Refuse rather than bend | Earlier versions returned stacks like Green × 1, Black × 3 (an exact sum with counts rising with value). They were found in testing and are now regression tests. |

### 2.3 The clean ladder

```
L = { 5, 10, 25, 50, 75, 100, 125, 150, … }  cents      (5¢, 10¢, then every multiple of 25¢)
```

Three small functions keep values on it:

- `cleanValueCents(near: raw)` snaps a raw value: at or below **17.5¢** to the nearer of 5¢ and 10¢, above that to the **nearest multiple of 25¢** (never below 25¢). So 8 → 10, 30 → 25, 60 → 50, 110 → 100, 434.8 → 425.
- `nextCleanValueCents(after:)` is the next rung up: 5 → 10 → 25 → 50 → 75 → …
- `previousCleanValueCents(before:)` is the rung below, used when a fixed value above forces one down.

The ladder is "every quarter", **not** a 1-2-5 series. That keeps values mentally checkable, but it is also why a suggestion can contain a $4.25 or $8.75 chip; see §2.12 and §17.

### 2.4 How many chips: the target T

```
T(P) = round( 30 − 10 · (clamp(P, 2, 10) − 2) / 8 )        (rounding halves away from zero)
```

| Players | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|
| T | 30 | 29 | 28 | 26 | 25 | 24 | 23 | 21 | 20 |

### 2.5 A first guess at each colour's value: the average-chip rule

With T fixed, the average chip is worth a = B / T. Each colour has a natural multiple of that average, **by colour, not by position**:

| White | Red | Blue | Green | Black |
|---|---|---|---|---|
| 0.3 a | 0.6 a | 1.1 a | 2.0 a | 4.0 a |

The first-guess value is the multiple snapped to the ladder, v\*ᵢ = snap(a · μ(cᵢ)). If a snapped value is not above the previous colour's, it is bumped up the ladder one rung at a time until it is, so strict ordering (R2) holds even when a small buy-in squeezes several natural values together.

*Why scale from the average chip and not from the buy-in:* for a small buy-in split across five colours the average is already small, so Black's 4× lands on a small, affordable value instead of eating the whole budget on its own (the code's comment).

*Worked example, $25, six players, all five colours:* T = 25, a = 100¢. Natural values: 30 → **25¢**, 60 → **50¢**, 110 → **$1**, 200 → **$2**, 400 → **$4**.

### 2.6 How many of each: the decay curve

Counts fall by rank with weight

```
wᵢ = e^(−0.55 · i)          i = 0 for the cheapest colour in use
```

which for five colours is 1.000, 0.577, 0.333, 0.192, 0.111. The weights use each colour's **true rank among the colours present** (not its place in some slice), so with three colours the one expensive colour gets the smallest share rather than inheriting a weight of 1.0 and claiming most of the budget. The base unit is u = T / Σ wᵢ, summed over the colours in use. For five colours and T = 25 that is u = 11.30 chips.

The **two cheapest colours are left free** (§2.7). Each colour of rank 2 or more gets a first-guess count

```
nᵢ = max(1, round(wᵢ · u · s))
```

where **s is a scale** that the search tries in turn (§2.8): 0.6, 0.75, 0.9, 1.0, 1.1, 1.25, 1.4. Each count is then forced strictly below the one before it (to a floor of 1). If two colours both want 1 the attempt is marked *shape-broken*: the floor is the one place a tie cannot be avoided by lowering a count, so that scale is penalised instead of quietly accepted.

### 2.7 Closing the gap exactly: two free colours

Once the expensive colours' values and counts are fixed, they are worth H = Σ nᵢ·vᵢ (rank ≥ 2). What remains is

```
L = B − H            and the two cheapest colours must pay it exactly:     n₁·v₁ + n₀·v₀ = L
```

The search walks n₁ = 1, 2, … up to min(40, ⌊L / v₁⌋). For each n₁ the rest is R = L − n₁·v₁ (which must be positive). **v₀ is only tried among ladder values that divide R**, and no larger than v₁ − 5¢; then n₀ = R / v₀ is an exact integer by construction.

That is how R1 holds *by construction* instead of by checking afterwards, and bounding v₀ below v₁ is what keeps the search fast for large buy-ins: R can be huge, but v₀ never needs to be.

*Why two free colours and not one.* The code's comment: one free colour alone is too coarse against a ladder spaced in quarters to land an exact sum, a strict shape and a 20–30 total all at once; two free counts find one in the vast majority of cases. With only **two colours in use** there are no expensive colours and the free pair is the whole stack.

*Rank 1's value.* v₁ starts at its natural value. If that yields no good candidate it may climb up to four rungs, but always stays below the next colour's value, so ordering is never broken.

### 2.8 Choosing among candidates

The whole of §2.7 runs once for each scale s. Every candidate found is compared with the best so far, in this strict order:

1. a **correctly shaped** stack (R3) beats a shape-broken one;
2. a stack **inside 20–30** beats one outside;
3. a lower **score** wins, where

```
score = 10 · (chips outside the 20–30 window) + 0.05 · |total − T| + 0.02 · | ln v₁ − ln v₁* |
```

So distance outside the window dominates, then closeness to the target for this table size, then a mild preference for keeping the second-cheapest colour at its natural value ("bumping it up is a last resort, not the norm"). Ties keep the earlier candidate, so the result is deterministic: the solver uses no randomness.

**Why seven scales?** Different scales change how many chips the expensive colours take and therefore how much is left for the cheap pair. Here is the real search for the $25 example (the table is the best candidate at each scale):

| Scale s | Blue / Green / Black | Best cheap pair (White @ 25¢, Red @ 50¢) | Chips | Shape | In 20–30 |
|---|---|---|---|---|---|
| 0.6 | 2 / 1 / 1 | 2 × 25¢, 33 × 50¢ | 39 | no (Green and Black tie at 1) | no |
| 0.75 | 3 / 2 / 1 | 20 × 25¢, 18 × 50¢ | 44 | yes | no |
| 0.9 | 3 / 2 / 1 | 20 × 25¢, 18 × 50¢ | 44 | yes | no |
| 1.0 | 4 / 2 / 1 | 18 × 25¢, 17 × 50¢ | 42 | yes | no |
| 1.1 | 4 / 2 / 1 | 18 × 25¢, 17 × 50¢ | 42 | yes | no |
| **1.25** | **5 / 3 / 2** | **10 × 25¢, 7 × 50¢** | **27** | **yes** | **yes** |
| 1.4 | 5 / 3 / 2 | 10 × 25¢, 7 × 50¢ | 27 | yes | yes |

At low scales the expensive colours get so few chips that most of the $25 has to be paid in cheap ones, which pushes the total far past 30. At s = 1.25 the expensive chips (5 × $1 + 3 × $2 + 2 × $4 = $19) leave $6 for the cheap pair: 7 × 50¢ = $3.50 and 10 × 25¢ = $2.50. Total 27 chips. In all, 477 candidates were examined.

### 2.9 When the first attempt fails: three escalations

Tier 2 runs only if tier 1 found no stack that is both correctly shaped and in the window; tier 3 only if no correctly shaped stack exists at all.

1. **Tier 1: ladder only.** Everything above. The window is hit for the great majority of ordinary inputs.
2. **Tier 2: one nickel-safe exception.** The cheapest colour's value may be *any divisor of R that is a multiple of 5¢*, not only a ladder value. Everything else stays on the ladder. This is R4's single exception, and it is how a real chip set copes with a buy-in whose cents won't split on a quarter. Divisors are found by factoring R/5 up to its square root, not by stepping through every multiple of 5, so a six-figure buy-in stays fast. It is also where values like **45¢** and **70¢** come from (§2.12).
3. **Tier 3: tiny buy-ins.** When nothing correctly shaped exists yet, the expensive colours get much smaller counts (scales 0.45, 0.3, 0.2, 0.12, 0.06), ladder values first, then nickel-safe. Ordinary buy-ins never reach it. Example: $1.35 over White, Green and Black is 18 × 5¢ + 2 × 10¢ + 1 × 25¢ (an exact sum with falling counts; an earlier version returned Green × 1, Black × 3, whose counts rose with value, and that is now a regression test).

If even tier 3 finds no correctly shaped stack the answer is "too small" (§2.10, §2.13).

### 2.10 The smallest buy-in that works

The cheapest correctly shaped stack gives the largest counts to the smallest ladder values, counts m, m − 1, …, 1 against values 5¢, 10¢, 25¢, 50¢, 75¢. By the rearrangement inequality that assignment minimises the total. So

```
B_min(m) = Σ (m − i) · v(i)      with v = 5, 10, 25, 50, 75
  m = 3:  3·5 + 2·10 + 1·25                 =  60¢    ($0.60)
  m = 4:  4·5 + 3·10 + 2·25 + 1·50          = 150¢    ($1.50)
  m = 5:  5·5 + 4·10 + 3·25 + 2·50 + 1·75   = 315¢    ($3.15)
```

A test checks each floor both ways: a stack exists *at* the floor and none exists one nickel *below* it. In the real run, $3.15 over five colours gives 5 × 5¢, 4 × 10¢, 3 × 25¢, 2 × 50¢, 1 × 75¢ (15 chips) and $3.10 gives nothing.

### 2.11 One colour only

With a single colour every chip is the same, so there is no shape rule and the task is to pick a value and a count whose product is exactly B. `solveSingleColor` tries every ladder value that divides B and prefers a count in 20–30 that is nearest T. If none is in the window it scans counts outward from T (T ± 1, T ± 2, …) for a count that divides B into a multiple of 5¢. Examples: $25, Red only → 25 × $1; $13, Blue only → 26 × 50¢.

### 2.12 What the real solver returns

All from the compiled solver (Appendix C). "Chips" is the total per player.

| Buy-in | Players | Colours | Result | Chips |
|---|---|---|---|---|
| $25 | 6 | all five | 10 × 25¢, 7 × 50¢, 5 × $1, 3 × $2, 2 × $4 | 27 |
| $20 | 4 | W R B | 20 × 45¢, 13 × 50¢, 6 × 75¢ | 39 |
| $20 | 5 | W R B G | 15 × 45¢, 10 × 50¢, 5 × 75¢, 3 × $1.50 | 33 |
| $50 | 8 | all five | 14 × $1, 7 × $1.25, 4 × $2.50, 2 × $4.25, 1 × $8.75 | 28 |
| $100 | 10 | all five | 8 × $2.50, 6 × $3, 4 × $5.50, 2 × $10, 1 × $20 | 21 |
| $10 | 2 | W R | 20 × 25¢, 10 × 50¢ | 30 |
| $25.03 (→ $25.05) | 6 | W R B | 19 × 70¢, 9 × 75¢, 5 × $1 | 33 |
| $19.95 | 6 | all five | 9 × 5¢, 7 × 50¢, 5 × $1, 3 × $1.50, 2 × $3.25 | 26 |
| $1.35 | 6 | W G K | 18 × 5¢, 2 × 10¢, 1 × 25¢ | 21 |
| $3.15 | 6 | all five | 5 × 5¢, 4 × 10¢, 3 × 25¢, 2 × 50¢, 1 × 75¢ | 15 |
| $3.10 | 6 | all five | *no stack: too small* | |
| $25 / $13 | 6 | Red only / Blue only | 25 × $1 / 26 × 50¢ | 25 / 26 |

The effect of the table size on the same $50 buy-in with all five colours:

| Players | T | Result | Chips |
|---|---|---|---|
| 2 | 30 | 11 × 75¢, 8 × $1, 6 × $1.75, 3 × $3.25, 2 × $6.75 | 30 |
| 4 | 28 | 12 × 75¢, 6 × $1, 5 × $2, 3 × $3.50, 2 × $7.25 | 28 |
| 6 | 25 | 8 × 25¢, 7 × $1.25, 5 × $2.25, 3 × $4, 2 × $8 | 25 |
| 8 | 23 | 14 × $1, 7 × $1.25, 4 × $2.50, 2 × $4.25, 1 × $8.75 | 28 |
| 10 | 20 | 8 × $1.25, 6 × $1.50, 4 × $2.75, 2 × $5, 1 × $10 | 21 |

**What these runs show, honestly.** The invariants hold in every row (exact sum, falling counts, rising values). But:

- *Odd-looking values are legal.* $4.25 and $8.75 (the $50, eight-player row) are multiples of 25¢, so they are on the ladder, but a host would more naturally choose $5 and $10. They come from snapping 434.8¢ and 869.6¢ to the nearest quarter. A 1-2-5 style ladder would be a design change (§17).
- *The window is soft, and few colours miss it.* With three or four colours and a small buy-in the exact-sum and shape rules leave no stack in 20–30 (39 and 33 chips above). The 90 % window rate is measured for five colours.
- *The cheapest chip can be an odd value* (45¢, 70¢) when tier 2 is needed, sitting close to the next colour (50¢, 75¢).
- *Neighbouring table sizes can give quite different stacks* (White is 25¢ at six players and 75¢ at four) because the first guess depends on a = B / T, which moves with T.

### 2.13 With the chips the host owns: the planner

`ChipPlanner.plan(buyIn:players:colors:inventory:lockedValues:)` adds four things to the solver.

**Inventory.** `ChipInventory` says how many chips of each colour are owned. Presets of 100, 200, 300 and 500 are split evenly over the colours in use, with the remainder going to the cheapest colours (100 over three colours is 34 / 33 / 33), and every count can be edited. The most one player can be dealt of a colour is `owned ÷ players` (integer division); that cap is passed into the search, where it limits n₀ and n₁ directly and clips the higher colours' counts (a clip that forces a tie marks the attempt shape-broken like any other).

**Fixed values.** If the values are printed on the chips, or the person has set a colour's value by hand, `assignCleanValues` keeps them and works the rest around them: a fixed value must be above the colour below it; an unfixed colour whose natural value is now at or above a fixed colour above it is brought down a rung at a time; and if the order can't be kept, or no correctly shaped stack exists around the fixed values, the plan fails with *values conflict*.

**All values fixed.** When every colour has a fixed value only the counts are unknown, and `solveFixed` enumerates *every* exact deal by depth-first search from the dearest colour down, requiring strictly more of each cheaper colour, with each colour capped (default 100) and a safety budget of 2,000,000 steps. The winner is the deal inside 20–30 nearest to T, ties broken towards more of the cheapest chips. The alternative offered is the deal with the fewest chips (at least 8).

**Options.** The plan can hold up to three stacks over the same buy-in:

| Option | Meaning | How it is picked |
|---|---|---|
| Recommended | The balanced stack, exactly what the solver would give | the search's winner |
| Fewer chips | Same buy-in, less to count and rack | among the correctly shaped candidates the search already visited with at least 8 chips, the one with the fewest chips (ties: the larger smallest chip) |
| Finer chips | A smaller smallest chip, for finer blinds and betting | among the same candidates, the one with the smallest smallest chip (ties: total nearest 25) |

Because the alternatives come from candidates the search already judged correct, they are never worse-shaped than the recommendation.

**When it can't.** Failure is a typed value with something that would work, not a vague error:

| Failure | When | What is offered |
|---|---|---|
| No colours | none selected | choose colours |
| Too small | even with unlimited chips the buy-in can't be split into a correctly shaped stack | the next buy-in that works (scanned in 5¢ steps up to $10) |
| Set too small | it works without the owned-chip limits but not with them | up to one each of: fewer players (the largest count below the current one that works), a lower buy-in (90 %, 80 %, 70 %, 60 %, 50 % rounded to quarters; the first that works), or leaving one colour out (trying the dearest first). Each is checked to really work |
| No exact split | chips with printed values can't add up to this amount | the nearest amounts below and above that *can* be made, searched on a grid of the values' greatest common divisor, up to 200 steps each way |
| Values conflict | fixed values can't be ordered low to high, or no correctly shaped stack exists around them | change the values |

A one-colour stack within a set needs at least **five chips**: fewer can't make change.

Real runs of the planner:

| Situation | Result |
|---|---|
| $50, eight players, five colours, a 100-piece set (20 of each, so at most 2 of a colour per player) | *Set too small*; "fewer players: 2" offered |
| $20, six players, W R B, a 100-piece set (34 / 33 / 33, so at most 5 each) | *Set too small*; nothing nearby works |
| $20, four players, W R B, chips printed 25¢ / $1 / $5, set of 200 / 200 / 100 | Recommended **16 × 25¢ + 11 × $1 + 1 × $5** (28 chips); fewer chips: 12 × 25¢ + 7 × $1 + 2 × $5 (21 chips) |
| The same printed chips for **$22.10** | *No exact split*; the nearest amounts they can make are **$22.00** and **$22.25** |
| $20, four players, W R B, Red fixed at $1 | Recommended 18 × 50¢ + 6 × $1 + 4 × $1.25 (28); fewer chips 9 × 75¢ + 7 × $1 + 5 × $1.25 (21); finer chips 15 × 5¢ + 13 × $1 + 5 × $1.25 (33) |
| White fixed at $1 and Red at 50¢ | *Values conflict* |
| $2, six players, five colours | *Too small*; **$3.15** offered |
| $25, six players, five colours, no limits | Recommended as in §2.8; finer chips: 20 × 5¢, 10 × 50¢, 5 × $1, 3 × $2, 2 × $4 (40 chips) |

### 2.14 Blinds

The small blind must be payable with the smallest chip, the big blind is twice it, and the starting stack should be near a hundred big blinds (the usual deep-stack home game). With stack S and smallest chip u (both in cents), let `s* = S / (200 · u)`. The candidates are ⌊s*⌋ and ⌈s*⌉ (never below 1). For each candidate k the number of big blinds in the stack is `S / (2·k·u)`, and the one nearest 100 wins. Then small = k·u and big = 2·k·u.

| Stack | Smallest chip | Blinds | Big blinds in the stack |
|---|---|---|---|
| $100 | 25¢ | 50¢ / $1 | 100 |
| $50 | 25¢ | 25¢ / 50¢ | 100 |
| $25 | 5¢ | 15¢ / 30¢ | 83 (two steps would be 125; three is nearer 100) |
| $25 | 25¢ | 25¢ / 50¢ | 50 |
| $200 | 25¢ | $1 / $2 | 100 |

The blinds are never finer than the smallest chip allows, so a small stack of large chips can end up with fewer than 100 big blinds ($25 in quarters is 50). The person can step them up or down one smallest chip at a time (never below one).

### 2.15 How the solver is tested

All in `PokerChipAppTests/DenominationEngineTests.swift` and `ChipPlannerTests.swift`.

- **Hard invariants over seeded random inputs.** 700 cases from a fixed seed: mostly whole dollars and nickels with some odd pennies, 2–10 players, random colour subsets. For every case that gets a stack: exact sum to the rounded buy-in; the colours asked for; every colour has chips; at most one value off the ladder and only the cheapest; values strictly rising and counts strictly falling. More than 80 % of the random cases must get a stack at all.
- **Every realistic home game.** $10–$100 in $5 steps × {2, 4, 6, 8, 10} players × four colour sets must *all* have a suggestion that satisfies the invariants.
- **The soft goal as a rate.** At least 90 % of realistic five-colour games land in 20–30 chips. The slide from 30 chips (two players) to 20 (ten) is checked in one direction, for $50 with five colours: the two-player stack never has fewer chips than the ten-player one.
- **Named regressions.** $25 for six players used to suggest 85 white chips; a buy-in is rounded to the nearest nickel ($25.03 is worth $25.05); a single colour splits the buy-in exactly; no colours means no suggestion; a buy-in too small for five colours means *no* suggestion rather than a wrong one; the three floors above (at and one nickel under); $1.35 over White, Green, Black.
- **Planner tests** cover caps from inventory, printed values, the options, each failure with its recovery, the blinds, and that "with no limits the planner equals the solver".
- **Speed.** The slowest of 8,859 inputs took 8.5 ms in an optimised build (QA.md); in a Debug build a test holds each of 150 random cases under 0.5 s. The screen computes the suggestion once, off the main thread, and caches it.

---

## 3. From a photo to a count: the pipeline

Counting chips **by hand never needs the network or the camera**. A photo is an optional shortcut, and only ever a starting point: stacked chips are genuinely hard to read, so the result is always shown as editable counts that the person confirms.

**Two ways to photograph, chosen by the person (the app does not guess).**

| | From above | From the side |
|---|---|---|
| Chips laid out | spread on the table, faces up | standing in piles |
| What the counter finds | a circle per chip (§4) | a box per pile, with a count (§6) |
| What it can't see | chips hidden under others: a stack is **one circle** | chips inside a pile whose tabs it can't read |
| What it needs from the phone | nothing but the picture | the camera's tilt: pitch, roll, lens |
| Code | `chip_detection.py` | `side_view.py` |

The side view exists *because* of the left-hand column's blind spot: from above, a stack of five chips is a single disc.

```
person chooses "From above" or "From the side"
   │
camera guide (or the system camera) ──► a photo, and for the side view the camera's tilt
   │
PhotoQuality, on the phone: sharp enough? lit well? big enough?    poor ─► retake, or "use it anyway"
   │
prepared: upright, long edge ≤ 1600 px, JPEG quality 0.7  ──►  POST /v1/sessions/{id}/photo
   │                                                           (+ view, pitch, roll, focal35, colours)
server: token ─► rate limit ─► size and pixel limits ─► decode and re-encode (metadata gone)
   │
detect_chips_detailed (above)  or  detect_stacks (side)       OpenCV, no trained model
   │
private copy stored (best effort) ─► counts + confidence + the position of every chip or pile
   │
photo review: a circle on every chip / a box on every pile; every edit moves the counts by the same amount
   │
the person confirms ─► the cash-out
```

### 3.1 The check on the phone

`PhotoQuality` takes a few milliseconds and runs before anything is sent, so a bad photo is retaken at the table instead of discovered after a slow round trip. It works on a 256-pixel greyscale copy.

| Measure | How | Called a problem when |
|---|---|---|
| Brightness | mean grey level, 0–255 | below **35** (too dark) or above **225** (washed out) |
| Sharpness | variance of the 4-neighbour Laplacian of the grey copy | below **250** (blurry) |
| Size | the long edge of the photo in pixels | below **600** (small) |

Rules about the checks: lighting is reported *before* blur, because a dark or washed-out photo has little contrast to be sharp with, so the lighting is what to fix first; only the first problem is shown; and the person can always use the photo anyway, since the checks only ever suggest. The 250 threshold was set against the nine sample photos: sharp ones scored 1,000–2,000, and the same photos blurred by 16 pixels (at 12 MP) scored 55–110.

Before upload the photo is redrawn upright (the camera stores rotation as metadata, which a re-encode would drop), scaled so its long edge is at most **1600 px** (never scaled up) and encoded as JPEG at quality **0.7**. A 12-megapixel photo is about 3 MB; 1600 px is "plenty to find and colour-match chips and keeps an upload on weak signal quick".

### 3.2 The server's intake

In the order they happen, with the reason for each:

1. **What was asked.** The framework checks the form fields on arrival: `pitch` −30…90, `roll` −180…180 and `focal35` 8…200 (else 422), so a pose a phone could not report is refused.
2. **Who.** The Bearer token is verified with Firebase (401 if missing or bad); guest tokens work like any other. Then `view` must be `top` or `side` (else 400).
3. **How often.** 60 analyses an hour per user (`PHOTO_RATE_LIMIT_PER_HOUR`, else 429), the one expensive call. The counter is in process memory, so the limit is per instance. That is enough to blunt a runaway client, not a global quota.
4. **How big.** At most 10 MB (`MAX_UPLOAD_BYTES`; the server reads one byte past the limit so an oversized upload is detected without buffering it all) and at most 50 million pixels (`MAX_IMAGE_PIXELS`) once decoded, so a tiny file declaring enormous dimensions is refused (413).
5. **Clean.** The upload is decoded and re-encoded from pixels only (JPEG quality 90). OpenCV's encoder writes no EXIF, XMP or ICC segments, which is what strips location and device data; a test checks it. Detection sees the same upright picture.
6. **Count.** The detector runs in a worker thread, because it is CPU-bound OpenCV and would otherwise block the whole event loop.
7. **Keep.** The cleaned photo is stored privately (best effort: if Storage is down the person still gets counts) and a one-hour signed link is returned.

The response carries `counts`, `confidence`, `photoUrl`, `view`, and either `detections` (one circle per counted chip) or `stacks` (one box per pile). The required `denominations` field is parsed and checked to be a JSON object but the counters do not use it: they count by colour name and the app turns counts into money.

**Why classical computer vision.** The service says it plainly: it is a Hough circle transform and colour matching, *not* a trained model, so it will undercount chips hidden in tall stacks. That is the stated reason the app always shows the counts as editable and requires the person to confirm before a result is calculated, and why that step must never be removed just because the output looks confident.

---

## 4. Counting from above

A chip seen from directly above is a disc: one body colour, a printed pattern round the rim and often a logo in the middle. `chip_detection.py` finds those discs, throws away everything that isn't one, and names what survives.

### 4.1 The steps

| # | Step | Parameters | The failure it removes |
|---|---|---|---|
| 1 | Work on a copy at most **1280 px** on the long edge | `INTER_AREA` | Full-size photos make the next step slow enough to time out and flood it with false circles from fine texture. The stored photo is untouched. |
| 2 | Grey, then a **5×5 median blur** | | Texture and noise |
| 3 | **Hough circle transform** | gradient method; accumulator resolution `dp` 1.2; Canny high threshold 100; accumulator threshold 20; `minDist` = 1.5 × the smallest radius; radii from `max(8, min(h, w)/60)` to `max(min+4, min(h, w)/12)` px | Finds candidates. `minDist` only rejects near-identical duplicate votes. It does *not* separate two chips, or a chip from its own inner edges. |
| 4 | **Merge duplicates** | a circle whose centre is closer than **1.8 × the larger radius** to a bigger kept one is dropped | A chip's rim, inner pattern and logo are separate edges Hough latches onto separately. 1.8 came from a real photo in which a printed logo was sampled as a second, "black" chip about 1.5 radii away; two genuinely distinct chips were never seen closer than about 2.4 radii. |
| 5 | **Sample the colour** | the median HSV of a patch of half-width `max(2, r/3)` at the centre, and its saturation spread | The centre, not the whole disc, so a neighbour's edge colour is not picked up; the median, not the mean, so a stray pixel can't skew it. |
| 6 | **Isolation test** | median HSV of a ring from 1.05 r to 1.4 r; the Euclidean distance (in HSV) to the centre colour must be **≥ 25** | Flat background (a desk, a laptop lid) has no distinct edge. On the test photo real chips scored 59–200 and false circles on plain dark desk 3–18. |
| 7 | **Dark circles need texture** | a circle that names as Black must have a standard deviation of brightness ≥ **15** over the inner 0.75 r | A cast shadow is dark, low in saturation and has a real edge, so step 6 lets it through as a "black chip". A real face has printed segments and a logo, so its brightness varies; a shadow is a smooth falloff. |
| 8 | **Consistent size** | keep circles within **±25 %** of the median radius (needs at least 3 circles) | Every chip in one photo is the same size; a cup or a logo at another distance is a size outlier. |
| 9 | **In focus** | the Laplacian variance inside the circle's box must be **≥ 20 %** of the sharpest circle's | A phone's shallow depth of field leaves background clutter soft. It is relative to this photo, not a fixed floor, because phones differ hugely in how much detail they capture. |
| 10 | **Chromatic anchors** | White and Black circles are kept only inside the bounding box of the Red/Green/Blue circles, padded by **3.5 × the largest allowed radius**. With no coloured circle at all, everything is kept | White and black can't be told from generic bright or dark background by colour alone; a coloured hue is rare in a background. A photographed stack is one group, not scattered across the frame. |
| 11 | **Final check and naming** | isolation again, then the nearest reference colour (§5.1) | |
| 12 | **Report** | each chip as a centre and radius, as fractions of the picture's **width**, rounded to 4 places | |

### 4.2 Confidence

`confidence` is a coarse signal, not a probability. A circle is *ambiguous* when the saturation inside its sampled patch varies a lot (standard deviation above 60), which suggests it caught an edge or an overlap rather than a clean face. If more than 35 % of the circles are ambiguous the answer is `low`; more than 15 %, `medium`; otherwise `high`. Nothing found is `low`.

### 4.3 Decisions recorded in the code

- **The second, more permissive Hough pass was removed.** It used to run to rescue black chips, which have less edge contrast against a dark table. With the focus and anchor filters in place the first pass finds real black chips in most cases, while the permissive pass kept adding background circles next to the real chips. Trading a rare missed chip (the safe, expected failure, which the person fixes in review) for a frequent overcount (the misleading one) was judged a bad trade.
- **A cleverer anchor scheme was tried and reverted.** Clustering every circle by proximity and keeping the most colour-diverse group broke on a real photo whose chips were not all close enough to form one connected group, and preferred a coincidental pair of false detections over correct, scattered singletons. The simple anchor box plus the focus filter covers the same failures with less fragility.
- **Thresholds were tuned, not guessed,** against a clean synthetic image and nine real, messy phone photos with known counts. The accuracy on unseen photos is not measured; the synthetic test (no occlusion) detects and colours every chip, black included. An earlier note blamed black chips for misses; that turned out to be a bug in the test's image generator (a chip drawn partly off the canvas).

### 4.4 What this counter cannot do

- **It counts faces, not chips.** A stack is one circle; touching chips can merge; hidden chips are invisible. This is why the side view exists.
- **It assumes the camera looks straight down.** Tilted, each disc becomes an ellipse and Hough finds fewer of them. At the camera guide's limit of 72° a face is `sin 72° = 0.95` as deep as it is wide, a squash of about 5 %. (The code doesn't record why 72° was chosen; that is its geometric meaning.)
- **It knows five colours** (§5.1). A sixth is forced into the nearest of the five.
- **Its tuning rests on nine photos.**

---

## 5. How a chip's colour is decided

Colour is decided differently in the two views because the evidence differs: from above the whole face is visible; from the side the face is a sliver, the body is a thin band and the *tabs* printed round the rim are the most conspicuous thing.

### 5.1 From above: the nearest of five reference colours in HSV

The centre patch's median pixel (§4.1 step 5) is compared with five reference colours in OpenCV's HSV:

| Colour | H | S | V |
|---|---|---|---|
| White | 0 | 0 | 220 |
| Red | 0 | 200 | 200 |
| Blue | 110 | 200 | 200 |
| Green | 60 | 200 | 180 |
| Black | 0 | 0 | 30 |

```
distance² = (2 · Δh)² + (s − s_ref)² + (v − v_ref)²           Δh = min(|h − h_ref|, 180 − |h − h_ref|)
```

The hue is circular (0 and 179 are neighbours), so Δh takes the shorter way round. The smallest distance wins; a tie goes to the first listed. Hue carries double weight in the sum *(inferred: so that a colour's identity outweighs the lighting differences that move S and V)*.

**The regions this produces** (read out of the real function, `tools/colour_map.py`):

| Where | Result |
|---|---|
| Fully coloured pixels (S ≈ 200, V ≈ 200) | **Red** for hue 0–30 *and* 145–179; **Green** 31–83; **Blue** 84–144 (at full saturation and brightness the edges move to Red 0–35, Green 36–78, Blue 79–144) |
| The grey axis (S = 0) | **Black** below brightness 125, **White** from 125 up: the midpoint between the references 30 and 220 |
| How much colour turns a bright pixel (V = 220) from White into a colour | blue hue at S ≥ **53**; green at S ≥ 69; violet at S ≥ 95; red, orange, yellow and pink at S ≥ **102** |
| Pale pixels (S ≈ 80, V ≈ 200) | hues 0–46 and 132–179 (pale reds, oranges, yellows, pinks) read as **White**; only green (47–83) and blue (84–131) hues survive as colours |

Some pixels through the function:

| HSV | What it stands for | Named |
|---|---|---|
| (5, 210, 190) | a red chip face | Red |
| (172, 210, 190) | a red chip, hue wrapped round | Red |
| (105, 180, 170) | a blue chip in shade | Blue |
| (62, 150, 150) | a pastel green chip | Green |
| (0, 10, 230) | a lit white chip | White |
| (110, 25, 215) | a white chip with a blue cast | White |
| (0, 5, 25) | a black chip | Black |
| (0, 0, 100) | a mid-grey (a shadowed table) | **Black** |
| (0, 0, 125) | a light grey | **White** |
| (20, 200, 200), (28, 200, 200), (150, 120, 150) | orange, yellow, purple | **Red** (all three) |

**What this means in practice.**

- *The set is closed.* A chip in a sixth colour (orange, yellow, pink, purple, teal) is named as whichever of the five is nearest: orange, yellow and pink read as Red, purple as Red or Blue, teal as Blue. The person fixes it in review.
- *Greys are ambiguous,* which is why so much of §4 exists: the isolation, texture, focus and anchor tests are what keep a grey table and its shadows from becoming White and Black chips.
- *Why the centre.* A white chip with blue edge spots has its spots near the rim, outside the central third that is sampled, so from above it is named by its face. A lit white face has low saturation and reads White, and even a bluish cast such as (110, 25, 215) stays White, since a blue-hued pixel needs a saturation above about 53 to leave White. **This has not been measured on the owner's own white-with-blue-edges chip**: no top-view photo of it was available. The rule for the side view is firm and tested (§5.2).

### 5.2 From the side: Lab masks, tabs and one firm rule

From the side the counter works in Lab (lightness L 0–100; a and b centred on zero; chroma C = √(a² + b²)), because chroma separates "coloured" from "grey" cleanly, and the printed tabs are bright and almost colourless.

| Thing | Test | Notes |
|---|---|---|
| Red body | a > 22, b > −5, C > 30, L > 20 | chip red sits at a\* ≈ +45…+52; a table, a shadow and a white tab are near zero |
| Green body | a < −8, b > 4, C > 12 | a pastel chip green is a\* −24, b\* +17; its shaded wall a\* −10, b\* +9 |
| Blue body | b < −18, C > 22 | |
| **Tab** (a printed rim spot) | L > 70 and C < 14, a blob of 0.15–1.6 % of the chip width squared, at least 35 % filled, width 0.3–6 times its height | "bright, almost colourless rectangles on the rim" |
| White body | (L > 72 and C < 12) or (C > 25 and b < −8) | the bright face *together with* its coloured logo and stripes, so the logo doesn't cut the chip in two |
| Black body | **no colour test** | a black chip on a dark table has no outline; it is found only from its white tabs (§6.7) |

**The body-colour rule.** *A pile is named for the colour of its chips' bodies, and never for their tabs or logos.* A white chip with blue tabs is **White**, whatever colours the night is using. This is the owner's decision (QUESTIONS A12) after seeing their own set: they have a white chip with blue edges and no blue chip.

- *History.* An earlier version renamed a pile whose colour wasn't in play to the nearest colour that was, so a white chip with blue tabs became Blue on a night with blue chips and no white. That renaming was removed.
- *Today.* The `colors` field the app sends is accepted and ignored. What the app does with a pile of a colour the night isn't using is **leave it out of the counts and tell the person** (so a White pile on a night with no White chips is reported, not silently relabelled).
- *Tested* in `test_a_pile_is_named_for_its_own_colour_whatever_colours_are_in_play`, which tries four different "colours in play" lists and expects the same names every time, and in the real-photo regression, which expects the white chip with blue tabs to count as White.

### 5.3 What the person can do about colour

Every circle or pile can be recoloured in the photo review, and the counts move with it (§8). Colour is never the only signal in the interface either: chips carry a name always and a letter (W R B G K) when "Differentiate Without Color" or the in-app option is on.

---

## 6. Counting from the side, at any angle

`side_view.py` reads photos taken from the side or at a low angle, where each chip is a thin band or a squashed ellipse and a circle counter finds nothing. It answers three questions in order: *where are the piles*, *what colour is each*, *how many chips are in each*. The last depends on **how foreshortened the chips are, which depends on the camera angle**, so the app sends the camera's own tilt along with the photo.

### 6.1 The camera's pose, from the phone's sensors

Every iPhone photo stores an accelerometer reading in Apple's maker note (item 8): a vector pointing the way gravity does, in the phone's own axes, in units of g. The camera looks out of the back, along −z. From that vector (`CameraPose.swift`):

```
valid only if 0.7 < |g| < 1.3          (a phone at rest reads 1 g; much more or less means it was being shaken: no pose)

pitch = asin( −g_z / |g| )              0° = looking along the horizon, 90° = straight down
roll  = atan2( −(g · right), (g · down) )     measured on the upright picture that is sent
```

`right` and `down` are the picture's own axes expressed in the phone's, which depend on the photo's EXIF orientation:

| EXIF orientation | The photo is | picture "down" | picture "right" |
|---|---|---|---|
| 1 | as the sensor saw it | −x | −y |
| 3 | turned half way round | +x | +y |
| 6 | a portrait photo (the usual one) | −y | +x |
| 8 | a portrait photo, phone upside down | +y | −x |
| anything else | not something a camera writes | roll unknown | |

*Check:* a phone lying flat with the camera pointing down reads g = (0, 0, −1), so pitch = asin(1) = 90°; held upright in portrait it reads (0, −1, 0), so roll = atan2(0, 1) = 0°.

The third number is the lens: the photo's 35 mm-equivalent focal length, accepted between 8 and 200 mm. **Only these three numbers are ever read from a photo or sent** (not where, when or which phone). If the photo carries no maker note the guide's sensor reading from just before the shutter is used instead. If there is no pose at all the server assumes a pitch of 22° and a 24 mm lens, and every count says "low".

### 6.2 Make the picture level

If the roll is 1° or more, the picture is rotated by the roll about its centre (bilinear, borders replicated) so the horizon is level and a pile's chips are stacked straight up. Piles are found in the level picture; each box is mapped back to the photo as it was sent and carries `angle = −roll`, so the app can draw it turned the same amount.

### 6.3 The elevation at each row

The pose's pitch is the elevation at the **centre** of the picture. Rows lower in the frame look more steeply down at the table:

```
θ(row) = pitch + atan( (row − height/2) / f )          f = focal35 · width / 36   (in pixels)         limited to 4°…80°
```

*Example:* pitch 20°, a 24 mm lens, a 1280-px-wide picture: f = 853 px.

| Row relative to the centre (px) | −300 | −150 | 0 | +150 | +300 | +480 |
|---|---|---|---|---|---|---|
| Elevation θ | 4.0° (limited) | 10.0° | 20.0° | 30.0° | 39.4° | 49.4° |

Each pile uses θ at the middle row of its own box, so two piles in one photo are seen at different angles. In the walkthrough below three stacks drawn at the same 12° pitch were measured at 12.6°, 11.0° and 13.5° because their boxes sit at different rows.

> **A thing to check.** The `width / 36` conversion treats the 35 mm-equivalent length as measured along the picture's width. That is exact for a landscape 3:2 frame and within about 4 % for a landscape 4:3 one, but for a **portrait** picture, the usual phone shot, `width` is the short side and the lens model comes out about 28 % too short. For a 3024 × 4032 photo the model puts the top and bottom edges 45° from the centre row where a diagonal-based conversion gives about 36°. Piles near the middle row are barely affected; piles far from it would be seen at too steep an angle by up to several degrees. This is a reading of the code, not something measured on real photos (§17).

### 6.4 The geometry of a chip

A chip is a short cylinder of diameter D and thickness t. A standard clay-composite chip is **3.3 mm thick and 39 mm across**, so

```
k = t / D = 3.3 / 39 = 0.0846
```

Seen from elevation θ (treating the projection across one chip as orthographic):

- its **top face** is an ellipse D wide and **D · sin θ** deep;
- its **side wall** is D wide and **k · D · cos θ** tall.

For a chip that is 150 px wide in the picture:

| θ | sin θ | Top face, px deep | cos θ | Side wall, px tall |
|---|---|---|---|---|
| 5° | 0.087 | 13.1 | 0.996 | 12.64 |
| 10° | 0.174 | 26.0 | 0.985 | 12.50 |
| 15° | 0.259 | 38.8 | 0.966 | 12.26 |
| 20° | 0.342 | 51.3 | 0.940 | 11.92 |
| 30° | 0.500 | 75.0 | 0.866 | 10.99 |
| 45° | 0.707 | 106.1 | 0.707 | 8.97 |
| 60° | 0.866 | 129.9 | 0.500 | 6.35 |
| 90° | 1.000 | 150.0 | 0.000 | 0.00 |

This is why the angle matters so much and why the guide keeps the camera low from the side: as θ grows the top face swells and the walls (the only thing that says "how many") shrink to nothing. **At 90° a stack of any height is a single disc.**

A stack of n chips is therefore

```
H(n) = n · k · D · cos θ  +  D · sin θ          n walls, plus the depth of the top face
n    = ( H − D · sin θ ) / ( k · D · cos θ )     what the counter solves for
```

| θ | n = 1 | n = 3 | n = 5 | n = 10 | n = 20 |
|---|---|---|---|---|---|
| 12° | 43.6 | 68.4 | 93.3 | 155.3 | 279.4 |
| 20° | 63.2 | 87.1 | 110.9 | 170.6 | 289.8 |
| 30° | 86.0 | 108.0 | 129.9 | 184.9 | 294.8 |

(silhouette height H in pixels, for a 150-px chip). The counter measures two things in the picture:

- **D**, one chip's width. A loose pile is wider than one chip, so the best measure is the *narrowest* of the photo's piles: the 25th percentile of the anchor piles' widths.
- **H**, the *central height*: the median height of the silhouette's columns within ±12 % of its width around its middle, "where the stack is least spoiled by the curve of a rim".

### 6.5 Two ways to count

Let `walls = (H − D · sin θ) / (k · D · cos θ)`.

- **Four or more walls** (`walls ≥ 4.0`): count by height, `n = round(walls)`.
- **Fewer:** count the **rings of tabs** (next section).
- **Black piles** have no silhouette to measure (a black chip on a dark table has no outline), so they are counted from rings alone.

### 6.6 Counting rings of tabs

Poker chips carry printed rim tabs, six to a chip, 60° apart. Seen from the side the front half of a chip shows about three. The tabs of one chip lie on a circle of radius `0.86 · D / 2` (`_TAB_RING`), which at elevation θ appears as an ellipse **2R wide and 2R · sin θ deep**.

1. **Flatten.** Divide every tab's y-coordinate by sin θ (with sin θ never taken as less than 0.15). Each ring becomes a true circle again, whatever the angle.
2. **Hypothesise.** For every pair of tabs whose separation (the chord) is between 0.25 r and 2 r, there are two circles of radius r through both: the centres lie on the perpendicular bisector at distance `√(r² − (chord/2)²)` from the midpoint, on either side. Radii of 0.9 r, 1.0 r and 1.1 r are tried.
3. **Vote.** Count the other tabs within **13 % of r** of each hypothesised circle (the *inliers*).
4. **Accept** the circle with the most inliers if it has **at least 3** (at least **4** for black piles, where the rings are the only evidence) and they are *spread out*: no two closer than **40°** around the centre, since a chip's tabs are 60° apart and blobs closer than that are not tabs.
5. **Repeat** on the tabs that remain, up to six rings.

The count is the number of rings found. Glare on a dark table makes bright blobs too, but they don't sit on a ring of the right size.

### 6.7 Finding the piles

| Pile | How it is found | Checks that keep it from counting a red cup |
|---|---|---|
| **Red, green, blue** (the *anchors*) | a colour mask (§5.2), closed with an elliptical kernel of about 1.2 % of the picture width, then connected components | the blob is 0.10–5 % of the picture's area, 0.25–7 times as wide as tall, at least 30 % solid, and **shows at least 3 tabs** — "no printed rim: not a chip" |
| Merging and tidying | same-colour blobs split by white tabs (top face and side wall found apart) within 15 % of the pile's width join; a smudge that overlaps a bigger pile by more than 40 % of its own area is part of that pile | |
| Consistency | keep the largest set of piles about the same width (±50 %) standing in one row (bottoms within 1.2 widths) | a pile that is the wrong size or in the wrong place is not a chip |
| Silhouette | each anchor is grown by 12 % of a chip's width, one step at a time, through coloured or bright pixels, so growth stops at the shadow under the pile instead of leaping to the glare beyond | |
| **White** | a bright colourless body (or a strongly blue accent area) 0.6–1.5 chip widths wide, 1.1–7 times as wide as tall, at least 50 % filled, near the anchors (within 4.5 chip widths sideways and 3 vertically), overlapping no other pile, with **at least 2 tab-sized coloured accents** (its stripes) | named White (§5.2) |
| **Black** | white tabs inside the strip where the anchors stand (0.8 chip widths above the highest and below the lowest, 3 beyond left and right), outside any other pile; fitted to rings of at least 4 tabs; rings stacked at the same place (within 0.4 W sideways and 0.7 W vertically) form a pile | the count is the number of rings |

**It needs rim tabs** (plain-edged chips are not found), **and at least one red, green or blue pile** to learn the chip's size and the row they stand in: a photo of only white and black chips finds nothing. Loose piles (chips pushed off-centre) and very tall stacks are estimates. Piles come back sorted left to right.

### 6.8 What a wrong angle does to the count

The count depends on knowing θ and D. Two sensitivity tables, computed with the counter's own formula (a 150-px chip, the height measured exactly), show what an error in either costs.

**The angle told to the counter is wrong by δ** (counts of a stack of n chips whose true elevation is θ₀):

| θ₀ | n | δ = −5° | −2° | 0 | +2° | +5° | +10° |
|---|---|---|---|---|---|---|---|
| 15° | 4 | 4.9 | 4.4 | 4.0 | 3.6 | 3.1 | 2.1 |
| 15° | 10 | 10.8 | 10.3 | 10.0 | 9.7 | 9.2 | 8.5 |
| 15° | 20 | 20.6 | 20.2 | 20.0 | 19.8 | 19.5 | 19.2 |
| 25° | 10 | 10.7 | 10.3 | 10.0 | 9.8 | 9.4 | 8.9 |

**The chip's width is mis-measured by ε** (θ = 20°):

| n | ε = −10 % | −5 % | 0 | +5 % | +10 % |
|---|---|---|---|---|---|
| 4 | 4.9 | 4.4 | 4.0 | 3.6 | 3.2 |
| 10 | 11.6 | 10.8 | 10.0 | 9.3 | 8.7 |
| 20 | 22.7 | 21.3 | 20.0 | 18.8 | 17.8 |

The rule of thumb: **5° of angle moves a 10-chip count by under one chip (0.8), and a 5 % error in the measured chip width moves it by about as much**, 6–10 % of the stack. The same experiment with the real counter on a drawn stack of 8 red chips, told the true angle and then 5° too low and 5° too high (`tools/side_view_walkthrough.py`):

| Drawn at | Told true | Told −5° | Told +5° |
|---|---|---|---|
| 8° | 8 | 9 | 7 |
| 12° | 8 | 9 | 7 |
| 20° | 8 | 9 | 7 |
| 30° | 8 | 8 | 7 |
| 45° | 8 | 8 | 8 |

This is why the pose comes from the phone's sensors (accurate to the shutter) and why the camera guide keeps the tilt where the model is accurate: from the side, a pitch of at most 30° and a level horizon within 5° (§7).

### 6.9 What was measured, and what wasn't

**Seven real photos of one chip set** (piles of one or two chips, shot at 16–24° above the table, kept out of git in `PokerChipApp/test_photos/side_view`): the counter found **26 of 28 piles** with the right colour and counted **18 of 28** exactly. Piles of one chip were right every time; a pair about half the time. The regression test asserts floors just below those figures (at least 24 found and 16 right), not a promise.

**Drawn scenes** that follow the counter's own geometry prove the code path and the arithmetic, and nothing about real stacks. On those, stacks of five or more are counted by height within one chip (`tools/side_view_walkthrough.py`, drawn at 12° with the pose given):

| Drawn | 1 | 2 | 3 | 4 | 5 | 6 | 8 | 10 | 12 | 15 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Counted | 1 | **1** | **2** | **3** | 5 | 6 | 8 | 10 | 12 | 15 | 21 |
| By | rings | rings | rings | rings | height | height | height | height | height | height | height |

Even on drawn scenes the **ring rule undercounts piles of 2, 3 and 4 chips by one**, and the height rule is within one chip from five up (21 for 20). Rounding the height estimate alone would have been right for 2, 3 and 4 on these scenes; whether it is better on real photos has not been tested, so nothing was changed (§17).

**Confidence** is `low` for every pile the counter returns today. It is never `high`, and the app says so and asks the person to check every pile.

**Tall stacks of real chips** have not been tested. QUESTIONS A13 asks for photos of real upright stacks with known counts; if they are added to that folder with their counts the test measures them.

---

## 7. The camera guide

The photo is only as good as how the phone was held, and the person usually can't see what is wrong (a tilted horizon, a dim table). The **guided camera** looks at three things ten times a second and says one sentence; it can only advise, and the shutter is never disabled.

### 7.1 What it reads

| Reading | From | How often |
|---|---|---|
| Pitch and roll | CoreMotion gravity, through the same `CameraPose` maths as §6.1 (assuming the phone is held upright, orientation 6) | 10 Hz |
| Turning speed | the magnitude of the gyroscope's rotation rate, in rad/s | 10 Hz, not smoothed |
| Brightness and sharpness | the brightness plane of 640 × 480 video frames, at most every 0.2 s, shrunk to about 256 px by averaging blocks of pixels, then measured *exactly as `PhotoQuality` measures a finished photo* | 5 Hz |

Using one measure before and after the shot means the advice never contradicts the check: the brightness limits are the very same constants.

### 7.2 What it says, in order of importance

`FramingAdvisor` is pure arithmetic on a reading, so every sentence can be tested without a camera. The first rule that fires wins.

| # | Says | Fires when | For |
|---|---|---|---|
| 0 | "Getting the camera ready…" | no brightness reading yet | both |
| 1 | Hold the phone upright | pitch < 75° and \|roll\| > 35° | side only |
| 2 | It's dark in here | mean brightness < 35 | both |
| 3 | Glare is washing the picture out | mean brightness > 225 | both |
| 4 | Hold the phone flat above the chips | pitch < 72° | above |
| 5 | Lower the phone to the height of the piles | pitch > 30° | side |
| 6 | Tilt the phone down a little | pitch < −8° | side |
| 7 | Straighten the phone | \|roll\| > 5° | side |
| 8 | Hold still… | turning faster than 0.8 rad/s | both |
| 9 | "Hold still…", or "The picture is soft. Hold still, and move back a little" | sharpness < 80: the first if turning faster than 0.4 rad/s, the second otherwise | both |
| — | **Looks good. Take the photo.** | none of the above | both |

Reasons recorded for particular rules:

- *Circles don't mind a turned picture, so from above the phone may be held any way round*; from the side the piles are measured against the horizon, so it must be upright. The "turned" angle is judged only below 75° pitch, because near straight-down the lean of gravity across the screen is a hair and its direction is noise.
- *Sharpness 80 is set low on purpose:* a wrong "it's soft" is worse than a missing one. Soft while moving is just the movement, so it is called "Hold still", not a focus fault.
- *The thresholds are reasoned, not measured.* The tilt limits match what the counters read best (from above, straight down; from the side, level and a little down, so each chip is a thin band and not a disc, §6.4).

### 7.3 Keeping the words from flickering

`FramingCoach` sits between the sensors and the screen:

- Pitch, roll, brightness and sharpness are smoothed with an exponential average that takes **30 %** of each new reading. Turning speed is *not* averaged: holding still should be noticed at once.
- A **change of advice must hold for half a second** before it replaces the one on screen, and "ready" must hold for **0.9 s**, so it doesn't flash as the phone swings through level.
- Leaving "ready" (or the start-up message) is immediate: a picture that has just stopped being right shouldn't say it is.
- Screen readers are told each new sentence once.

### 7.4 Choices around it

- **Advise, never block** (principle 6). A photo taken against the advice is still counted.
- **The standard camera is one tap away,** and is what appears if the guide is switched off (Settings → Camera tips), if the phone can't run it, or if the camera can't start within six seconds, stops, or is taken over by a call. The standard camera shows a static frame and has the system camera's zoom, focus and flash that the guide lacks.
- **The camera settings:** the main wide back camera, the photo preset, balanced quality prioritisation, no flash. The photo's own recorded tilt is used when it has one, with the sensors' reading from just before the shutter as the fallback.
- **The screen stays awake** while the guide is up, and a guide that failed is restarted when the app comes back to the foreground.
- **Text stops growing at the first accessibility size** here only, because at AX3 on the smallest phone the advice took half the screen; a viewfinder can't give its picture to words (§13).
- **The lens path has not been run:** the Simulator has no camera. Everything except the lens, the motion sensors and the real frames is tested on a stand-in camera, and trying it on a phone is on the owner's checklist (QUESTIONS B5).

---

## 8. Reviewing and correcting what the photo found

**The counts are the source of truth; the circles and boxes are a way of fixing them.** The cash-out screen holds a count per colour. A photo sets those counts, and every edit afterwards changes them by exactly the amount the edit implies, so the marks and the counts can't disagree (a random test applies 600 edits and checks they stay in step).

| Edit | Effect on the counts |
|---|---|
| Recolour a circle | −1 from the old colour, +1 to the new |
| Remove a circle (not a chip, or counted twice) | −1 from its colour |
| Add a chip the photo missed (tap where it is) | +1 to its colour; drawn at the median radius of this photo's circles |
| Set a pile's count | the difference, to the pile's colour (a pile holds 1 to 99) |
| Recolour a pile | all its chips move to the new colour |
| Remove a pile | its chips come off its colour |
| Add a pile the photo missed | +1 (a pile one chip tall, at the typical size of this photo's piles) |

Counts never go below zero. The stepper under each colour still works and stays in step.

- **Several photos add up.** The first photo sets the counts; each further one *adds*, up to four, for chips that won't fit in one frame. Each chip should be in only one photo.
- **Colours the night isn't using are left out and said so,** for both circles and piles (§5.2).
- **An old server is recognised.** If a side photo comes back from a server that predates side-view counting (it answers `top`), the app refuses it with a message instead of showing piles that are really single circles.
- **Failure never blocks.** If counting is unavailable the message says why and tells the person to count by hand.
- **The photo is held in memory only,** never saved to the phone.
- **The service is woken ahead of time** (`Prewarm`, at most every five minutes, a `/healthz` call that needs no sign-in) when a night or a cash-out opens, because a service that scaled to zero can take seconds to answer the first photo.
- **A bad photo is held back before it is sent,** with the reason and a retake button (§3.1).

---

## 9. The night, the bank and settling up

A **night** is the unit of everything: who played, when, what each put in and took out, the chips used, the breaks, and how the bank was reconciled. A one-player game is simply a one-player night. The code is `Views/Nights/Model/` (`GameNight`, `NightMath`, `Settlement`), all pure and all in integer cents.

### 9.1 The record

| Part | What it is | Why it is shaped that way |
|---|---|---|
| `PlayerLedger` | name, a list of `BuyInEvent`s, an optional cash-out (cents) and when | A player's total in is the sum of their events, so there is no separate "rebuy count" to drift out of step. |
| `BuyInEvent` | id, amount in cents, time | Each buy-in or rebuy is its own event: it can be undone, history is complete, and nothing is counted twice. A player always keeps their first buy-in. |
| `PauseInterval` | start, optional end | A break is an interval, not a flag; the clock subtracts the intervals. |
| `BankResolution` | kind (tip, assign, split), a player id for assign, and **the difference it was made for** | If a cash-out is corrected afterwards the difference changes and the stored choice stops applying; the night asks again instead of silently reusing a stale answer. |
| `updatedAt` | the night's logical clock | Last-writer-wins merging (§10). |
| `schemaVersion` | currently 1 | New fields decode to sensible defaults, so a night saved by an older build still opens. |
| `myPlayerID` | which player is the person holding the phone | Stats and "your result" are about that player; nil if they weren't playing. |

Names are trimmed and cut to 40 characters, with "Player N" if nothing usable is typed; places to 80; notes to 2,000.

### 9.2 The clock

```
playtime = floor( (endedAt ?? now) − startedAt − time on breaks )          never below 0
```

Each break is clipped to the span between the start and the end, so an interval that began before the night or runs past it can't produce negative or doubled time. Ending play ends an open break at the same moment. A rebuy has no effect on time; the earlier version of the app counted playtime twice on a rebuy, and one of the tests builds a night with random breaks and checks that played time plus break time equals the length of the night to within a second.

A night belongs to the **local calendar day it started on**, in the time zone it was played in (an 8 pm game is "today" even though it is already tomorrow in UTC). One that runs past midnight is not split.

### 9.3 The bank check

When everyone has cashed out, the bank should balance:

```
Δ = Σ cash-outs − Σ buy-ins
```

If Δ = 0 the night can be settled. Otherwise one of three resolutions covers it:

| Resolution | Meaning | Allowed when | Effect on each player's net |
|---|---|---|---|
| **Tip** (or rake) | the house keeps the shortfall | Δ < 0 only (chips can't appear from nowhere, so an overage can't be a tip) | none; a "Tips" line of −Δ is added |
| **Assign** | one player's count was off by the difference | always, to a player still in the night | that player's net is adjusted by Δ |
| **Split** | share it out | always | every player's net moves by an even share |

An even share of an amount among n people is computed in whole cents with **the first few people taking the extra cent**, so the shares always add to the amount and nothing is rounded away. `evenShares(−100, 3) = [−34, −33, −33]`; `evenShares(7, 4) = [2, 2, 2, 1]`.

A resolution is *active* only while it still fits: it must have been made for today's Δ, a tip needs a shortfall, and an assigned player must still be in the night. Otherwise `isBalanced` is false and the bank-check screen asks again.

After the resolution, each player's net is

```
net(i) = cashOut(i) − totalIn(i) − share(i)           plus a "Tips" entry of −Δ if the shortfall was a tip
```

and these **always sum to exactly zero**: for assign and split the shares add to Δ, which cancels Σ(cashOut − totalIn) = Δ; for a tip the players' nets add to Δ and the tip entry is −Δ. A property test checks the sum over 4,000 random nights.

*Real runs* (`tools/settle_demo`): three players each put in $20; cash-outs of $25, $20 and $14 leave the bank $1.00 short.

| Resolution | Nets after it | Payments |
|---|---|---|
| Tip | Alex +500, Blair 0, Casey −600, Tips +100 | Casey pays Alex 500 and the house 100 |
| Assign to Casey | Alex +500, Blair 0, Casey −500 | Casey pays Alex 500 |
| Split three ways | Alex +534, Blair +33, Casey −567 | Casey pays Alex 534 and Blair 33 |
| *Casey's cash-out corrected to $15* | the old choice no longer applies; the bank balances | Casey pays Alex 500 |

With a $1.00 *overage* a tip is refused (the night stays unbalanced), and a split gives Alex +466, Blair −33, Casey −433.

### 9.4 Settling up

`Settlement.payments(for:)` turns the nets into payments by repeating one step: **match the person owed the most with the person who owes the most**, pay the smaller of the two amounts, and drop whoever reaches zero. Each step removes at least one person, and the last removes two, so with n people with non-zero nets there are **at most n − 1 payments**; a given pair is matched at most once. Equal amounts are broken by name (case-insensitive) and then id, so the answer never depends on the order the players are listed in.

| Nets | Payments |
|---|---|
| A +50, B +30, C −20, D −60 | D pays A 50; C pays B 20; D pays B 10 (3 payments for 4 people) |
| A +5, B +4, C +3, D −5, E −7 | E pays A 5; D pays B 4; E pays C 2; D pays C 1 (**4** payments) |

The second row shows the limit of the rule: A and D cancel exactly and E could pay B and C directly, which takes three payments. Finding the true minimum means finding the largest way to split the people into groups that each net to zero, which is a much harder problem; the simple rule guarantees *at most n − 1*, not *the fewest*. The app's wording was changed from "the fewest payments" to "a few simple payments" for that reason. Settlements also render as text ("Sam → Alex $23.50", one per line) and as a share card.

### 9.5 Changing a night

Rules the model enforces, each a method on `GameNight`:

- A player can be added late (in for the default buy-in) and removed only if they haven't cashed out.
- A rebuy is refused for someone already cashed out or for a non-positive amount; undoing a buy-in always leaves at least the first.
- A cash-out must be non-negative; clearing one makes the bank unbalanced again.
- "End the night" stops the clock (and any open break); **resuming play** clears the bank resolution, because the numbers it was made for are about to change.
- A settled night can be reopened to correct it.
- Deleting keeps the full night for the undo window, then reduces it to a **tombstone**: id, start, time zone, currency and the two timestamps, with no names, place, notes or amounts. Other devices need the marker to stop showing the night.

### 9.6 Money and text

All arithmetic is integer cents. Display goes through one place (`Money`): currency formatting that follows the device locale (always two decimals, since chip arithmetic is exact to the cent), a compact form for tight spots ("$10", "$12.50"), signed results with a true minus sign, and a spoken form for VoiceOver ("2.50 US dollars"). Typed input is parsed **strictly** in the device locale: "25,5" in a US locale is rejected rather than quietly read as 255. A buy-in or cash-out field takes up to $1,000,000; the conversion to cents rounds to the nearest cent so that 0.1 + 0.2 style drift can't occur.

---

## 10. Keeping nights in step: storage and sync

**The phone is the source of truth** (principle 1). Everything a person does is on the phone before the network is asked about it, so a killed app or a dead signal never costs a night.

### 10.1 Every change goes through one door

`NightStore.mutate(id) { … }` is the only thing that changes a night:

1. apply the change to a copy;
2. put the copy in **canonical form** (encode and decode it, which puts every date at whole milliseconds), so what is in memory, on disk and on the wire are always byte-for-byte equal;
3. if it is not different from before, stop (a "change" that changes nothing is not a change);
4. **re-stamp** `updatedAt` as `max(now, previous + 1 ms)`: strictly later than the previous version even if the clock was set back, which is what makes last-writer-wins safe;
5. write it to disk at once, mark it dirty (queued for the server), and publish it to the screens.

*Files.* One JSON file per night in Application Support, **written to a temporary file and renamed into place** so a crash can't leave half a file. An unreadable file is moved to `quarantine/` (never deleted) and the person is told. A night from a *newer* schema is left alone and not shown, with a message to update. An older one goes through the stepwise `NightMigrator`. A full disk is reported and the write retried, not swallowed.

### 10.2 One sync pass

Syncing starts after a **2-second quiet moment** on any change (a burst of taps is one request), on launch and return to the foreground, and on sign-in. A pass is:

1. **Import** any earlier single-player sessions the account has on the server as one-player nights (once per account; best effort, never in the way).
2. **Push**: for each queued night, one idempotent `PUT /v1/nights/{id}`. If the server answers `applied: true` the night is marked synced, but only if it hasn't changed on the phone since it was sent (otherwise it stays queued with its newer version). If it answers `applied: false` it has kept a *later* edit, and the app adopts that version.
3. **Pull**: ask for nights changed after the stored cursor, **starting 10 seconds before it** (a write the server stamped slightly out of order, because its instances' clocks drift, is still picked up; re-reading a night is harmless because merging is idempotent), in pages of 100. Each night is merged by `updatedAt`.
4. Drop the details of nights deleted more than the undo window ago.

Only one pass runs at a time; a request that arrives during a pass asks for one more pass instead of overlapping. Every failure is a status, never a loss:

| Error | Becomes | Meaning |
|---|---|---|
| no connection, timeout, unreachable | *offline* | changes are safe and will go when there is a connection |
| 401 | *needs sign-in* | |
| the server has no night endpoints (404, 405) or no address | *unavailable* | an older or missing backend; nothing is wrong on the phone |
| the server refused one night (a 4xx other than 404 and 405, or too large) | counted and skipped | the night stays on the phone and the rest still sync |
| 429 | failed, with a gentle message | |
| anything else | failed | "Your nights are safe on this iPhone" |

Signing in as a **different account** re-queues every night on the phone for that account and starts the pull from the beginning.

### 10.3 The merge rules

*On the phone* (`merge`): a night from the server replaces the local one only if its `updatedAt` is **strictly later**. An equal stamp with equal content changes nothing. An equal stamp with different content, or an older server version, keeps the local night and leaves it queued so the server hears about it.

*On the server* (`nights.decide_put`, tested exhaustively without Firebase): the offered night is stored if there is none yet, or if its `updatedAt` is strictly later than the one held. Re-sending the version the server holds changes nothing (so a retry is harmless). A tie with different content keeps the first writer's version and hands it to the second device, so **every device converges on one answer**. The write runs in a Firestore transaction, so two devices writing at once can't overwrite each other's newer edit.

The pull is ordered by `serverUpdatedAt`: a server-assigned, fixed-width UTC timestamp (microseconds) so string order is time order, queried with a single-field index that Firestore builds by itself, so no extra index is needed. The cursor is the last `serverUpdatedAt` returned.

*The trade-off.* Whole nights win or lose, not individual fields: if two phones edit the same night while offline, the later edit replaces the other entirely. That is simple, converges, and suits one person with a couple of devices. *(Inferred: the repository records the rule, not the alternatives considered.)*

### 10.4 What the server refuses, and why

`NightModel` (Pydantic) validates a night **strictly**, with `extra="forbid"`: an unknown field is a 422, not silently dropped. A newer app talking to an older server therefore fails loudly and the night stays safe on the phone, instead of losing the new field on the way through. Limits: at most 30 players, 200 buy-ins per player, 500 breaks, 12 chip colours; a buy-in up to $1,000,000.00 and a cash-out up to $10,000,000.00; dates between 2000 and 2100; colour names short and plain (Firestore rejects map keys that look like `__reserved__`); names 1–40 characters and not blank; ids must be UUIDs (stored upper-case) and players' ids distinct; at most 128 KB per night (413) and 600 writes an hour per user (429). Error messages **never repeat the input**, because it holds players' names.

### 10.5 Deleting and importing

*Deleting a night:* locally it keeps the whole record for an **8-second undo window**, then reduces it to a tombstone. The server stores only a tombstone from the start (id, start time, zone, currency, the two timestamps) and deletes the photos stored for the night. A later "undo" (a newer, un-deleted version) can still win over the tombstone.

*Importing old sessions:* the single-player era saved one record per game. `legacy_night` turns each completed one into a one-player night whose id is derived from the old id with a fixed namespace (UUID v5), so importing the same session twice is a no-op and an edited night is never overwritten. Segments of one old night that were saved separately stay separate nights.

---

## 11. Stats and healthy play

Everything here is computed **on the phone from the nights it holds**, so it works offline, agrees with History, and needs no server.

### 11.1 Stats

`StatsEngine` is pure and is tested against a hand-computed eight-night fixture.

- **Which nights count:** settled, not deleted, the person was playing (`myPlayerID` set), and in the currency of the *most recent* such night (a total across currencies means nothing).
- **Per night:** the stake (the default buy-in), what the person put in, their net after the bank was reconciled, and playtime.
- **Totals:** net, money in, time, wins / losses / break-evens, average buy-in. **Best and worst** night; on a tie the more recent one.
- **Streaks:** a win extends a win streak and resets a loss streak, a loss does the reverse, a break-even resets both. The current streak is positive for wins, negative for losses, zero if the latest night broke even.
- **Per-hour rate:** `net × 3600 / seconds`, shown only from **10 nights** on, "because fewer says nothing"; until then the screen says so.
- **Bankroll over time,** and breakdowns by month, by place (most profitable first; nights with no place last), by weekday (Monday first, the way a week of home games is thought of) and by stake (smallest first). Months, days and weekdays are those of the place the night was played, not of the phone's current zone.
- **CSV export** follows RFC 4180, and a test checks that parsing the export gives back the same rows.

### 11.2 Poker Health: the week

The last seven *local* days, oldest first, ending today; each night counts for the day it started on; time on a break is not played time. **The total is the sum of the bars,** so the two can never disagree at the edge of the window (a bug the first version had). A `WeekTrend` compares this week with last week and shows the last four weeks beside the limit the person set: "1h 20m more than last week", said plainly and never as a scolding. The chip on the screen wears from gold to a skeleton as the limit nears, for fun, with a spoken description.

### 11.3 Healthy-play tools

The tone is the point: *nothing here blocks anyone from their own history or from finishing a night, nothing counts money or time against them in red, and every message is something a good friend might say.* Nothing is said without a limit the person set.

| Tool | Rule |
|---|---|
| **Weekly time limit** (20 hours unless the person changes it) | At **80 %** of the limit: a level-1 word ("You're close to the 20-hour limit you set"). At **100 %**: a level-2 word. |
| **Weekly loss limit** (optional) | If the net of closed nights over the last seven local days is a loss of at least the limit: a level-2 word. It takes precedence over the time word. |
| **Dismissing a word** | "Got it" remembers the week, the reason (time or loss) and the level; the same or a milder word stays away for that week, a *stronger* one still appears. |
| **A break** (24 hours, 3 days or 7 days) | No new night can be started until it ends. It **cannot be shortened once chosen**, because that is the point of it. Nothing else is blocked. |
| **A reminder during a long night** | After N hours of *play* (breaks excluded) a local notification. Nothing is scheduled for a night that is over, paused or already past the mark; permission is asked only when the setting is switched on. |
| **A helpline** | A card in Settings and on Poker Health, chosen by the device's region. |

The helpline directory (`HelplineDirectory`) maps US, Puerto Rico, Guam and the US Virgin Islands to the US national line, GB to GamCare, AU to Gambling Help, CA to the provincial list plus a world finder, and everywhere else to the world finder. Its entries carry the date they were last checked against the organisation's own site (9 October 2026). The US line changed on **29 January 2026**: the National Council on Problem Gambling adopted 1-800-MY-RESET (1-800-697-3738), and the old 1-800-GAMBLER number went back to a New Jersey state council, which is why the brief's number was not used.

*What the app is not.* It tracks chips and time, moves no money and takes no wagers.

---

## 12. The backend, security and privacy

### 12.1 What it is

`ChipVisionService` is a FastAPI app (Python 3.12) in a container on Cloud Run, using OpenCV for counting and the Firebase Admin SDK for Auth, Firestore and Storage. Its pure logic is kept apart from I/O so it can be tested without a network: `nights.py` (the sync rules), `weekly.py` (time-zone bucketing), `photos.py` (decode, limits, metadata stripping), `chip_detection.py` and `side_view.py` (the two counters), `ratelimit.py`. Only `firebase.py` touches Firebase, and the tests replace Firestore and Storage with in-memory fakes.

| Route | Does |
|---|---|
| `GET /healthz`, `/readyz` | process up / Firebase initialised (a load balancer should use `/readyz`) |
| `POST /v1/sessions/{id}/photo` | analyse a photo (§3–§6) |
| `PUT /v1/nights/{id}`, `GET /v1/nights`, `DELETE /v1/nights/{id}`, `POST /v1/nights/import-legacy` | sync (§10) |
| `DELETE /v1/account` | remove every session, night, photo and the Firebase user; safe to retry |
| `/complete`, `/weekly-summary`, `/photo-url`, `DELETE /v1/sessions/{id}` | the single-player endpoints, kept for older app versions |

### 12.2 Decisions and the reasons

- **The app never talks to Firestore or Storage.** Their security rules deny every client request, so "who can read what" is decided in the backend's *tested* code, not in rules that are hard to test. The Admin SDK bypasses the rules. Firebase Auth is the only thing the app uses directly.
- **The service does its own authentication** (Firebase ID token in `Authorization: Bearer`; guest tokens work like any other), so deploying with `--allow-unauthenticated` is correct: Cloud Run's own IAM layer would demand a second scheme on top.
- **Identifiers can't escape the caller's folder.** Session ids are letters, digits, `_` and `-` (at most 64); night ids must be UUIDs; a photo's path is derived from the caller's own uid.
- **Photos are private.** Nothing is public; links are signed and last one hour. Uploads are decoded and re-encoded from pixels, which drops EXIF, GPS and XMP. A 30-day lifecycle file deletes stored photos (applied at deploy, not before). Deleting a night, a session or an account deletes the photos stored for it.
- **No location data is kept** and none is requested.
- **Logs** are JSON with a hashed user id and never include emails, tokens or photo contents.
- **Rate limits** are per user and held in memory, so they are per instance: fine at min-instances 0–1; a shared store is needed if it scales out.
- **The container** is pinned to one Debian release and exact dependency versions, so a rebuild next month is the same image as today's; it runs as an unprivileged user (uid 10001) because "a bug in image decoding shouldn't be root"; it ships `tzdata` because the slim image would otherwise fail every time-zone lookup; and OpenCV's own pixel limit is set to the same 50 million as the service's.
- **Cloud Run settings** in the runbook: 1 GiB, 60 s timeout, 0–3 instances. At zero instances the first request after a quiet spell cold-starts, which is why the app pre-warms the service and treats a slow first call as normal.
- **Deploying is the owner's step:** the commands are written and printed by `deploy.sh`, and nothing has been run against a real project (QUESTIONS A14, B2).

### 12.3 Privacy as shipped

| Fact | Where it is enforced |
|---|---|
| No analytics, advertising or tracking SDK | the Firebase Analytics library was removed; the privacy manifest declares no tracking |
| The privacy manifest declares the one required-reason API used (`UserDefaults`, reason CA92.1) and the data sent to the app's own service: email, name, photos, and the nights' content, linked to the account, none for tracking | `PrivacyInfo.xcprivacy`, checked by the Release build |
| Photos are never written to the phone | `PhotoCapture` is held in memory |
| Only three numbers are read from a photo's metadata | `CameraPose` |
| Account deletion is in the app | `DELETE /v1/account` is called **first**; only on success is the device cleared and the user signed out, so an offline attempt changes nothing |
| Guest mode is real | Firebase anonymous auth, which can be upgraded in place and keeps the same uid and data |
| Share cards leak nothing the person didn't choose | the table card has no names, places or dates; a night summary has no names or results; the weekly recap never says what was won or lost |

---

## 13. Interface and accessibility decisions

[`DESIGN.md`](DESIGN.md) has the tokens, components and measured contrast tables. The decisions behind them:

- **A calm, premium casino-lounge utility.** Dark, purple and gold, rounded heavy titles, evolving the existing badge and seal rather than replacing them. *Restraint over gimmicks:* the host has one hand busy, the room is dim, the phone is at arm's length.
- **Screens use token names, never raw numbers,** so the look is tuned in one place: a 4-pt spacing grid, three radii, type built on Dynamic Type styles with rounded headings and numbers, and *monospaced digits* for money, counts and clocks (which never wrap, but shrink).
- **Contrast is arithmetic, not taste.** Light text is judged against the *lightest* surface it can sit on, by WCAG relative luminance, and enforced by a test on the real colour values: body text at least 4.5:1 everywhere (the tightest pair is error text on its tint at 4.6:1). Colour is meaning-only for positive / negative / warning, never decoration.
- **A black chip is 1.04:1 against the backdrop,** so graphics get a lighter rim and a printed letter, and every chip is labelled with its colour name wherever it can be tapped. *Colour is never the only signal:* chips carry names (and optionally letters), results carry a sign and the words "Up" or "Down", and errors have an icon and text.
- **Touch targets are at least 44 × 44 pt,** including text-only buttons whose whole row responds, because the audit found some responded only on their glyphs.
- **At large text sizes layouts change instead of shrinking** (`ViewThatFits`): chip toggles become full-width rows, rows stack, the Poker Health chart becomes one row per day. Checked at accessibility size 3 on three phones. A pinned bottom bar carries a button, not a paragraph; a note that would take a third of a small screen moves into the scrolling content and stays on the button as its VoiceOver hint.
- **One exception to Dynamic Type:** the camera guide stops growing at the first accessibility size, because at size 3 on the smallest phone the advice took half the screen and cut off the buttons, and a viewfinder can't give its picture to words (the system camera, one tap away, ignores text size).
- **Motion and haptics:** one spring for state changes, off under Reduce Motion; all haptics go through one helper and one Settings switch turns them all off; no decorative animation. The one repeating motion, the clock's blinking dot, is drawn once a second from a timeline rather than with a repeating animation, because a profile showed a repeating animation redraws the screen every frame (15 % of a core on the live night screen; 1.3 % after).
- **Every interactive element has an accessibility identifier,** used by the UI tests. *A trap found the hard way:* an identifier on a *container* replaces the identifiers of the elements inside it as far as UI testing is concerned, so identifiers go on a heading or a leaf, never on a card holding other identified elements.
- **VoiceOver:** custom controls have labels, values and traits; the Result and Poker Health cards read as one sentence; the live clock is marked as updating frequently instead of announcing every second; money and durations are spoken as words. A manual VoiceOver pass has not been done.

---

## 14. How it is tested

| Layer | Count | What it is for |
|---|---|---|
| Backend `pytest` | 171 | endpoints, auth, validation, the nights API (idempotent last-writer-wins, transactions, tombstones that keep no personal data, incremental pulls, legacy import), photo detections and clean-up, the side-view piles (drawn scenes, pose and roll, a real-photo regression), time-zone bucketing, rate limits |
| iOS unit | 484 | money and nights (settlement over 4,000 random nights, the file store, sync against two phones and a rule-following fake server, golden JSON shared with pytest); stats and healthy play (a hand-computed eight-night fixture); the solver and planner; photo checks, the camera advice and coach; view models; cards; the built Info.plist; colour contrast |
| iOS UI | 36 | a whole night from buy-in to Poker Health, kill-and-resume, deletion, validation, photo counting from above and from the side against a stubbed backend, the camera guide on a stand-in camera |
| Tours and audits | 5 | a screenshot of every screen at every device and text size; Xcode's accessibility audit; the same over the camera guide's states |
| Release build | 2 | an unsigned archive both ways: with a real address it must succeed with the widget and privacy manifest; with the placeholder it must fail |

**Techniques that matter more than the counts:**

- **Properties over examples.** The solver's invariants are checked on 700 seeded random inputs; settlement on 4,000 random nights; the photo-edit bookkeeping on a 600-edit random sequence; the break arithmetic on random breaks. The seeds are fixed, so a failure reproduces.
- **Golden files shared across languages.** The app's night encoder and the server's validator are pinned to the same JSON string in both test suites, so a change on one side that the other doesn't expect fails a test.
- **Fakes that follow the real rules.** Firestore and Storage in the backend tests; a scripted network transport and a rule-following fake server in the app's sync tests; a stand-in camera that walks through scripted readings; an in-process fake backend for UI tests (`-UITestMode`). Everything but the lens, the sensors and the real network can therefore be tested.
- **Breakage is injected on purpose.** For the nights API, five deliberate breakages are each checked to be caught by a test.
- **Real photos where they exist,** with a floor just below what was measured, skipped when the photos are absent (they are not in git).
- **Accessibility is measured, not asserted.** Contrast from pixels (153 text elements, median 9.7:1) and from tokens (a unit test); Xcode's audit with an explicit allow-list of 14 documented false positives.

**What the tests cannot say** (QA.md has the full list): how the live camera lens and sensors behave on a phone; the Live Activity and the table card on a physical phone; counting accuracy on real photos beyond the seven; anything against a deployed backend, a real Firestore or bucket; a manual VoiceOver pass; iOS 16 (the simulators here are iOS 18 only); the Release build on a device and TestFlight.

---

## 15. Release engineering

- **One version for every target.** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are set once on the project, so the app, the Live Activity extension and the tests cannot disagree (an App Store upload is refused if the extension's version differs from the app's). `scripts/bump-build.sh` raises the build number.
- **The Release guard.** A build phase that runs only when archiving (`ACTION=install`) fails if: the backend address is the placeholder or isn't HTTPS; the old camera-permission placeholder text is present; a development-only local-network string is present; the privacy manifest is missing; the widget extension is missing; or the widget's version differs from the app's. A local Release build only warns. *A sandbox lesson:* Xcode's script sandbox lets a phase read only the files it declares, so the guard declares the widget's `Info.plist` as an input; before that, the version check failed on versions that matched.
- **The backend address is a build setting** (`API_BASE_URL`), different per configuration: Debug defaults to a LAN address, Release must be HTTPS.
- **The app icon has light, dark and tinted variants.** There is no iPad support, and portrait is enforced at run time (the table card widens it).
- **String Catalog.** `Localizable.xcstrings` holds the literal text SwiftUI extracts. English only; nothing translated. Text assembled in code is not in it yet.
- **Continuous integration** (`.github/workflows/ci.yml`, written and never run, because the project had no remote of its own): the app's unit and UI tests, the unsigned Release archive both ways (it must carry the widget and the privacy manifest with a real address, and be refused with the placeholder), the backend tests plus a container build, and a guard that looks for development leftovers in sources and settings. Inside the `PokerChipCountingApp/` folder of the owner's shared repository the workflow sits below the repository root, where GitHub does not read it.
- **The owner's steps, written as exact commands:** signing, the backend deploy (`deploy.sh` prints the plan; `--apply` runs it), the Firebase console switches (anonymous sign-in, restricting the API key to the bundle ID), TestFlight and submission. No billed cloud resource, console setting or store action has been taken on the owner's behalf.
- **Legal drafts and App Store text** are in `docs/legal/` and `docs/APPSTORE.md`; the privacy answers there match the manifest and the server's real behaviour.

---

## 16. Decision log

One row per decision that shaped the project. "Why" is the reason the repository records (in code comments, tests or the other docs); *(inferred)* marks a reason the repository does not state. Section numbers point to the full account.

### Architecture and data

| # | Decision | Set aside | Why | Where |
|---|---|---|---|---|
| D1 | **Local-first:** a night lives in files on the phone and is mirrored later | server-first | nothing waits for the network; a killed app or dead signal costs nothing | §10 |
| D2 | **The app never talks to Firestore or Storage;** their rules deny every client | client SDK guarded by security rules | "who can read what" lives in tested backend code | §12 |
| D3 | **Pure logic, thin shells** (solver, night rules, settlement, stats, healthy play, camera advice; sync rules and both counters on the server) | logic inside views | testable without a phone, camera or network | §1.1, §14 |
| D4 | **Integer cents everywhere** | dollars as `Double` | totals reconcile to the cent; settlements sum to zero; fixes the old `Double(text)` parsing and hard-coded `$` | §9.6 |
| D5 | **The clock is derived** (`now − start − breaks`), not a counter a view owns | a timer in a view | survives the app being killed or navigated away; fixes the old restart on `onAppear`; the Lock Screen clock counts itself from `clockStart` | §1.4 |
| D6 | **Rebuys are events** | a rebuy counter / running total | undo, complete history, no double-counted playtime | §9.1 |
| D7 | **Last-writer-wins on the whole night** by its own `updatedAt` | field-level merge; server time | simple, converges for one person's few devices *(inferred)*; ties keep the first writer so devices agree | §10.3 |
| D8 | **Every change is stamped strictly later** (`max(now, previous + 1 ms)`) | plain `Date()` | a clock set back must not reorder history | §10.1 |
| D9 | **One canonical JSON form** (whole-millisecond dates, sorted keys) for disk, memory and wire | separate shapes | "has this changed?" never turns on a fraction of a millisecond; the same bytes everywhere | §10.1 |
| D10 | **Deleted nights become tombstones with no personal data** | hard delete; keep everything | other devices need the marker; privacy | §9.5, §10.5 |
| D11 | **The server refuses unknown fields** (`extra="forbid"`) | silently drop them | a newer app on an older server fails loudly and the night stays safe | §10.4 |
| D12 | **A golden JSON string shared by the Swift and Python tests** | separate fixtures | a change one side doesn't expect fails a test | §14 |
| D13 | **Idempotent writes** (`PUT`, delete, legacy import by UUIDv5) | POST-style creates | a retry after a dropped connection is harmless | §10 |
| D14 | **Quarantine, never delete,** an unreadable night file; ignore a newer-schema night | overwrite or crash | no night is ever lost to a format problem | §10.1 |
| D15 | **Bank resolutions store the difference they were made for** | a bare choice | a corrected cash-out must make the night ask again | §9.3 |
| D16 | **A tip can only cover a shortfall** | tips for any difference | chips can't appear from nowhere | §9.3 |
| D17 | **Even shares in whole cents, the first people taking the extra cent** | rounding each share | the shares always add to the amount | §9.3 |
| D18 | **Settle with the greedy largest-pair rule** (at most n − 1 payments), ties by name then id | exact minimum | simple and explainable; deterministic *(inferred)*. Not always the fewest (§9.4) | §9.4 |
| D19 | **Stats count only closed nights the person played, in the latest currency; the hourly rate waits for 10 nights** | all nights; always show a rate | a total across currencies means nothing; fewer nights is mostly luck | §11.1 |
| D20 | **Weekly figures use the player's local days, attribute a night to its start day, and total the bars** | UTC days; a separate total | an 8 pm game is "today"; the two numbers can never disagree | §11.2 |

### Chip values

| # | Decision | Set aside | Why | Where |
|---|---|---|---|---|
| D21 | **Exact sum is never negotiable; correct shape outranks the 20–30 window; refuse rather than bend** | accept near-misses | a stack that ties or inverts counts "isn't what was asked for"; "too small" is a better answer | §2.1 |
| D22 | **A clean quarter ladder** (5¢, 10¢, then multiples of 25¢) | arbitrary values; a 1-2-5 series | "easy mental math instead of odd values like $0.35". Cost: $4.25-style values (§17) | §2.3 |
| D23 | **Target 30 chips with two players sliding to 20 with ten** | a fixed total | "more players means less felt per player" | §2.4 |
| D24 | **First-guess values scale off the average chip, per colour** (0.3 / 0.6 / 1.1 / 2.0 / 4.0) | scaling off the buy-in | keeps Black affordable on small buy-ins | §2.5 |
| D25 | **Counts follow a negative exponential by rank** (decay 0.55) | equal counts | a real set racks many low chips and few high ones | §2.6 |
| D26 | **Two cheapest colours stay free and are closed by a divisor search** | one free colour; brute force | one is too coarse on a quarter ladder; the divisor trick makes the sum exact by construction and keeps it fast | §2.7 |
| D27 | **Seven count scales, then three escalation tiers** (a nickel-safe exception for the cheapest colour; thin scales for tiny buy-ins) | one pass | different scales turn an impossible leftover into a possible one; the exception is how a real set copes with odd cents | §2.8–2.9 |
| D28 | **The planner wraps the solver and fails with a reason and a remedy** | a generic "can't do it" | tell the person what would work (next buy-in, fewer players, drop a colour, nearby amounts) | §2.13 |
| D29 | **Blinds: small blind a whole number of the smallest chip, stack near 100 big blinds** | arbitrary blinds | every bet can be paid with the chips on the table; the usual deep-stack home game | §2.14 |
| D30 | **Inventory caps are `owned ÷ players`** | no cap | a suggestion must never deal chips that don't exist | §2.13 |

### Photos and the camera

| # | Decision | Set aside | Why | Where |
|---|---|---|---|---|
| D31 | **The counts are the source of truth; a photo is a suggestion;** every edit moves the counts by the same amount | trusting the count | stacked chips are genuinely hard to read; classic CV undercounts | §8 |
| D32 | **Counting by hand never needs the network or the camera** | photo-only | the app must work in a basement with no signal | §3 |
| D33 | **Classical computer vision, no trained model** | a trained detector | stated trade-off: undercounts hidden chips, so the review step is mandatory *(why not ML is not recorded)* | §3.2 |
| D34 | **Two photo modes, chosen by the person** | auto-detecting the view | the counters rest on different geometry, and a stack from above is one circle; letting the person choose is simpler than detecting it *(inferred)* | §3 |
| D35 | **Top view: Hough circles plus filters** (merge, isolation, texture, size, focus, chromatic anchors) | Hough alone | each filter removes a failure seen on real photos | §4 |
| D36 | **The second, permissive Hough pass was removed** | keep it to rescue black chips | it added frequent overcounts to rescue rare misses; an overcount is the misleading failure | §4.3 |
| D37 | **Top-view colour is the nearest of five references in HSV, from the median of the centre patch** | whole-disc mean; learned colours | the centre avoids neighbours' edges; the median shrugs off stray pixels | §5.1 |
| D38 | **The colour set is closed at five** | open vocabulary | matches the app's chip colours *(inferred)*; a sixth colour is forced to the nearest | §5.1 |
| D39 | **A pile is named for its body colour, never its tabs** (the owner's rule, A12) | renaming to the colours in play | a white chip with blue tabs is White; renaming was removed | §5.2 |
| D40 | **Side view uses the camera's tilt from the phone's sensors** and a physical chip model (0.0846) | guessing the angle from the picture | the count depends on foreshortening, which the sensors give accurately | §6 |
| D41 | **Height rule from four walls up, rings of tabs below** | one method | *(inferred)* a short pile has too little height to measure against the uncertainty in the top face, a tall one hides most of its rings; the code records the rule, not the reason | §6.5 |
| D42 | **Side-view confidence is never "high"** (it is `low` today) | claiming confidence | measured on seven photos of one set | §6.9 |
| D43 | **Check the photo on the phone first, and only advise** | server-side rejection | a bad photo is retaken at the table, not after a slow round trip; the person may always use it | §3.1 |
| D44 | **The camera guide advises and never blocks;** a fixed priority; smoothed with a settle time | locking the shutter; raw readings | a wrong block is worse than a missing hint; words shouldn't flicker | §7 |
| D45 | **Sharpness advice is set low (80) against 250 for the finished photo** | the same limit | "a wrong 'it's soft' is worse than a missing one" | §7.2 |
| D46 | **Photos are held in memory only on the phone; only three numbers are read from metadata; the server strips the rest** | storing photos locally | privacy | §3, §12 |
| D47 | **Pre-warm the counting service** when a night or cash-out opens | wait for the first photo | a service scaled to zero takes seconds to answer | §8 |

### Product, platform and process

| # | Decision | Set aside | Why | Where |
|---|---|---|---|---|
| D48 | **iOS 16.4, iPhone only, portrait (the table card lands in landscape), dark only** | iPad, all orientations, light mode | a deliberate v1 simplification; the card is read across a table; the room is dim | §1.2 |
| D49 | **No analytics, advertising or tracking** (the unused Analytics library was removed) | usage analytics | privacy; nothing used it. Crashlytics is deferred to 1.1 (A7); App Check is not planned (A8) | §12.3 |
| D50 | **Healthy play never blocks anything except a break the person chose,** which cannot be shortened | hard locks; red numbers | the tone is the point; a short-circuitable break defeats it | §11.3 |
| D51 | **The US helpline is 1-800-MY-RESET** | 1-800-GAMBLER | the old number was retired on 29 January 2026 | §11.3 |
| D52 | **Guest mode is Firebase anonymous auth,** upgradable in place; **account deletion calls the server first** | local-only guest; delete locally first | the same uid keeps the data; an offline attempt changes nothing | §12.3 |
| D53 | **One version for every target and a Release guard on archives** | per-target versions; manual checks | an App Store upload is refused if the extension's version differs; placeholders must not ship | §15 |
| D54 | **A stand-in camera and an in-process fake backend for tests** | testing only on a device | the Simulator has no camera; UI tests must run anywhere | §14 |
| D55 | **Camera tips are on by default** (the owner's decision) | off by default | one tap away from the standard camera; Settings turns it off | §7.4 |
| D56 | **Tournament mode is not built** (A6 is open) | building it for 1.0 | two to three weeks and a second rule set; a blind timer alone would be about three days | QUESTIONS A6 |
| D57 | **The Live Activity is built; the weekly-hours widget is not** | an App Group | an App Group needs a paid developer team (A11) | §1.4 |
| D58 | **Nothing billed, console-side or irreversible is done without the owner:** no deploy, console change, TestFlight or force-push | acting on the owner's behalf | the owner's standing instruction. Publishing the code to the owner's GitHub repository was done at their explicit request | §15 |

---

## 17. Limits, weak spots and open questions

Honest, in one place. Each says what it is, why it matters and what would address it. Items marked **found while writing this document** were not recorded anywhere before.

### Chip values

1. **Odd-looking values are legal.** The ladder is every quarter, so $4.25 and $8.75 are "clean" (the $50, eight-player example) though a host would choose $5 and $10. *Would address:* a friendlier ladder (a 1-2-5 style series) for the dearer colours. That changes the rules in §2.1 and their tests, so it is a design decision, not a fix. **Found while writing.**
2. **Three or four colours on a small buy-in can run past 30 chips** (39 chips for $20 over three colours and four players; 33 for $20 over four colours and five players, and for $25.05 over three colours and six), because exact sum and shape outrank the window and only the two cheapest colours are free. The 90 % window rate is measured for five colours only. **Found while writing.**
3. **The cheapest chip can be an odd value** (45¢, 70¢) when tier 2 is needed, close to the next colour's value (50¢, 75¢). **Found while writing.**
4. **Neighbouring table sizes can give quite different stacks** (White 25¢ at six players, 75¢ at four), because the first guess moves with T. **Found while writing.**
5. **USD only,** and the buy-in is rounded to the nearest nickel.

### Counting from above

6. **It counts faces, not chips.** A stack is one circle; touching chips can merge.
7. **Five colours only.** Orange, yellow and pink read as Red, purple as Red or Blue, teal as Blue; a grey table reads White or Black by brightness (§5.1). **Found while writing** (the full map).
8. **Tuned on nine photos and one synthetic image;** accuracy on unseen photos is not measured. A white-with-blue-edges chip has not been measured from above.
9. **It assumes a near-overhead camera.** The guide asks for at least 72°, where a face is squashed by about 5 %.

### Counting from the side

10. **It needs rim tabs and at least one red, green or blue pile,** and was measured on seven photos of one chip set.
11. **Short piles are the weak regime.** On drawn scenes the ring rule reports one chip too few for piles of 2, 3 and 4, where rounding the height estimate alone would have been right; on the real photos a pair is right about half the time. *Would address:* test a height-based count for short piles against real photos before changing anything. **Found while writing.**
12. **Tall stacks of real chips are unmeasured** (QUESTIONS A13). On drawn scenes five or more chips are within one.
13. **A portrait picture's lens model may be too wide.** `focal35 · width / 36` is exact for a landscape 3:2 picture but, for a portrait one, comes out about 28 % too short, which exaggerates how the elevation changes away from the middle row (§6.3). Piles near the middle row are barely affected. *Would address:* convert with the picture's diagonal, then compare on real photos. **Found while writing; not measured.**
14. **Confidence is `low` for every pile today,** by design.
15. **The module's own docstring described an area-based count the code no longer used, and two constants were dead.** Corrected while writing this document (comments and two unused constants only; the 171 backend tests still pass). **Found while writing.**

### The camera guide

16. **The live lens, motion sensors and real frames have never run on a device,** and the advice thresholds are reasoned, not measured. The stand-in camera tests everything else.
17. **The reason for the 72° "flat enough" limit isn't recorded;** its geometric meaning is in §4.4.

### Money, sync and the server

18. **Settle-up is "at most n − 1 payments", not "the fewest".** The five-person example in §9.4 takes four where three would do. The wording in the README and the App Store draft was corrected to match. **Found while writing.**
19. **Whole-night last-writer-wins.** Two phones editing the same night offline: the later edit replaces the other entirely.
20. **The photo and night rate limits are per instance,** not global.
21. **Nothing has run against a real Firebase project:** the nights API against a real Firestore, the 30-day photo lifecycle, the anonymous sign-in switch, restricting the API key to the bundle ID (QUESTIONS B1–B2, A14). The backend is tested against fakes and in a container with no credentials.

### Verification gaps (QA.md has the full list)

22. iOS 16 (the simulators are iOS 18 only); a manual VoiceOver pass; accessibility sizes 4 and 5; Reduce Motion; the table card, share sheets, break reminder and Live Activity on a physical phone; the Release build on a device and TestFlight.

### Not built, by decision

23. Tournament mode (A6, open), Crashlytics (planned for 1.1), App Check (no), the weekly-hours widget (needs a paid team, A11), translations, iPad.

---

## Appendix A: every threshold in one place

### A.1 Chip values (`DenominationEngine.swift`, `BlindsPlanner.swift`)

| Constant | Value |
|---|---|
| Clean ladder | 5¢, 10¢, then every multiple of 25¢; snap crossover 17.5¢ |
| Buy-in | rounded to the nearest 5¢ (ties away from zero), at least 5¢ |
| Target chips T(P) | `round(30 − 10·(clamp(P, 2, 10) − 2)/8)`; window 20–30 |
| Natural multipliers of the average chip | White 0.3, Red 0.6, Blue 1.1, Green 2.0, Black 4.0 |
| Count decay | `e^(−0.55·rank)` |
| Count scales | 0.6, 0.75, 0.9, 1.0, 1.1, 1.25, 1.4; thin: 0.45, 0.3, 0.2, 0.12, 0.06 |
| Free colour count bound | 1 … min(40, leftover ÷ value, cap) |
| Second-cheapest value bump | up to 4 rungs, below the next colour's value |
| Candidate score | `10·(chips outside 20–30) + 0.05·\|total − T\| + 0.02·\|ln v₁ − ln v₁*\|` |
| One-colour scan | counts T ± 0 … 3,999 |
| One-colour minimum within a set | 5 chips |
| Fixed-value search | 2,000,000 steps; default cap 100 per colour |
| Fewer / finer chips pool | stacks of at least 8 chips |
| Next working buy-in | scanned in 5¢ steps up to $10 |
| Nearby amounts | 200 steps each way on the grid of the values' gcd |
| Lower-buy-in alternative | 90, 80, 70, 60, 50 % rounded to quarters (at least 25¢) |
| Presets | 100, 200, 300, 500 chips; cap per player `owned ÷ players` |
| Blinds | small = k·u, big = 2·k·u; the k nearest 100 big blinds |
| Smallest buy-in for 3 / 4 / 5 colours | 60¢ / $1.50 / $3.15 |

### A.2 Photo path

| Item | Value |
|---|---|
| On-phone check | 256-px grey copy; blurry below sharpness 250; dark below 35; washed out above 225; small below 600 px |
| Upload | long edge ≤ 1600 px; JPEG 0.7 |
| Client network | 15 s request / 60 s total timeout; 3 attempts, 0.6 s then 1.5 s back-off on 502–504 and transient errors; one forced token refresh on 401; pre-warm at most every 300 s (10 s timeout) |
| Server limits | 10 MB; 50 MP; stored JPEG quality 90; 60 photos an hour per user; signed links last 1 hour; 30-day lifecycle |
| Photos per cash-out | up to 4; a pile holds 1–99 |

### A.3 Counting from above (`chip_detection.py`)

| Item | Value |
|---|---|
| Working size | long edge ≤ 1280 px; median blur 5 |
| Hough | `dp` 1.2; Canny 100; accumulator 20; `minDist` 1.5·min radius; radii `max(8, min(h,w)/60)` … `max(min+4, min(h,w)/12)` |
| Duplicate merge | centres closer than 1.8 × the larger radius |
| Colour patch | median HSV, half-width `max(2, r/3)` |
| Isolation | ring 1.05 r … 1.4 r; contrast ≥ 25 |
| Black texture | brightness std ≥ 15 over 0.75 r |
| Size filter | ±25 % of the median radius (≥ 3 circles) |
| Focus filter | ≥ 20 % of the sharpest circle's Laplacian variance |
| Anchor box | coloured circles' bounding box + 3.5 × the largest radius |
| Confidence | ambiguous when patch saturation std > 60; > 35 % low, > 15 % medium, else high |
| Reference colours (H, S, V) | White (0, 0, 220), Red (0, 200, 200), Blue (110, 200, 200), Green (60, 200, 180), Black (0, 0, 30) |
| Distance | `(2Δh)² + Δs² + Δv²`, hue circular |

### A.4 Counting from the side (`side_view.py`, `CameraPose.swift`)

| Item | Value |
|---|---|
| Working size | long edge ≤ 1280 px |
| Chip | thickness ÷ diameter 0.0846 (3.3 mm ÷ 39 mm) |
| Default pose | pitch 22°, 24 mm lens, confidence low |
| Valid pose | 0.7 < \|g\| < 1.3; focal 8–200 mm; server: pitch −30…90, roll ±180 |
| Level rotation | when \|roll\| ≥ 1° |
| Elevation | `pitch + atan((row − h/2)/f)`, `f = focal35·width/36`, limited to 4°…80° |
| Colour masks (Lab) | Red a > 22, b > −5, C > 30, L > 20; Green a < −8, b > 4, C > 12; Blue b < −18, C > 22 |
| Tab | L > 70, C < 14, area 0.15–1.6 % of width², fill ≥ 0.35, aspect 0.3–6 |
| White body | (L > 72, C < 12) or (C > 25, b < −8); ≥ 2 accents |
| Anchor pile | area 0.10–5 % of the picture; aspect 0.25–7; solidity ≥ 0.30; ≥ 3 tabs |
| Piles of one size | ±50 % of width; bottoms within 1.2 widths |
| Silhouette growth | 12 % of a chip's width |
| Height counting | from 4 walls up; central height ±12 % of the width around the middle |
| Ring counting | radius 0.86·D/2 (×0.9, 1.0, 1.1); chord 0.25–2 r; inliers within 13 % of r; ≥ 3 inliers (≥ 4 for black); spread ≥ 40°; up to 6 rings; sin θ floor 0.15 |

### A.5 Camera guide (`FramingAdvisor.swift`, `GuidedCamera.swift`)

| Item | Value |
|---|---|
| Upright | pitch < 75° and \|roll\| > 35° (side only) |
| Dark / washed out | brightness < 35 / > 225 |
| Flat enough (above) | pitch ≥ 72° |
| Side: pitch range | −8° … 30° |
| Side: level | \|roll\| ≤ 5° |
| Still | turning ≤ 0.8 rad/s; "soft" below sharpness 80 |
| Smoothing | 30 % of each new reading; turning not smoothed |
| Settle | 0.5 s; "ready" 0.9 s |
| Sample rates | sensors and advice 10 Hz; frames at most every 0.2 s from 640 × 480 video |
| Failure | offers the standard camera if it can't start within 6 s |

### A.6 Nights, sync and healthy play

| Item | Value |
|---|---|
| Sync | quiet period 2 s; pull overlap 10 s; page 100 (server maximum 200); undo window 8 s |
| Server limits | 30 players; 200 buy-ins each; 500 breaks; 12 colours; night body 128 KB; 600 night writes an hour |
| Stats | hourly rate from 10 nights |
| Healthy play | word at 80 % and 100 % of the weekly limit (default 20 h); breaks of 24 h, 3 d, 7 d; reminder after N hours of play |

---

## Appendix B: glossary

- **Anchor pile:** a red, green or blue pile that shows rim tabs; it fixes the chip size and the row the others stand in.
- **Average chip (a):** the buy-in divided by the target chip count; the scale the first-guess values hang from.
- **Body colour:** the colour of the chip's main face, as opposed to its printed tabs or logo; the only thing a chip is named for.
- **Bank difference (Δ):** the cash-outs minus the buy-ins; zero when the bank balances.
- **Clean ladder:** the allowed chip values: 5¢, 10¢ and every multiple of 25¢.
- **Cursor:** the last `serverUpdatedAt` the phone has seen; the next pull asks for what changed after it.
- **Elevation (θ):** the angle between the line of sight and the table; 0° along it, 90° straight down. **Pitch** is the camera's elevation at the centre of the picture; **roll** is how far the picture is turned about the camera's axis.
- **Last-writer-wins:** the rule that the version with the strictly later `updatedAt` replaces the other.
- **Net:** what a player cashed out minus what they put in, after the bank resolution.
- **Rank:** a colour's place among the colours in use, cheapest first (0, 1, …).
- **Ring (of tabs):** the circle on which one chip's rim tabs lie; seen from an angle, an ellipse.
- **Scale (s):** the factor applied to the expensive colours' first-guess counts; seven are tried.
- **Shape (correct):** values strictly rising and counts strictly falling with colour rank.
- **Tab:** a bright, almost colourless printed rectangle on a chip's rim.
- **Tier:** an escalation of the solver's search: ladder only, then one nickel-safe exception, then thin counts for tiny buy-ins.
- **Tombstone:** what remains of a deleted night: id, start, zone, currency and timestamps, nothing personal.
- **Wall:** the side face of one chip; `0.0846 · width · cos θ` tall in the picture. A stack's height is measured in walls.
- **Window:** the 20–30 chips-per-player range.

---

## Appendix C: reproducing the numbers

From the repository root. None of these change the app or the backend; the Swift tools compile the app's real source files on their own.

| To reproduce | Run |
|---|---|
| §2: what the solver, planner and blinds return | `swiftc -O -o /tmp/solver_demo docs/tools/solver_demo/Support.swift docs/tools/solver_demo/main.swift PokerChipApp/Views/Denominations/DenominationEngine.swift PokerChipApp/Views/Denominations/BlindsPlanner.swift && /tmp/solver_demo` |
| §2.8: the search, from a second implementation that agrees with the solver on all 16 cases listed | `python3 docs/tools/solver_replica.py` |
| §9: the bank check, resolutions and settle-up | `swiftc -O -o /tmp/settle_demo docs/tools/settle_demo/main.swift PokerChipApp/Views/Nights/Model/Settlement.swift PokerChipApp/Views/Nights/Model/NightMath.swift PokerChipApp/Views/Nights/Model/GameNight.swift PokerChipApp/Views/Core/Money.swift && /tmp/settle_demo` |
| §5.1: how a colour is named from above | `python docs/tools/colour_map.py` (with the backend's environment: numpy and OpenCV) |
| §6: the angle tables | `python3 docs/tools/geometry_tables.py` |
| §6.8–6.9: the side-view counter on drawn stacks | `python docs/tools/side_view_walkthrough.py` (with the backend's environment) |
| §13: contrast ratios | `python3 docs/tools/contrast.py` |
| All tests | the commands in [`QA.md`](QA.md) |

The backend's environment is `cd ChipVisionService && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements-dev.txt`.

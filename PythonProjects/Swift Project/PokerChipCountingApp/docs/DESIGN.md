# Design

A calm, premium casino-lounge utility: dark, purple and gold, rounded heavy titles. This evolves the existing identity (the purple badge icon, the gold Van Arp Studios seal) rather than replacing it. Restraint over gimmicks — the host has one hand busy, the room is dim, and the phone is at arm's length.

Everything below lives in `PokerChipApp/Views/DesignSystem/` (tokens and components) and `Views/Theme.swift` (brand colours, backdrop, card and field styles). Screens use token names, never raw numbers, so the look can be tuned in one place.

## Tokens

**Spacing** — a 4-pt grid: `xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32 · huge 48`. Screen gutter 16. Minimum touch target 44.

**Radius** — `control 12 · card 18 · sheet 28`.

**Type** — built on Dynamic Type text styles so everything scales with the reader's text size. Rounded design is the brand voice for headings and numbers; body copy stays in the plain system face for legibility.

| Token | Style |
|---|---|
| `pokerDisplay` | large title, rounded, heavy |
| `pokerTitle` | title 2, rounded, bold |
| `pokerHeadline` | headline, rounded |
| `pokerBody` / `pokerCallout` / `pokerFootnote` | system body / callout / footnote |
| `pokerCaption` | caption, semibold (uppercase section labels use it with +0.8 tracking) |
| `pokerNumeric(style)` | rounded, bold, **monospaced digits** — money, counts, clocks. These never wrap: `lineLimit(1)` + `minimumScaleFactor` |

The brand title (`PokerTitle`) is the gold gradient and is used sparingly: Home, the welcome screen.

**Colour roles**

| Role | Value | Use |
|---|---|---|
| `pokerGold` / `pokerGoldLight` | `#D9AD52` / `#F5D68F` | primary actions, key numbers |
| `pokerPurpleLight` | `#B89EEB` | section labels, secondary actions, info |
| `pokerBackgroundTop` → `Bottom` | `#1A1226` → `#05040A` | the backdrop gradient |
| `pokerSurface` | white 6% | cards |
| `pokerSurfaceRaised` | white 10% | text fields, raised surfaces |
| `pokerStroke` | gold 22% | card hairline |
| `pokerTextPrimary / Secondary / Tertiary` | white 95% / 72% / 58% | text levels |
| `pokerPositive` / `Negative` / `Warning` | `#4DCC85` / `#F77373` / `#FAB84D` | meaning only (results, validation, status) — never decoration |

### Measured contrast

Computed with WCAG 2.x relative luminance by `docs/tools/contrast.py` (run it with `python3 docs/tools/contrast.py`; update it when a colour token changes). Light text is judged against the **lightest** surface it can sit on: the backdrop's top stop plus a 10% white overlay.

| Text | on backdrop top | on card | on raised / field |
|---|---|---|---|
| Primary (white 95%) | 16.4 | 14.2 | **12.6** |
| Secondary (white 72%) | 9.7 | 8.7 | **7.9** |
| Tertiary (white 58%) | 6.7 | 6.2 | **5.7** |
| *Replaced:* old captions (white 40–45%) | 3.8 / 4.5 | 3.7 / 4.3 | 3.5 / 4.1 — **failed 4.5:1** |

| Colour | on backdrop top | on card | on raised |
|---|---|---|---|
| Gold | 8.7 | 7.5 | 6.6 |
| Gold light | 12.9 | 11.1 | 9.8 |
| Purple light | 7.9 | 6.8 | 6.0 |
| Positive | 8.9 | 7.7 | 6.8 |
| Negative | 6.6 | 5.7 | 5.0 |
| Warning | 10.4 | 8.9 | 7.9 |

| Component | Pair | Ratio |
|---|---|---|
| Primary button | black on gold → gold-light | 10.1 – 14.9 |
| Secondary button | purple light on its fill | 7.0 |
| Destructive button | negative on its fill | 5.8 |
| Info / success / warning banner text | tint on 14% tint | 5.2 / 5.9 / 6.6 |
| Error banner text | negative on 14% tint | **4.6** (the tightest pair; it clears 4.5) |

Everything clears 4.5:1 body / 3:1 large. The one exception that mattered was **graphics, not text**: a Black chip is only 1.04:1 against the backdrop, so chips get a lighter rim (`ChipPalette.rim`) and a printed letter, and every chip is labelled with its colour name wherever it can be tapped.

## Components

| Component | Purpose |
|---|---|
| `PokerButton` | The only button. Kinds: `primary` (gold), `secondary` (outlined), `destructive`, `quiet`. Loading and disabled states; 44–54 pt tall; a light haptic on press. A `NavigationLink` label uses `.pokerSecondaryLabel()` for the same look |
| `ChipView` | A vector chip: edge spots, inner ring, rim. Draws a letter (W R B G **K**lack-as-K) when "Differentiate Without Color" or the in-app option is on. Dimmed state for "not available" |
| `StepIndicator` | "Step 2 of 4 · Chips" through Buy-in → Chips → Play → Count |
| `StepperField` | −/+ buttons around a number field; whole numbers with a range; 44 pt targets |
| `ListRow`, `StatTile`, `SectionHeader` | Cards and labels |
| `InlineBanner` | info / success / warning / error, with an optional action |
| `EmptyState` | Icon, title, message, one recovery action |
| `SkeletonView` | Shimmering placeholder while loading; static under Reduce Motion |
| `MoneyText`, `DurationText` | Locale-aware amounts and times, monospaced, never wrapping, spoken in words to VoiceOver |
| `PokerBackground`, `.pokerCard()`, `.pokerTextField()` | Backdrop, card, field |

| `FlowLayout` | Wraps quick-pick chips onto as many lines as they need (names, places, regulars) |
| `TableCardArtwork` | The chip-values card: sized from its height, not Dynamic Type, because it is read across a table; the same view is drawn full screen and rendered to PNG/PDF |
| Photo review | The photo with a ring on every counted chip (chip colour inside a light edge, so it shows on any felt); the selected ring is gold and thicker; rings get a ≥ 44 pt hit area; a letter appears on each ring under "Differentiate Without Color" |
| Share cards | `NightSummaryCard`, `WeeklyRecapCard`, `SettlementCard`: 360 pt wide, the app backdrop with a gold hairline, no names unless the card is about who pays whom |
| Side-view review | The same photo with a box round each pile (the chip colour inside a light edge) and a count badge; the selected pile is gold; the stepper under the photo changes the count, a second row changes the colour |
| Camera guide | A full-screen camera in black with one pill of advice at the top (an amber ⚠ while something needs doing, a green ✓ when it is ready), a dashed frame to put the chips in, a level line for photos from the side, the tilt in degrees, and an 84 pt shutter that is never disabled by advice. Cancel at the left and "Standard camera" at the right, both ≥ 44 pt (the frame is inside the button, so the whole area answers). The words change at most every half second; VoiceOver is told each new sentence once. **Text stops growing at the first accessibility size**: at AX3 on an iPhone SE the advice took half the screen and the buttons were cut off, and a viewfinder can't give its picture to words (the system camera, one tap away, ignores text size altogether) |
| Lock Screen / Dynamic Island | The app's dark purple and gold. "Playing" or "On a break" over the clock, a large monospaced timer the system counts itself; the money on the table and the player count beside it; one Break / Resume button in a gold capsule; a tap anywhere else opens the night |

Not built yet: a transient `Toast` (inline banners cover every current case) and previews at the largest accessibility sizes.

## Motion and haptics

- One spring for state changes, `response 0.35, damping 0.85` (`pokerSpring`). It is switched off by **Reduce Motion**, as are the shimmer and the clock's blinking dot.
- All haptics go through one `Haptics` helper and the Settings toggle turns every one of them off.
- No decorative animation. The only motion that repeats is the game clock's dot, which blinks once a second in step with the clock rather than pulsing with a repeating animation: a repeating animation redraws the screen every frame, which a profile showed was 15% of a core on the live night screen, and should keep a ProMotion display at a high refresh rate while the screen is kept awake all night (not measured; the CPU figure is now 1.3%).

## Accessibility decisions

- Every interactive element is at least 44×44 pt; the chip toggles are a 57×68 column.
- Colour is never the only signal: chips carry a letter (optionally) and always a name; selection shows a check badge; results show a sign and the words "Up"/"Down"; errors have an icon and text as well as a red outline.
- VoiceOver: custom controls have labels, values and traits (chip toggles read "White chips, available"); the Result and Poker Health cards read as one sentence; the live clock is marked as updating frequently rather than announcing every second.
- Dynamic Type: type uses text styles throughout (the one deliberate exception is the camera guide, above); money and time scale down (`minimumScaleFactor`) rather than truncating or wrapping; screens scroll. At accessibility sizes layouts **change instead of shrinking**: the chip toggles become full-width rows, the Suggested, Review and Custom rows and the Home header stack (`ViewThatFits`), the quick-pick grid's column width scales with the text, and the Poker Health chart becomes one row per day. Checked at AX3 on iPhone SE, 16 and 16 Pro Max (`docs/qa/after/*-ax3`); AX4–AX5 were not captured.
- A pinned bottom bar carries a button, not a paragraph. At accessibility sizes a note under the button (why it is disabled, what closing does) would take a third of a small phone's screen, so it moves into the scrolling content and stays on the button as its VoiceOver hint (Bank check, Settle up, the live night). `ListRow`, the Suggested header and blinds, the cash-out photo buttons, the bank-check rows and the buy-in history rows switch with `ViewThatFits` or the text size, so no word is ever broken mid-way. Controls that would be cut off (the photo review's) get a scroll view of their own.
- Every interactive element has an `accessibilityIdentifier` (`home.newGame`, `buyin.amount`, `review.count.White.plus`, …) used by the UI tests. An identifier goes on a leaf or a heading, or on a real accessibility container — never on a plain stack that holds other identified elements, which would replace theirs.

## Known gaps

- **Localization.** Money, numbers and dates are locale-aware and input is parsed with the locale. `Localizable.xcstrings` is a String Catalog of the text SwiftUI takes from literals (`Text("…")`, `Button("…")`, labels): English only, nothing translated. Messages assembled in code as plain `String`s — the camera guide's advice, the healthy-play nudges, error descriptions — are *not* in it and would need `String(localized:)` before a translation could reach them; nothing has been checked in a right-to-left language.
- **Orientation and devices.** Portrait, iPhone only (a deliberate v1 simplification). The one exception is the table card, which is designed for landscape and is the only screen that rotates; the camera is portrait too. iPad is excluded.
- **AX4–AX5** were not captured (AX3 was), and a Toast component is not built. See `docs/QA.md` for what was and wasn't checked.

# App Store page — drafts for you to edit and submit

Everything below is a draft written from what the app actually does. The name, the support and privacy URLs, and every questionnaire answer are yours to decide (`docs/QUESTIONS.md → Release inputs`). Nothing was entered into App Store Connect.

Character limits are Apple's: name 30, subtitle 30, promotional text 170, keywords 100 (including commas), description 4000.

## Name, subtitle, category

| Field | Draft | Notes |
|---|---|---|
| Name | **Chip Counter** | The Home Screen name today. Check it is free in App Store Connect; the name on the page doesn't have to match the one on the icon. Alternatives that include a search word: *Chip Counter: Poker Nights* (26) |
| Subtitle | **Chips, buy-ins & who owes whom** (30) | |
| Primary category | **Utilities** | Not *Games*: the app plays no game and takes no bets, and a Games category invites the gambling questions |
| Secondary category | Lifestyle (optional) | |
| Copyright | © 2026 Van Arp Studios | Whatever name you want shown |
| Support URL | *(yours)* | Required. Also set in `SupportConfig` |
| Privacy policy URL | *(yours)* | Required. A draft to publish is in `docs/legal/privacy-policy.md` |
| Marketing URL | *(optional)* | |

## Promotional text (170 max)

> Running a home poker night? Set the chips, count them with your camera, track rebuys and who owes whom — all from one notebook that never takes a bet.

(158)

## Description

> Chip Counter is a notebook for home poker nights. It keeps the clock, the money in, the chips and the settling-up, so the only thing left to argue about is the cards.
>
> BEFORE THE GAME
> • Tell it the buy-in and how many people are playing. It suggests chip values and how many of each colour everyone starts with, so every stack adds up to the dollar.
> • Own a 100- or 500-piece set? Enter what you have and it works from your chips, shows what it needs against what you own, and offers other ways to deal it if the set is too small.
> • Suggested blinds, and a table card — big chips, values and blinds in landscape — to prop up in the middle of the table or send to the group.
>
> DURING THE GAME
> • A clock that survives closing the app, with breaks that don't count as playing time, and a Break button on the Lock Screen and in the Dynamic Island.
> • One tap for a rebuy, with undo.
> • Add a late player or fix a name in a moment.
>
> WHEN IT'S OVER
> • Count each player's chips by hand, or photograph them — from above, or from the side — and correct anything the camera got wrong. The camera tells you how to hold the phone: flatter, lower, steadier, or where to find more light.
> • A bank check shows whether the chips cashed out match the money that went in, and lets you decide, openly, what to do with a difference.
> • Settle up in a few simple payments, as text or a picture you can share.
>
> AFTERWARDS
> • History of every night, searchable, with the results.
> • Stats on your own results and hours, and a CSV export of everything.
>
> PLAYING HEALTHILY
> • Set your own weekly time limit, an optional loss limit and a reminder during long nights. Take a break from new nights — for a day, three days or a week — and the app holds you to it.
> • Where to turn if it stops being fun: the National Problem Gambling Helpline (1-800-MY-RESET) and similar services elsewhere.
>
> YOUR DATA
> Your nights live on your iPhone and, when you sign in, are backed up to your own account. You can use the app as a guest, with no email at all. Delete a night, or your whole account, from inside the app. There is no advertising, no tracking and no analytics.
>
> Chip Counter is for keeping track of friendly home games. It doesn't handle money, take bets, or offer any kind of gambling.

## Keywords (100 max)

`poker,chips,home game,buy-in,rebuy,cash out,settle up,blinds,ledger,tracker,table card`

(88) — "gambling" and "casino" are left out on purpose: the app is not that, and the words would draw the wrong people and the wrong review.

## What's new in this version (1.0)

> First release.

## Screenshots

Required: the **6.9-inch** iPhone set (1320 × 2868). App Store Connect scales it down for smaller iPhones. The app is iPhone-only, so no iPad set is needed. Eight at most; five or six is enough. The six files are in `docs/appstore/screenshots/` — plain app screens at the exact size with no frames or captions, taken on the iPhone 16 Pro Max simulator with the status bar set to 9:41 and full battery and signal, ready to upload. Suggested captions are in the table so you can add them in your own tool if you want them.

| File | Screen | Suggested caption |
|---|---|---|
| `01-home-night-in-progress.png` | Home with a night in progress | Your home game, in one notebook |
| `02-suggested-chips.png` | Suggested chip values | Chips that add up to the dollar |
| `03-live-night.png` | The night in progress | A clock that keeps time and stops for breaks |
| `04-count-from-a-photo.png` | Counting from a photo (a ring on every chip, and the tally) | Count chips with your camera |
| `05-settle-up.png` | Settle up | Settle up in a few simple payments |
| `06-stats.png` | Stats | See how your nights add up |

**Be aware before you upload them.** They are real screens of the real app, but the data is the test data the UI tests use (three players called Sam, Alex and Jo; a night that lasted seconds). Three of them are thin for that reason: `01` (the "New game" button is dimmed because a night is in progress, and the timer reads 00:04), `04` (the photo is the app's drawn sample picture of 27 discs, not a photograph) and `06` (one night of history, so the charts hold one dot). Retake those three from your own phone after a real night or two, and swap in a photo of your own chips for `04`; the other three are fine as they are. The side-view review and the camera guide are left out on purpose: the first needs a real photo to be believable, and the second is only a drawn picture in the Simulator.

## App Privacy ("nutrition label") — what the app really does

Answer these in App Store Connect → App Privacy. **Declared conservatively**: where it was a judgement call, it is declared. You can narrow it; you cannot under-declare.

**Does this app collect data?** Yes. **Is any of it used to track you?** No. The app has no advertising SDK and no analytics (the Firebase Analytics library is not linked at all), asks no tracking permission, and uses no identifier for advertising.

| Data type (Apple's wording) | Why it's collected | Linked to the person's identity | Used for tracking |
|---|---|---|---|
| **Contact Info → Email Address** — the address they sign in with (not collected from guests or from Sign in with Apple users who hide it) | App functionality (account) | Yes | No |
| **Contact Info → Name** — names typed for the players, which can include the person's own | App functionality | Yes | No |
| **User Content → Photos or Videos** — chip photos sent for counting, kept privately under the account until the night is deleted or 30 days pass | App functionality | Yes | No |
| **User Content → Other User Content** — where and when a night was played and any notes typed | App functionality | Yes | No |
| **Financial Info → Other Financial Info** — what each player put in and took out of a night | App functionality | Yes | No |
| **Identifiers → User ID** — the sign-in account's ID | App functionality | Yes | No |

Not collected: location, contacts, browsing history, search history, health data, purchases, usage data, diagnostics, advertising data. (The service's operational logs hold a *hashed* account ID and event names such as "photo analysed", kept by Google Cloud Logging for its default period. If you read that as "Diagnostics → Other Diagnostic Data", add it.)

The same answers, as the privacy manifest that ships in the app, are in `PokerChipApp/PrivacyInfo.xcprivacy`. The Firebase and Google libraries ship manifests of their own (verified: they are embedded in the built app, one per module).

## Age rating

Apple's current questionnaire asks, among others, about *Simulated Gambling*, *Contests* and *Gambling*. **Answer them yourself**, from Apple's own definitions at the time you submit. What is true of the app, to answer from:

- It doesn't deal cards, spin anything or let anyone wager. It has no simulated casino games.
- It never moves money, takes a payment or connects to a payment service; settle-up produces a text or a picture saying who owes whom.
- It has no contests or prizes.
- Its subject is poker nights between friends. It says so on the first screen of its description, and in Settings: "It doesn't handle money or take bets."
- It points to gambling-help services and lets a person set limits and take a break.

## Review notes (App Review Information)

> **Demo access.** No account is needed. On the first screen tap **Continue as guest**. (Sign-in with an email and, if enabled, Sign in with Apple is also available.)
>
> **What the app is.** A notebook for friendly home poker nights: it suggests chip values for a buy-in, times the night, records buy-ins and rebuys, helps count each player's chips, and works out who owes whom. It is not a gambling app: it deals no cards, takes no bets, and never handles or transfers money. Settle-up is text or a picture.
>
> **Camera.** Used only to photograph a player's chips so the app can count them (Start a night → … → cash out → *Take photo*). It is optional: every count can be entered by hand, and a photo can instead be chosen from the library. Photos are sent over HTTPS to the app's own counting service, kept privately under the account, and deleted with the night or after 30 days.
>
> **To see the main features without a real game:** Play → New game → pick a buy-in and two or more players → Chip values → Start → *End night* → cash out each player (count chips by hand, or *Enter amount*) → Bank check → Settle up. History and Stats then show it.
>
> **Live Activity.** When a night is in progress the clock appears on the Lock Screen and in the Dynamic Island with a Break button.
>
> **Backend.** The counting service and backup run on Google Cloud (Cloud Run, Firestore, Cloud Storage) and Firebase Authentication. They are live for the review.

## TestFlight "What to test"

> Play a real night with it. Start from New game, set the chips, time the night, rebuy someone, cash everyone out, and settle up. Then:
> • Count one player's chips from a photo taken from above, and another from the side, and say how close the camera got.
> • Lock your phone during a night: does the clock show on the Lock Screen? Tap **Break**.
> • Open the table card and turn the phone on its side.
> • Kill the app in the middle of a night and open it again.
> Tell me anything that was confusing, slow or wrong.

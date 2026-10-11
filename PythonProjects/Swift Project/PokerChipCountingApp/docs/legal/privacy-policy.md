# Chip Counter — Privacy Policy

> **DRAFT — not legal advice.** Written from what the app and its backend actually do (every statement here can be checked against the code, `docs/APPSTORE.md` and `ChipVisionService/README.md`). Fill in the bracketed parts, have it read by someone qualified where you live, then publish it at the URL you give App Store Connect. If the app changes what it collects, change this first.

**Effective date:** [date]
**Who we are:** [Name or company], [address or country], contact [support email]

Chip Counter is a notebook for home poker nights. This policy says what the app keeps, where, for how long, and how to remove it.

## The short version

- Your nights are kept **on your iPhone**. If you sign in, they are also **backed up to your own account**.
- You can use the app **as a guest**, without giving an email address.
- There is **no advertising, no tracking and no analytics** in the app.
- We **don't sell** your data or share it for marketing.
- You can **delete a night, or your whole account, inside the app**, whenever you like.

## What we keep

**Your account.** If you sign in with email, we keep your email address. If you sign in with Apple, we keep the identifier Apple gives us and, if you choose to share it, your email address (or Apple's private relay address). A guest has an anonymous identifier and nothing else. Sign-in is handled by Google's Firebase Authentication.

**Your nights.** For each night you record: when it started and ended, the place and any notes you type, the names you give the players (which can include your own), the chip values and colours, what each player put in and took out, any breaks, and how a difference was settled. This is stored on your iPhone. When you are signed in it is also stored in your account on Google Cloud (Firestore) so it can be restored on another device.

**Photos of chips.** If you use photo counting, the photo is sent over an encrypted connection to the counting service, which counts the chips and keeps the photo **privately** under your account. Photos are not made public and are not linked to other people's data. The location and other metadata in the photo are removed before it is stored, and the app sends only how the camera was tilted (never where or when it was taken). A photo is deleted when you delete the night it was taken for, when you delete your account, and automatically after 30 days.

**Settings.** Your limits, preferences and similar choices are stored on your iPhone only.

**Operational logs.** The counting service keeps ordinary server logs (for example "a photo was analysed") that include a scrambled version of your account identifier. They contain no email addresses, no names, no notes and no photos.

## What we don't do

- We don't read your contacts, your location or your photo library (when you choose an existing photo, only that photo is shared with the app, by the system).
- The camera's tips ("hold the phone flatter", "it's dark in here") are worked out on your iPhone from its motion sensors and the live picture while the camera is open. None of that is recorded or sent anywhere; only the tilt of the photo you take is sent with it, as described above.
- We don't use any advertising identifier, and we don't track you across other apps or websites.
- We don't handle money. The app records amounts you type; it doesn't move, take or hold any.
- We don't share your data with anyone else except the services that run the app (Google Cloud and Firebase, which store and process it for us under their terms).

## How long we keep it

- Nights: until you delete them. A deleted night leaves only a small marker (its ID, start time, time zone, currency and when it was deleted) so your other devices learn of the deletion, with no names, place or notes.
- Photos: until you delete the night or your account, or 30 days, whichever comes first. (The 30-day limit is a storage rule the owner switches on when deploying the backend — `docs/RELEASE.md`, step 4. Don't publish this sentence until it is on.)
- Account: until you delete it.

## Your choices

- **Delete a night:** open the night's History entry and delete it. Its backed-up copy and photos are deleted with it.
- **Delete your account:** Settings → Delete account. This removes your nights, photos and sign-in from our systems and from your iPhone. It can't be undone.
- **Take your data with you:** Stats → Export every night as a spreadsheet (CSV).
- **Use the app without an account:** choose *Continue as guest*. Nothing is then backed up.

## Children

Chip Counter is a tool for adults who play poker with friends. It isn't directed at children, and we don't knowingly collect their data.

## Security

Data travels over encrypted connections. Stored photos are private; the app never reads the database or storage directly, only the counting service does, after checking your sign-in. No system is perfectly secure, and we can't promise otherwise.

## Where it's stored

Google Cloud and Firebase, in [the United States / the region you chose]. If you're outside that region your data is transferred there.

## If gambling stops being fun

Chip Counter includes limits and breaks you can set for yourself. If you want to talk to someone: in the US, the National Problem Gambling Helpline, 1-800-MY-RESET (1-800-697-3738), call, text or chat any time (1800myreset.org); the app lists services for other countries.

## Changes

If this policy changes in a way that matters, we'll say so in the app and update the date above.

## Contact

[Support email] — for questions, or to ask us to remove something you can't remove yourself.

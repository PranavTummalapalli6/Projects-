# ChipVisionService

Containerized backend for PokerChipApp. It:

1. Receives the end-of-game chip photo (`POST /v1/sessions/{id}/photo`), verifies the caller's Firebase ID token, strips the photo's metadata, runs best-effort chip detection (OpenCV, see `app/chip_detection.py`), stores the photo **privately** in Firebase Storage, and returns suggested counts + a confidence level.
2. Receives the user's confirmed final counts (`POST /v1/sessions/{id}/complete`), computes profit/loss server-side in whole cents, and writes the session to Firestore. Safe to repeat: the app lets people fix a miscounted chip and resubmit.
3. Reports the last seven days of playtime for the Poker Health screen, bucketed by the player's own time zone.
4. Keeps each person's game **nights** in sync between their devices (`/v1/nights`): last-writer-wins, safe to retry, incremental, with deletions that leave only a marker.
5. Deletes a session, or a whole account and everything stored for it (required for App Store review).

The detection is classic computer vision (Hough circle transform + color matching against the app's 5 known chip colors), **not** a trained model — it will undercount chips hidden inside tall stacks. That's why the app always shows the counts as editable and requires the user to confirm before calculating a result; treat this service's output as a suggestion, not ground truth.

## Endpoints

All `/v1` routes need `Authorization: Bearer <Firebase ID token>`. Guest (anonymous) tokens work like any other.

| Method | Path | Notes |
|---|---|---|
| GET | `/healthz` | The process is up. |
| GET | `/readyz` | 200 only if Firebase initialized *and* credentials resolved; otherwise 503 `firebase-unavailable`. |
| POST | `/v1/sessions/{id}/photo` | multipart: `image` (file), `denominations` (JSON string); optional `view` (`top`, the default, or `side`), and for `side` the camera's `pitch`, `roll` (degrees) and `focal35` (35 mm-equivalent focal length) plus `colors` (the chip colours in play, comma separated). Returns `counts`, `confidence`, `photoUrl`, `view`, and either `detections` — one `{x, y, r, color}` per counted chip, with centre and radius as fractions of the photo's **width** (so a circle can be drawn at any size) — or, for `side`, `stacks` — one `{x, y, w, h, angle, color, count, confidence}` per pile. 400 for a `view` that isn't one of those; 422 for a pose a phone could not report. 413 if over `MAX_UPLOAD_BYTES` (10 MB) or `MAX_IMAGE_PIXELS` (50 MP); 429 past `PHOTO_RATE_LIMIT_PER_HOUR` (60) per user. |
| POST | `/v1/sessions/{id}/complete` | JSON: `buyIn`, `denominations`, `finalCounts`, `elapsedSeconds` (**this segment only**, never the running total), optional `startedAt`, `tzIdentifier`, `sessionGroupId`. Returns `profitLoss`, `profitLossCents`, `photoUrl`. |
| GET | `/v1/sessions/weekly-summary?tz=<IANA zone>` | Last 7 local days; `totalSeconds` is always the sum of the daily bars. |
| GET | `/v1/sessions/{id}/photo-url` | A fresh signed link (1 hour) for the caller's own stored photo; 404 if none. |
| DELETE | `/v1/sessions/{id}` | Removes the record and its photo. |
| PUT | `/v1/nights/{id}` | One night as JSON (the app's own file format; see `app/nights.py`). Returns `{night, applied, serverUpdatedAt}`. Idempotent; **last-writer-wins by the night's `updatedAt`** — if the server already holds a later edit it answers `applied: false` with that edit. 413 over 128 KB, 422 with a short reason (never the input), 429 past `NIGHT_WRITE_RATE_LIMIT_PER_HOUR` (600). |
| GET | `/v1/nights?since=<cursor>&limit=<1–200>` | Nights **and deletion markers** changed after the cursor, oldest change first: `{nights, cursor, hasMore}`. Start without `since`; pass the returned `cursor` back to continue. |
| DELETE | `/v1/nights/{id}` | Turns a night into a marker (id, start time, zone, currency and two timestamps — no names, place or notes) and deletes the night's stored photos. 404 if unknown; repeating is harmless. |
| POST | `/v1/nights/import-legacy` | Turns the account's old single-player sessions into one-player nights. Idempotent (ids are derived from the old session id); never overwrites an edited night. |
| DELETE | `/v1/account` | Removes every session, every night, every photo, and the Firebase Auth user. Safe to retry. |

Session ids may only contain letters, digits, `_` and `-` (max 64), so an id can never reach outside the caller's own folder. Night ids must be UUIDs.

### How nights sync

Nights are stored at `sessions/{uid}/nights/{id}` with a server-assigned `serverUpdatedAt` (UTC, microseconds, fixed width) that `since` is ordered by — a single-field index Firestore creates by itself, so **no new index is needed**. Writes run in a transaction, so two devices writing at once cannot overwrite each other's newer edit. A tie on `updatedAt` with different content keeps the first writer's version and hands it to the second device, so everyone converges. The server refuses fields it doesn't know (`422`) rather than dropping them silently, which means a newer app talking to an older server keeps its night safe on the phone instead of losing data. Clients should re-read a few seconds *before* their cursor (the app uses 10 s) to be safe against clock skew between instances.

## Privacy and security

- **Photos are private.** Nothing is made public; the app gets short-lived signed URLs. `firestore.rules` and `storage.rules` (repo root) deny every direct client request — the app never talks to Firestore or Storage, only to this service, which uses the Admin SDK (that bypasses the rules).
- **No location data is kept.** Uploads are decoded and re-encoded from pixels, which drops EXIF/GPS/XMP; a test checks it.
- **Retention.** `storage-lifecycle.json` deletes stored photos after 30 days. It is not active until the owner applies it (see below). A per-user retention setting is not built yet.
- **Logs** are JSON, carry a hashed user id, and never include emails, tokens or photo contents.
- **Rate limit** is per user and held in memory, so it is per instance (fine at min-instances 0–1; move it to a shared store if you scale out).

## Detection accuracy — read this before trusting the numbers

`app/chip_detection.py` uses a Hough circle transform + color matching against
the app's 5 known chip colors, plus a second, more permissive detection pass
used only to rescue low-contrast (typically black) chips the first pass
missed — a candidate from that pass is kept only if it doesn't overlap
something already found *and* it actually color-matches as black, so it can't
introduce false positives for the other four colors.

On a clean synthetic test with no occlusion (`tests/test_chip_detection.py`),
it correctly detects and colors all chips, including black ones — an earlier
version of this doc claimed black chips were the weak point, but that turned
out to be a bug in the *test's* synthetic image generator (a chip was being
drawn partially off-canvas, so of course it wasn't "detected" — it was never
fully in the picture). That's fixed now; see the test for the corrected
generator.

None of this is a promise about real photos, though. Real chip stacks have
occlusion, uneven lighting, and actual shadows that a synthetic test can't
model, and low-contrast/dark chips are still the more plausible failure mode
there — a real shadow can genuinely blend into a black chip's edge in a way
this test simply doesn't produce. That's exactly why the app always shows the
counts as editable and requires the user to confirm before calculating a
result — treat every response from this service as a suggestion, not ground
truth.

## Side-view counting — what is and is not known

`app/side_view.py` reads photos taken from the side or at a low angle, where the
circle counter finds nothing. It uses the camera's pose (sent by the app from the
phone's own sensors) to know how each chip is foreshortened, finds each pile by
colour and by the bright tabs printed round a chip's rim, and counts: small piles
from the rings of tabs showing on them, tall stacks from their height measured in
chip thicknesses (a 3.3 mm chip, 39 mm across).

A pile is named for the colour of its chips' bodies and never for their tabs: a
white chip with blue tabs is White (the owner's set), even in a night that uses no
white chips — the app leaves a colour the night doesn't use out of the counts and
says so. The `colors` form field is still accepted but changes no name.

Measured on seven photos of one chip set (piles of one or two chips, shot at
16–24° above the table, kept out of git in `PokerChipApp/test_photos/side_view`;
the test skips when they are absent): 26 of 28 piles found with the right
colour, 18 of 28 counted right. Piles of one chip were right every time; a pair
about half the time. Tall stacks have only been tested on drawn scenes that
follow the counter's own geometry, which proves the code path and nothing about
real stacks. No count it returns is ever "high" confidence, and the app shows it
as a suggestion each pile of which can be corrected. If you have photos of real
upright stacks with known counts, add them to that folder with their counts and
the test will measure them.

## Tests

No network, credentials or Docker needed — Firestore and Storage are replaced by in-memory fakes (`tests/fakes.py`).

```bash
cd ChipVisionService
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt     # test-only extras (pytest, httpx) are not in the production image
python -m pytest -q
```

If `pip` starts compiling OpenCV from source on an Intel Mac (it will take a very long time), your Python is reporting macOS as "10.16"; run `SYSTEM_VERSION_COMPAT=0 pip install --only-binary=:all: -r requirements-dev.txt` instead.

## Local development

1. **Get a service-account key** (one-time, needs your Firebase console access):
   Firebase Console → project `pokerchipapp-f7a84` → Project Settings → Service Accounts → *Generate new private key*.
   Save the downloaded file as `ChipVisionService/secrets/firebase-service-account.json` (the `secrets/` folder is gitignored — never commit this file).

1b. **Enable Storage and Firestore** — as of this setup, neither was actually turned on for this project yet (confirmed by running `verify_firebase.py` below against the real key: the Storage bucket didn't exist, and the Firestore API was disabled). Both are one-time console steps:
   - **Storage:** Firebase Console → Build → Storage → *Get started* → this provisions the default bucket (`pokerchipapp-f7a84.firebasestorage.app`, already what the code expects).
   - **Firestore:** Firebase Console → Build → Firestore Database → *Create database* (Native mode, any region — pick one close to your users). Alternatively enable the API directly: https://console.developers.google.com/apis/api/firestore.googleapis.com/overview?project=pokerchipapp-f7a84

   Verify both are working:
   ```bash
   docker build -t chip-vision-service:test .
   docker run --rm \
     -v "$(pwd)/verify_firebase.py:/app/verify_firebase.py" \
     -v "$(pwd)/secrets/firebase-service-account.json:/secrets/firebase-service-account.json:ro" \
     -e GOOGLE_APPLICATION_CREDENTIALS=/secrets/firebase-service-account.json \
     chip-vision-service:test python /app/verify_firebase.py
   ```
   Should print `OK` for both Storage and Firestore before moving on.

2. **Build and run:**
   ```bash
   cd ChipVisionService
   docker compose up --build
   ```
   The container runs as an unprivileged user (uid 10001), so the key file must be readable by it — a normal `0600`/`0644` file mounted by Docker Desktop on a Mac is.

3. **Verify it's alive:**
   ```bash
   curl http://localhost:8000/healthz   # {"status":"ok"}
   curl http://localhost:8000/readyz    # {"status":"ready"} once the key loads
   ```
   With no credentials at all, startup takes about 8 seconds (Google's auth library probes for a cloud metadata server first), then `/readyz` answers 503.

4. **Test detection against a real photo** (replace `chips.jpg` with a real photo, and `$ID_TOKEN` with a Firebase ID token — easiest way to get one during dev is to print `try await Auth.auth().currentUser?.getIDToken()` from the running app after signing in):
   ```bash
   curl -X POST http://localhost:8000/v1/sessions/test-session/photo \
     -H "Authorization: Bearer $ID_TOKEN" \
     -F "image=@chips.jpg" \
     -F 'denominations={"White":0.25,"Red":1,"Blue":2,"Green":5,"Black":10}'
   ```

### Pointing the iOS app at a backend

The app reads its backend URL from the `API_BASE_URL` build setting (Info.plist key `APIBaseURL`):

- **Debug** defaults to `http://192.168.1.177:8000` — your Mac's LAN address, so a phone on the same Wi-Fi can reach the container. Change it in *Build Settings → API_BASE_URL* (Debug) if your Mac's IP changes; the iOS Simulator can use `http://localhost:8000`.
- **Release** must be an `https://` URL. Until the Cloud Run URL replaces the `REPLACE_WITH_CLOUD_RUN_URL` placeholder, an App Store archive deliberately fails the "Check Release configuration" build phase.

## Deploying (owner-only — nothing here has been run)

These steps change your Google Cloud and Firebase projects and need billing, so they were written but **not executed**. They need the `gcloud` and `firebase` CLIs logged in to `pokerchipapp-f7a84` (your login, not something an assistant can do).

At this app's scale (a few dozen friends, occasional games) it should fit comfortably in Cloud Run's free tier — a game is two requests — but Cloud Run still requires a billing account with a card on file.

```bash
PROJECT=pokerchipapp-f7a84
REGION=us-central1
SA=chip-vision-runner@$PROJECT.iam.gserviceaccount.com

# APIs
gcloud services enable run.googleapis.com artifactregistry.googleapis.com \
  cloudbuild.googleapis.com iamcredentials.googleapis.com --project $PROJECT

# A dedicated identity for the running container, with only what it needs
gcloud iam service-accounts create chip-vision-runner --project $PROJECT \
  --display-name "ChipVisionService Cloud Run identity"
for ROLE in roles/storage.objectAdmin roles/datastore.user roles/firebaseauth.admin; do
  gcloud projects add-iam-policy-binding $PROJECT --member "serviceAccount:$SA" --role $ROLE
done
# Lets the container sign photo links without a key file
gcloud iam service-accounts add-iam-policy-binding $SA --project $PROJECT \
  --member "serviceAccount:$SA" --role roles/iam.serviceAccountTokenCreator

# Build and deploy
gcloud artifacts repositories create chip-vision --repository-format=docker \
  --location=$REGION --project $PROJECT
IMAGE=$REGION-docker.pkg.dev/$PROJECT/chip-vision/chip-vision-service
gcloud builds submit --tag $IMAGE --project $PROJECT ChipVisionService

# --allow-unauthenticated is correct here: the service does its own auth with
# Firebase ID tokens (see _bearer_uid in app/main.py); Cloud Run's IAM layer
# would otherwise demand a second, separate scheme on top.
gcloud run deploy chip-vision-service --image $IMAGE --project $PROJECT --region $REGION \
  --service-account $SA --allow-unauthenticated \
  --memory 1Gi --timeout 60 --min-instances 0 --max-instances 3
```

Cloud Run prints the service URL — set it as the Release value of the `API_BASE_URL` build setting. No key file is needed there: the attached service account supplies Application Default Credentials (`init_firebase()` falls back to them when `GOOGLE_APPLICATION_CREDENTIALS` is unset). `min-instances 0` means the first request after a quiet spell cold-starts the container (a few seconds); the app treats a slow first call as normal and falls back to counting by hand.

Then lock down direct client access and set photo retention:

```bash
# Deny every direct Firestore/Storage client request (repo root files)
firebase deploy --only firestore:rules,firestore:indexes,storage --project pokerchipapp-f7a84

# Delete stored photos after 30 days
gcloud storage buckets update gs://pokerchipapp-f7a84.firebasestorage.app \
  --lifecycle-file=ChipVisionService/storage-lifecycle.json
```

Finally, in the Firebase console enable **Authentication → Sign-in method → Anonymous** (guest mode needs it) and, if you ship Sign in with Apple, the Apple provider.

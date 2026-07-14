# ChipVisionService

Containerized backend for PokerChipApp's end-of-game photo. It:

1. Receives the chip photo (`POST /v1/sessions/{id}/photo`), verifies the caller's Firebase ID token, runs best-effort chip detection (OpenCV, see `app/chip_detection.py`), uploads the photo to Firebase Storage, and returns suggested counts + a confidence level.
2. Receives the user's confirmed final counts (`POST /v1/sessions/{id}/complete`), computes profit/loss server-side, and writes the session to Firestore.

The detection is classic computer vision (Hough circle transform + color matching against the app's 5 known chip colors), **not** a trained model — it will undercount chips hidden inside tall stacks. That's why the app always shows the counts as editable and requires the user to confirm before calculating a result; treat this service's output as a suggestion, not ground truth.

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

Run the smoke test after changing detection parameters:
```bash
docker build -t chip-vision-service:test .
docker run --rm -v "$(pwd)/tests:/app/tests" chip-vision-service:test python -m tests.test_chip_detection
```

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

3. **Verify it's alive:**
   ```bash
   curl http://localhost:8000/healthz
   # {"status":"ok"}
   ```

4. **Test detection against a real photo** (replace `chips.jpg` with a real photo, and `$ID_TOKEN` with a Firebase ID token — easiest way to get one during dev is to print `try await Auth.auth().currentUser?.getIDToken()` from the running app after signing in):
   ```bash
   curl -X POST http://localhost:8000/v1/sessions/test-session/photo \
     -H "Authorization: Bearer $ID_TOKEN" \
     -F "image=@chips.jpg" \
     -F 'denominations={"White":0.25,"Red":1,"Blue":2,"Green":5,"Black":10}'
   ```

### Pointing the iOS app at this container

- **iOS Simulator** can reach the container at `http://localhost:8000` — this is already the Debug-build default in `PokerChipApp/Views/Networking/APIConfig.swift`.
- **A physical device** on the same Wi-Fi network needs your Mac's LAN IP instead (e.g. `http://192.168.1.23:8000`) — update `APIConfig.swift`'s Debug branch.

## Deploying (Cloud Run)

At the scale this app is actually used at (a couple dozen friends, occasional games), this comfortably fits inside Cloud Run's free tier — 2 million requests/month free, and a single poker session is only 2 requests. It should cost $0/month. The only friction is that Cloud Run requires a GCP billing account with a card on file for identity verification, even though you won't be charged at this volume.

This project is already on Firebase/GCP, so Cloud Run runs this exact container image with no separate hosting account needed. Requires the `gcloud` CLI logged into the `pokerchipapp-f7a84` project (your login, not something I can do from here):

```bash
# One-time: create a dedicated service account for the running container,
# scoped to only what it needs (not your personal/admin credentials).
gcloud iam service-accounts create chip-vision-runner \
  --project pokerchipapp-f7a84 \
  --display-name "ChipVisionService Cloud Run identity"

gcloud projects add-iam-policy-binding pokerchipapp-f7a84 \
  --member "serviceAccount:chip-vision-runner@pokerchipapp-f7a84.iam.gserviceaccount.com" \
  --role "roles/storage.objectAdmin"

gcloud projects add-iam-policy-binding pokerchipapp-f7a84 \
  --member "serviceAccount:chip-vision-runner@pokerchipapp-f7a84.iam.gserviceaccount.com" \
  --role "roles/datastore.user"

cd ChipVisionService

# Build and push the image to Artifact Registry
gcloud builds submit --tag gcr.io/pokerchipapp-f7a84/chip-vision-service

# Deploy — --allow-unauthenticated is correct here because the service does its
# own auth via Firebase ID tokens (see _bearer_uid in app/main.py); Cloud Run's
# IAM layer would otherwise require a *second*, separate auth scheme on top
gcloud run deploy chip-vision-service \
  --image gcr.io/pokerchipapp-f7a84/chip-vision-service \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --service-account chip-vision-runner@pokerchipapp-f7a84.iam.gserviceaccount.com

# Cloud Run prints the deployed URL — put it in APIConfig.swift's Release branch.
```

No service-account JSON file needed on Cloud Run itself: the attached service account gives `app/firebase.py` Application Default Credentials automatically (that's why `init_firebase()` falls back to no-credentials-path — see `app/firebase.py`). The JSON key file is only for local development.

## Endpoints

| Method | Path | Auth | Body |
|---|---|---|---|
| GET | `/healthz` | none | — |
| POST | `/v1/sessions/{id}/photo` | Bearer Firebase ID token | multipart: `image` (file), `denominations` (JSON string) |
| POST | `/v1/sessions/{id}/complete` | Bearer Firebase ID token | JSON: `buyIn`, `denominations`, `finalCounts`, `elapsedSeconds` |

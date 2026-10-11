"""
Standalone diagnostic — checks that the service-account key actually has
working access to Storage and Firestore, independent of the running app.
Run this after setting up secrets/firebase-service-account.json and again
any time Firebase access seems broken.

    docker build -t chip-vision-service:test .
    docker run --rm \
      -v "$(pwd)/verify_firebase.py:/app/verify_firebase.py" \
      -v "$(pwd)/secrets/firebase-service-account.json:/secrets/firebase-service-account.json:ro" \
      -e GOOGLE_APPLICATION_CREDENTIALS=/secrets/firebase-service-account.json \
      chip-vision-service:test python /app/verify_firebase.py
"""

from app.firebase import init_firebase, save_session
from firebase_admin import storage as fb_storage

init_firebase()
print("init_firebase() OK")

print("\n--- Storage ---")
try:
    bucket = fb_storage.bucket()
    print("bucket name configured as:", bucket.name)
    if bucket.exists():
        print("OK — bucket exists and is reachable")
    else:
        print(
            "FAIL — bucket does not exist. In the Firebase console: "
            "Build > Storage > Get Started, to provision the default bucket."
        )
except Exception as e:
    print("FAIL —", repr(e))

print("\n--- Firestore ---")
try:
    save_session("diagnostic-uid", "diagnostic-session", {
        "buyIn": 50.0,
        "denominations": {"White": 0.25, "Red": 1},
        "finalCounts": {"White": 10, "Red": 5},
        "elapsedSeconds": 120,
        "endingValue": 7.5,
        "profitLoss": -42.5,
        "photoUrl": "",
    })
    print("OK — wrote a diagnostic document to sessions/diagnostic-uid/games/diagnostic-session")
except Exception as e:
    print("FAIL —", repr(e))

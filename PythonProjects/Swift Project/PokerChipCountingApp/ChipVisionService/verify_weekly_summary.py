"""
Standalone diagnostic for get_weekly_summary — writes a few known session
documents (some inside the 7-day window, one outside it) for a throwaway uid,
then checks the aggregation comes back correct. Run the same way as
verify_firebase.py:

    docker build -t chip-vision-service:test .
    docker run --rm \
      -v "$(pwd)/verify_weekly_summary.py:/app/verify_weekly_summary.py" \
      -v "$(pwd)/secrets/firebase-service-account.json:/secrets/firebase-service-account.json:ro" \
      -e GOOGLE_APPLICATION_CREDENTIALS=/secrets/firebase-service-account.json \
      chip-vision-service:test python /app/verify_weekly_summary.py
"""

from datetime import datetime, timedelta, timezone

from firebase_admin import firestore

from app.firebase import get_weekly_summary, init_firebase

init_firebase()
print("init_firebase() OK")

uid = "diagnostic-weekly-uid"
db = firestore.client()
games_ref = db.collection("sessions").document(uid).collection("games")

now = datetime.now(timezone.utc)
fixtures = {
    "today": (now, 3600),
    "three-days-ago": (now - timedelta(days=3), 1800),
    "six-days-ago": (now - timedelta(days=6), 900),
    "eight-days-ago-excluded": (now - timedelta(days=8), 5000),
}

for doc_id, (created_at, elapsed) in fixtures.items():
    games_ref.document(doc_id).set({
        "buyIn": 50.0,
        "denominations": {"White": 0.25},
        "finalCounts": {"White": 10},
        "elapsedSeconds": elapsed,
        "endingValue": 2.5,
        "profitLoss": -47.5,
        "photoUrl": "",
        "createdAt": created_at.isoformat(),
    })
print(f"Wrote {len(fixtures)} fixture docs under sessions/{uid}/games")

summary = get_weekly_summary(uid)
print("\nget_weekly_summary result:")
print(summary)

expected_total = 3600 + 1800 + 900
actual_total = summary["totalSeconds"]
print(f"\nExpected totalSeconds={expected_total}, got={actual_total}: "
      f"{'PASS' if actual_total == expected_total else 'FAIL'}")
print(f"days bucket count={len(summary['days'])}: "
      f"{'PASS' if len(summary['days']) == 7 else 'FAIL'}")

for doc_id in fixtures:
    games_ref.document(doc_id).delete()
print("\nCleaned up fixture docs")

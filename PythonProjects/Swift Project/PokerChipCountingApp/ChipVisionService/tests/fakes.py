"""
In-memory stand-ins for the slice of Firestore / Cloud Storage the service
uses, so the real functions in app/firebase.py (and the endpoints on top of
them) can be exercised without a network or an emulator.

Deliberately strict: FakeBlob has no `make_public` or `public_url`, so any code
path that tries to expose a photo publicly fails loudly instead of passing.
"""

from typing import Dict, Iterator, List, Optional

from google.api_core.exceptions import AlreadyExists


class FakeSnapshot:
    def __init__(self, data: Optional[Dict], doc_id: str = ""):
        self._data = data
        self.id = doc_id

    @property
    def exists(self) -> bool:
        return self._data is not None

    def to_dict(self) -> Optional[Dict]:
        return dict(self._data) if self._data is not None else None


class FakeDocRef:
    def __init__(self, db: "FakeFirestore", path: str):
        self._db = db
        self.path = path

    def get(self, transaction=None) -> FakeSnapshot:
        return FakeSnapshot(self._db.docs.get(self.path), self.path.rsplit("/", 1)[-1])

    def set(self, data: Dict, merge: bool = False) -> None:
        if merge and self.path in self._db.docs:
            self._db.docs[self.path] = {**self._db.docs[self.path], **data}
        else:
            self._db.docs[self.path] = dict(data)

    def create(self, data: Dict) -> None:
        if self.path in self._db.docs:
            raise AlreadyExists(f"{self.path} already exists")
        self._db.docs[self.path] = dict(data)

    def delete(self) -> None:
        self._db.docs.pop(self.path, None)

    def collection(self, name: str) -> "FakeCollectionRef":
        return FakeCollectionRef(self._db, f"{self.path}/{name}")


_OPERATORS = {
    ">": lambda a, b: a > b,
    ">=": lambda a, b: a >= b,
    "<": lambda a, b: a < b,
    "<=": lambda a, b: a <= b,
    "==": lambda a, b: a == b,
}


class FakeQuery:
    """where / order_by / limit, evaluated the way Firestore does: a document
    without the filtered or ordered field is left out."""

    def __init__(self, collection: "FakeCollectionRef", filters=(), order_field=None, max_results=None):
        self._collection = collection
        self._filters = tuple(filters)
        self._order_field = order_field
        self._max_results = max_results

    def where(self, filter=None) -> "FakeQuery":  # noqa: A002 — mirrors the real kwarg
        return FakeQuery(self._collection, self._filters + (filter,), self._order_field, self._max_results)

    def order_by(self, field_path: str) -> "FakeQuery":
        return FakeQuery(self._collection, self._filters, field_path, self._max_results)

    def limit(self, count: int) -> "FakeQuery":
        return FakeQuery(self._collection, self._filters, self._order_field, count)

    def stream(self) -> Iterator[FakeSnapshot]:
        rows = []
        for snapshot in self._collection.stream():
            data = snapshot.to_dict()
            keep = True
            for field_filter in self._filters:
                value = data.get(field_filter.field_path)
                if value is None or not _OPERATORS[field_filter.op_string](value, field_filter.value):
                    keep = False
                    break
            if keep and self._order_field is not None and data.get(self._order_field) is None:
                keep = False
            if keep:
                rows.append(snapshot)
        if self._order_field is not None:
            rows.sort(key=lambda snapshot: snapshot.to_dict()[self._order_field])
        if self._max_results is not None:
            rows = rows[: self._max_results]
        yield from rows


class FakeCollectionRef:
    def __init__(self, db: "FakeFirestore", path: str):
        self._db = db
        self.path = path

    def document(self, doc_id: str) -> FakeDocRef:
        return FakeDocRef(self._db, f"{self.path}/{doc_id}")

    def where(self, filter=None) -> FakeQuery:  # noqa: A002 — mirrors the real kwarg
        return FakeQuery(self).where(filter=filter)

    def order_by(self, field_path: str) -> FakeQuery:
        return FakeQuery(self).order_by(field_path)

    def stream(self) -> Iterator[FakeSnapshot]:
        prefix = f"{self.path}/"
        for path, data in list(self._db.docs.items()):
            if path.startswith(prefix) and "/" not in path[len(prefix):]:
                yield FakeSnapshot(data, path.rsplit("/", 1)[-1])


class FakeTransaction:
    """Writes go straight through; the tests exercise the logic inside the
    transaction, not Firestore's retry machinery."""

    def set(self, ref: FakeDocRef, data: Dict, merge: bool = False) -> None:
        ref.set(data, merge=merge)


class FakeFirestore:
    def __init__(self):
        self.docs: Dict[str, Dict] = {}

    def collection(self, name: str) -> FakeCollectionRef:
        return FakeCollectionRef(self, name)

    def transaction(self) -> FakeTransaction:
        return FakeTransaction()

    def recursive_delete(self, ref: FakeDocRef) -> None:
        prefix = f"{ref.path}/"
        for path in [p for p in self.docs if p == ref.path or p.startswith(prefix)]:
            del self.docs[path]


class FakeBlob:
    def __init__(self, bucket: "FakeBucket", name: str):
        self._bucket = bucket
        self.name = name

    def upload_from_string(self, data: bytes, content_type: Optional[str] = None) -> None:
        self._bucket.objects[self.name] = (data, content_type)

    def exists(self) -> bool:
        return self.name in self._bucket.objects

    def delete(self) -> None:
        del self._bucket.objects[self.name]

    def generate_signed_url(self, **kwargs) -> str:
        ttl = int(kwargs["expiration"].total_seconds())
        return f"https://signed.example/{self.name}?ttl={ttl}&method={kwargs['method']}"


class FakeBucket:
    def __init__(self):
        self.objects: Dict[str, tuple] = {}

    def blob(self, name: str) -> FakeBlob:
        return FakeBlob(self, name)

    def list_blobs(self, prefix: str = "") -> List[FakeBlob]:
        return [FakeBlob(self, name) for name in list(self.objects) if name.startswith(prefix)]

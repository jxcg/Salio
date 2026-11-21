from datetime import UTC, datetime, timedelta

from fastapi import FastAPI
from pydantic import AwareDatetime, BaseModel

app = FastAPI(title="Salio")
MIN_STAY = timedelta(minutes=60)
DEMO_TIME = datetime(2030, 1, 1, 18, 0, tzinfo=UTC)


class Place(BaseModel):
    id: str
    name: str
    category: str
    walk_minutes: int
    closes_at: datetime


class BoardEntry(Place):
    leave_by: datetime


SAMPLE_PLACES = (
    ("gallery", "North Street Gallery", "Art", 14, 154),
    ("cinema", "The Picture House", "Cinema", 8, 79),
    ("cafe", "Courtyard Coffee", "Café", 5, 59),
)


@app.get("/v1/sample-board", response_model=list[BoardEntry])
def sample_board(at: AwareDatetime | None = None) -> list[BoardEntry]:
    now = at if at is not None else DEMO_TIME
    places = [
        Place(
            id=id_,
            name=name,
            category=category,
            walk_minutes=walk,
            closes_at=DEMO_TIME + timedelta(minutes=close),
        )
        for id_, name, category, walk, close in SAMPLE_PLACES
    ]
    entries = []
    for place in places:
        leave_by = place.closes_at - MIN_STAY - timedelta(minutes=place.walk_minutes)
        if leave_by >= now:
            entries.append(BoardEntry(**place.model_dump(), leave_by=leave_by))
    return sorted(entries, key=lambda entry: entry.leave_by)

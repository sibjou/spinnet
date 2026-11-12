# -*- coding: utf-8 -*-
"""Генератор тестовых данных Spinnet.

Чистая логика без Firebase: на выходе список документов `Doc(path, data)`.
Запись в базу делает seed.py. Здесь же правила счёта настольного тенниса (порт MatchScoring.swift),
чтобы каждый сгенерированный матч был таким, каким его принимает приложение.

Всё придумано: люди, результаты, отзывы, организаторы. Настоящими остаются только площадки (data/venues.json).
"""
from __future__ import annotations

import json
import math
import random
from collections import Counter
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import texts

UTC = timezone.utc
DATA_DIR = Path(__file__).resolve().parent / "data"

CITY_WEIGHTS = [
    ("Томск", 24), ("Новосибирск", 18), ("Москва", 18),
    ("Санкт-Петербург", 16), ("Кемерово", 12), ("Мурманск", 12),
]
LEVELS = ["Начинающий", "Любитель", "Продвинутый", "Профессионал"]
LEVEL_WEIGHTS = [20, 40, 30, 10]
LEVEL_STRENGTH = {  # (среднее, разброс) условной силы игрока
    "Начинающий": (700, 120), "Любитель": (1000, 130),
    "Продвинутый": (1350, 150), "Профессионал": (1750, 160),
}
GRIPS = ["Шейкхолд", "Пенхолд"]
STYLES = ["Нападающий", "Комбинированный", "Защитник"]
MONTHS_GEN = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа",
              "сентября", "октября", "ноября", "декабря"]
SEASONS = {12: "Зимний", 1: "Зимний", 2: "Зимний", 3: "Весенний", 4: "Весенний", 5: "Весенний",
           6: "Летний", 7: "Летний", 8: "Летний", 9: "Осенний", 10: "Осенний", 11: "Осенний"}
SEED_ID_PREFIX = "seed"


# ---------------------------------------------------------------- модели

@dataclass
class Doc:
    path: str                      # "collection/id" или "collection/id/sub/id"
    data: Dict[str, Any]

    @property
    def collection(self) -> str:
        return self.path.split("/")[0]


@dataclass
class Me:
    """Настоящий аккаунт владельца: на него навешиваются игры, отзывы и уведомления."""
    uid: str
    first: str
    last: str
    city: str = "Томск"
    skill: str = "Любитель"
    grip: str = "Шейкхолд"
    style: str = "Нападающий"


@dataclass
class Config:
    now: datetime                  # момент запуска, UTC
    tz_hours: int = 7              # часовой пояс телефона, на котором снимаются скриншоты (Томск = +7)
    scale: float = 1.0
    seed: int = 2026
    me: Optional[Me] = None
    email_domain: str = "spinnet.test"     # зарезервированный домен: письма на него никуда не доходят


@dataclass
class Person:
    uid: str
    first: str
    last: str
    city: str
    skill: str
    grip: str
    style: str
    strength: float
    ttw: int
    created: datetime
    weight: float                  # насколько часто создаёт заявки
    kindness: float                # сдвиг оценок, которые получает человек
    email: str = ""
    privacy: Dict[str, bool] = field(default_factory=dict)
    last_seen: Optional[datetime] = None
    is_me: bool = False

    @property
    def full(self) -> str:
        return "{} {}".format(self.first, self.last).strip()


@dataclass
class Slot:
    day: date                      # местный календарный день
    start: int                     # минут от полуночи
    end: int

    @property
    def text(self) -> str:
        return "{:02d}:{:02d} – {:02d}:{:02d}".format(self.start // 60, self.start % 60,
                                                          self.end // 60, self.end % 60)

    @property
    def minutes(self) -> int:
        return self.end - self.start


@dataclass
class World:
    cfg: Config
    people: List[Person]
    docs: List[Doc]

    def by_collection(self, name: str) -> List[Doc]:
        return [d for d in self.docs if d.collection == name]


# ---------------------------------------------------------------- время

def local_to_utc(cfg: Config, local_dt: datetime) -> datetime:
    return (local_dt - timedelta(hours=cfg.tz_hours)).replace(tzinfo=UTC)


def now_local(cfg: Config) -> datetime:
    return (cfg.now + timedelta(hours=cfg.tz_hours)).replace(tzinfo=None)


def day_stamp(day: date) -> datetime:
    """Значение поля `date` заявки и турнира.

    07:00 UTC — на любом часовом поясе России это тот же календарный день,
    поэтому игра не «съезжает» на соседнюю дату.
    """
    return datetime(day.year, day.month, day.day, 7, 0, tzinfo=UTC)


def slot_start_local(slot: Slot) -> datetime:
    return datetime(slot.day.year, slot.day.month, slot.day.day) + timedelta(minutes=slot.start)


def slot_end_local(slot: Slot) -> datetime:
    return datetime(slot.day.year, slot.day.month, slot.day.day) + timedelta(minutes=slot.end)


def russian_when(slot: Slot) -> str:
    return "{} {}, {}".format(slot.day.day, MONTHS_GEN[slot.day.month - 1], slot.text)


# ---------------------------------------------------------------- счёт (порт MatchScoring.swift)

def game_error(a: int, b: int) -> Optional[str]:
    if a < 0 or b < 0:
        return "negative"
    if a == b:
        return "tie"
    high, low = max(a, b), min(a, b)
    if high > 40:
        return "too_big"
    if high < 11:
        return "short"
    if high == 11:
        return None if low <= 9 else "deuce"
    return None if high - low == 2 else "bad_deuce"


def validate_match(games: List[Tuple[int, int]], best_of: int) -> Optional[Tuple[int, int]]:
    """(партий у A, партий у B), если счёт возможен и матч закончен; иначе None."""
    need = best_of // 2 + 1
    won_a = won_b = 0
    for a, b in games:
        if won_a == need or won_b == need:
            return None
        if game_error(a, b) is not None:
            return None
        if a > b:
            won_a += 1
        else:
            won_b += 1
    return (won_a, won_b) if need in (won_a, won_b) else None


def simulate_game(rng: random.Random, q: float) -> Tuple[int, int]:
    """Одна партия по очкам; q — вероятность очка у игрока A."""
    while True:
        a = b = 0
        while True:
            if rng.random() < q:
                a += 1
            else:
                b += 1
            if (a >= 11 or b >= 11) and abs(a - b) >= 2:
                break
            if a + b > 70:
                break
        if game_error(a, b) is None:
            return a, b


def simulate_match(rng: random.Random, strength_a: float, strength_b: float,
                   best_of: int, force_winner: Optional[str] = None) -> List[Tuple[int, int]]:
    need = best_of // 2 + 1
    for _ in range(200):
        q = 0.5 + 0.2 * math.tanh((strength_a - strength_b) / 450.0)
        games: List[Tuple[int, int]] = []
        wa = wb = 0
        while wa < need and wb < need:
            a, b = simulate_game(rng, q)
            games.append((a, b))
            if a > b:
                wa += 1
            else:
                wb += 1
        winner = "a" if wa > wb else "b"
        if force_winner is None or force_winner == winner:
            return games
    return games


def encode_games(games: List[Tuple[int, int]]) -> List[Dict[str, int]]:
    return [{"a": a, "b": b} for a, b in games]


# ---------------------------------------------------------------- справочники

def load_venues() -> Dict[str, List[Dict[str, str]]]:
    raw = json.loads((DATA_DIR / "venues.json").read_text(encoding="utf-8"))
    by_city: Dict[str, List[Dict[str, str]]] = {}
    for venue in raw["venues"]:
        by_city.setdefault(venue["city"], []).append(venue)
    return by_city


def venue_label(venue: Dict[str, str]) -> str:
    text = venue["name"]
    if venue.get("address"):
        text += ", " + venue["address"]
    if venue.get("metro"):
        text += " (м. {})".format(venue["metro"])
    return text


def weighted_choice(rng: random.Random, items: List[Any], weights: List[float]) -> Any:
    return rng.choices(items, weights=weights, k=1)[0]


# ---------------------------------------------------------------- генератор

class Generator:

    def __init__(self, cfg: Config) -> None:
        self.cfg = cfg
        self.rng = random.Random(cfg.seed)
        self.venues = load_venues()
        self.docs: List[Doc] = []
        self.people: List[Person] = []
        self.me_person: Optional[Person] = None
        self._request_n = 0
        self._tournament_n = 0
        self._notification_n = 0
        self.requests: List[Dict[str, Any]] = []     # внутреннее описание заявок
        self.local_now = now_local(cfg)
        self._emails: set = set()

    # ----- люди

    def make_people(self) -> None:
        rng, cfg = self.rng, self.cfg
        total = max(30, int(round(120 * cfg.scale)))
        weights = [w for _, w in CITY_WEIGHTS]
        counts = {c: 0 for c, _ in CITY_WEIGHTS}
        for _ in range(total):
            counts[weighted_choice(rng, [c for c, _ in CITY_WEIGHTS], weights)] += 1
        for city in counts:                     # в каждом городе достаточно людей для встреч
            counts[city] = max(counts[city], 8)

        used = set()
        index = 0
        for city, count in counts.items():
            for _ in range(count):
                index += 1
                female = rng.random() < 0.38
                while True:
                    first = rng.choice(texts.FEMALE_FIRST if female else texts.MALE_FIRST)
                    surname = rng.choice(texts.SURNAMES)
                    last = texts.feminize(surname) if female else surname
                    if (first, last) not in used:
                        used.add((first, last))
                        break
                email = self._email(first, last)
                skill = weighted_choice(rng, LEVELS, LEVEL_WEIGHTS)
                mean, spread = LEVEL_STRENGTH[skill]
                strength = rng.gauss(mean, spread)
                self.people.append(Person(
                    uid="{}u{:04d}".format(SEED_ID_PREFIX, index),
                    first=first, last=last, city=city, skill=skill,
                    grip=weighted_choice(rng, GRIPS, [85, 15]),
                    style=weighted_choice(rng, STYLES, [50, 30, 20]),
                    strength=strength,
                    ttw=self._ttw(skill),
                    created=cfg.now - timedelta(days=rng.uniform(20, 600)),
                    weight=min(rng.lognormvariate(-0.3, 0.7), 4.0),
                    kindness=rng.gauss(0.25, 0.7),
                    email=email,
                    privacy=self._privacy(),
                    last_seen=(cfg.now - timedelta(hours=rng.uniform(0.2, 90))) if rng.random() < 0.45 else None,
                ))

        # «Активные» авторы: человек 8% создаёт заявки в разы чаще остальных
        power = rng.sample(self.people, max(3, len(self.people) // 12))
        for person in power:
            person.weight = rng.uniform(5, 14)

        if cfg.me:
            mean, spread = LEVEL_STRENGTH.get(cfg.me.skill, LEVEL_STRENGTH["Любитель"])
            self.me_person = Person(
                uid=cfg.me.uid, first=cfg.me.first, last=cfg.me.last, city=cfg.me.city,
                skill=cfg.me.skill, grip=cfg.me.grip, style=cfg.me.style,
                strength=mean, ttw=0, created=cfg.now - timedelta(days=500),
                weight=0.0, kindness=0.4, is_me=True)

    def _email(self, first: str, last: str) -> str:
        """ivan.petrov@spinnet.test; при совпадении — ivan.petrov2@…"""
        base = "{}.{}".format(texts.translit(first), texts.translit(last))
        candidate, number = base, 1
        while candidate in self._emails:
            number += 1
            candidate = "{}{}".format(base, number)
        self._emails.add(candidate)
        return "{}@{}".format(candidate, self.cfg.email_domain)

    def _ttw(self, skill: str) -> int:
        rng = self.rng
        ranges = {"Начинающий": (100, 400, 0.30), "Любитель": (250, 800, 0.60),
                  "Продвинутый": (700, 1300, 0.80), "Профессионал": (1200, 2100, 0.95)}
        low, high, share = ranges[skill]
        return rng.randrange(low, high) if rng.random() < share else 0

    def _privacy(self) -> Dict[str, bool]:
        rng = self.rng
        flags = {
            "showStats": rng.random() > 0.08,
            "showMatchHistory": rng.random() > 0.12,
            "showTournaments": rng.random() > 0.10,
            "allowClarifications": rng.random() > 0.06,
            "showLastSeen": rng.random() > 0.10,
        }
        return flags if not all(flags.values()) else {}

    def user_docs(self) -> None:
        for p in self.people:
            data: Dict[str, Any] = {
                "firstName": p.first, "lastName": p.last,
                "email": p.email,
                "city": p.city, "skillLevel": p.skill, "grip": p.grip, "playStyle": p.style,
                "ratingLink": "", "ttwRating": p.ttw, "createdAt": p.created,
                "isOnline": False, "isSeed": True,
            }
            if p.privacy:
                data["privacy"] = p.privacy
            if p.last_seen:
                data["lastSeenAt"] = p.last_seen
            self.docs.append(Doc("users/" + p.uid, data))

    # ----- выбор участников, времени и места

    def city_people(self, city: str, exclude: Tuple[str, ...] = ()) -> List[Person]:
        return [p for p in self.people if p.city == city and p.uid not in exclude]

    def pick_author(self, city: Optional[str] = None) -> Person:
        # Сначала город (по долям из CITY_WEIGHTS), потом человек: внутри города активные авторы заметнее
        if city is None:
            city = weighted_choice(self.rng, [c for c, _ in CITY_WEIGHTS], [w for _, w in CITY_WEIGHTS])
        pool = self.city_people(city)
        return weighted_choice(self.rng, pool, [p.weight for p in pool])

    def pick_partner(self, author: Person) -> Person:
        rng = self.rng
        same_city = self.city_people(author.city, (author.uid,))
        pool = same_city if (rng.random() < 0.92 and same_city) else [p for p in self.people if p.uid != author.uid]
        # похожий уровень встречается чаще, но не всегда
        weights = [1.0 / (1.0 + abs(p.strength - author.strength) / 250.0) for p in pool]
        return weighted_choice(rng, pool, weights)

    def pick_venue(self, city: str) -> Dict[str, str]:
        venues = self.venues[city]
        return weighted_choice(self.rng, venues, [1.0 / (i + 1) ** 0.6 for i in range(len(venues))])

    def make_slot(self, day: date, earliest: int = 8 * 60, latest_end: int = 23 * 60 + 30) -> Slot:
        rng = self.rng
        weekend = day.weekday() >= 5
        if weekend or rng.random() < 0.28:
            start = rng.randrange(10 * 60, 18 * 60 + 1, 30)
        else:
            start = rng.randrange(18 * 60, 20 * 60 + 31, 30)
        start = max(start, earliest)
        duration = weighted_choice(rng, [60, 90, 120, 150, 180], [20, 25, 35, 12, 8])
        end = min(start + duration, latest_end)
        if end - start < 60:
            start = end - 60
        return Slot(day, start, end)

    def future_slot(self) -> Slot:
        rng = self.rng
        for _ in range(50):
            offset = min(int(rng.expovariate(1 / 8.0)), 40)
            day = self.local_now.date() + timedelta(days=offset)
            earliest = 8 * 60
            if offset == 0:
                earliest = ((self.local_now.hour + 2) * 60 + (30 if self.local_now.minute < 30 else 60))
                if earliest > 21 * 60:
                    continue
            slot = self.make_slot(day, earliest=earliest)
            if slot_start_local(slot) > self.local_now + timedelta(hours=1):
                return slot
        return self.make_slot(self.local_now.date() + timedelta(days=1))

    def past_slot(self, max_days: int = 420, mode: int = 90) -> Slot:
        rng = self.rng
        offset = max(1, int(rng.triangular(1, max_days, mode)))
        return self.make_slot(self.local_now.date() - timedelta(days=offset))

    # ----- заявки

    def new_request_id(self) -> str:
        self._request_n += 1
        return "{}r{:05d}".format(SEED_ID_PREFIX, self._request_n)

    def level_wanted(self, author: Person) -> str:
        rng = self.rng
        r = rng.random()
        if r < 0.45:
            return "Любой"
        if r < 0.80:
            return author.skill
        idx = LEVELS.index(author.skill)
        return LEVELS[max(0, min(len(LEVELS) - 1, idx + rng.choice([-1, 1])))]

    def request_doc(self, rid: str, author: Person, slot: Slot, venue: Dict[str, str], status: str,
                    created: datetime, partner: Optional[Person] = None,
                    booked_at: Optional[datetime] = None, extra: Optional[Dict[str, Any]] = None) -> None:
        data: Dict[str, Any] = {
            "userId": author.uid,
            "authorFirstName": author.first, "authorLastName": author.last,
            "authorSkillLevel": author.skill, "authorGrip": author.grip, "authorPlayStyle": author.style,
            "date": day_stamp(slot.day), "timeSlot": slot.text,
            "city": author.city, "location": venue_label(venue),
            "desiredLevel": self.level_wanted(author),
            "status": status, "createdAt": created, "isSeed": True,
        }
        if partner:
            data["bookedBy"] = partner.uid
            data["bookedAt"] = booked_at or created + timedelta(hours=2)
        if extra:
            data.update(extra)
        self.docs.append(Doc("sparring_requests/" + rid, data))
        self.requests.append({"id": rid, "author": author, "partner": partner, "slot": slot,
                              "status": status, "city": author.city})

    def created_before(self, slot: Slot, low_days: float, high_days: float) -> datetime:
        start = local_to_utc(self.cfg, slot_start_local(slot))
        created = start - timedelta(days=self.rng.uniform(low_days, high_days))
        return min(created, self.cfg.now - timedelta(minutes=self.rng.uniform(3, 600)))

    def make_active(self, author: Person) -> None:
        rng, cfg = self.rng, self.cfg
        slot = self.future_slot()
        age_days = min(rng.expovariate(1 / 2.5), 12)
        created = cfg.now - timedelta(days=age_days, minutes=rng.uniform(1, 600))
        self.request_doc(self.new_request_id(), author, slot, self.pick_venue(author.city), "active", created)

    def make_booked(self, author: Person, partner: Person, slot: Optional[Slot] = None) -> str:
        rng, cfg = self.rng, self.cfg
        slot = slot or self.future_slot()
        rid = self.new_request_id()
        created = self.created_before(slot, 2, 9)
        booked = min(created + timedelta(hours=rng.uniform(1, 70)), cfg.now - timedelta(minutes=5))
        self.request_doc(rid, author, slot, self.pick_venue(author.city), "booked", created, partner, booked)
        return rid

    def make_expired(self, author: Person) -> None:
        slot = self.past_slot(max_days=300, mode=60)
        created = self.created_before(slot, 1, 8)
        self.request_doc(self.new_request_id(), author, slot, self.pick_venue(author.city), "expired", created)

    def make_cancelled(self, author: Person, partner: Person, by_author: bool = True) -> str:
        rng = self.rng
        rid = self.new_request_id()
        slot = self.past_slot(max_days=200, mode=40)
        created = self.created_before(slot, 2, 9)
        booked = created + timedelta(hours=rng.uniform(1, 40))
        cancelled_at = booked + timedelta(hours=rng.uniform(1, 30))
        start = local_to_utc(self.cfg, slot_start_local(slot))
        cancelled_at = min(cancelled_at, start - timedelta(minutes=30))
        if by_author:
            extra = {"cancelledBy": author.uid, "cancelledAt": cancelled_at}
            self.request_doc(rid, author, slot, self.pick_venue(author.city), "cancelled", created,
                             partner, booked, extra)
        else:
            # Партнёр отказался — заявка вернулась в ленту и истекла без брони
            self.request_doc(rid, author, slot, self.pick_venue(author.city), "expired", created)
        return rid

    def make_completed(self, author: Person, partner: Person, slot: Optional[Slot] = None) -> str:
        rng = self.rng
        slot = slot or self.past_slot()
        rid = self.new_request_id()
        created = self.created_before(slot, 1, 12)
        start = local_to_utc(self.cfg, slot_start_local(slot))
        booked = created + (start - created) * rng.uniform(0.05, 0.9)
        completed = local_to_utc(self.cfg, slot_end_local(slot)) + timedelta(minutes=rng.uniform(1, 40))
        self.request_doc(rid, author, slot, self.pick_venue(author.city), "completed", created, partner,
                         booked, {"completedAt": min(completed, self.cfg.now)})
        return rid

    # ----- матчи

    def make_matches(self, request: Dict[str, Any]) -> List[Dict[str, Any]]:
        rng, cfg = self.rng, self.cfg
        author, partner, slot = request["author"], request["partner"], request["slot"]
        if rng.random() > 0.78:
            return []
        count = 1 + (1 if rng.random() < 0.28 else 0) + (1 if rng.random() < 0.09 else 0)
        count = min(count, max(1, slot.minutes // 25), 6)
        played = local_to_utc(cfg, slot_start_local(slot))
        end = local_to_utc(cfg, slot_end_local(slot))
        age_days = (cfg.now - end).total_seconds() / 86400.0
        made: List[Dict[str, Any]] = []
        for ordinal in range(1, count + 1):
            best_of = weighted_choice(rng, [3, 5, 7], [35, 55, 10])
            games = simulate_match(rng, author.strength, partner.strength, best_of)
            if ordinal > 1 and made[-1]["status"] == "proposed":
                break                                    # следующий матч вносят только после решения по предыдущему
            if age_days <= 10:
                status = weighted_choice(rng, ["confirmed", "proposed", "disputed"], [55, 38, 7])
            else:
                status = weighted_choice(rng, ["confirmed", "proposed", "disputed"], [93, 3, 4])
            me_involved = (author.is_me or partner.is_me)
            who_first = weighted_choice(rng, [author, partner], [50, 50])
            if status == "proposed" and me_involved:
                who_first = partner if author.is_me else author      # ждут ответа именно от владельца
                if rng.random() > 0.75:
                    who_first = author if author.is_me else partner
            other = partner if who_first is author else author
            created = min(end + timedelta(minutes=rng.uniform(5, 180)), cfg.now - timedelta(minutes=1))
            rid = request["id"]
            doc_id = rid if ordinal == 1 else "{}_{}".format(rid, ordinal)
            data: Dict[str, Any] = {
                "playerAId": author.uid, "playerBId": partner.uid,
                "playerIds": [author.uid, partner.uid],
                "games": encode_games(games), "bestOf": best_of, "status": status,
                "proposedBy": who_first.uid, "revision": 1,
                "playedAt": played, "slotMinutes": slot.minutes, "city": request["city"],
                "createdAt": created, "updatedAt": created, "isSeed": True,
            }
            if status == "confirmed":
                updated = min(created + timedelta(minutes=rng.uniform(5, 2400)), cfg.now - timedelta(seconds=30))
                data.update({"confirmedBy": other.uid, "confirmedAt": updated, "updatedAt": updated})
            elif status == "disputed":
                counter = games
                for _ in range(20):
                    counter = simulate_match(rng, author.strength, partner.strength, best_of)
                    if counter != games:
                        break
                updated = min(created + timedelta(minutes=rng.uniform(5, 2400)), cfg.now - timedelta(seconds=30))
                data.update({"games": encode_games(counter), "proposedBy": other.uid, "revision": 2,
                             "previousGames": encode_games(games), "previousProposedBy": who_first.uid,
                             "updatedAt": updated})
                games = counter
            self.docs.append(Doc("matches/" + doc_id, data))
            made.append({"id": doc_id, "status": status, "games": games, "best_of": best_of,
                         "proposed_by": data["proposedBy"], "created": created, "request": request})
        return made

    # ----- отзывы

    def make_reviews(self, request: Dict[str, Any]) -> List[Dict[str, Any]]:
        rng, cfg = self.rng, self.cfg
        author, partner, slot = request["author"], request["partner"], request["slot"]
        end = local_to_utc(cfg, slot_end_local(slot))
        age_days = (cfg.now - end).total_seconds() / 86400.0
        chance = 0.40 if age_days <= 3 else 0.62
        out: List[Dict[str, Any]] = []
        for giver, receiver in ((author, partner), (partner, author)):
            if rng.random() > chance:
                continue
            raw = rng.gauss(4.35 + receiver.kindness * 0.55, 0.9)
            rating = int(max(1, min(5, round(raw))))
            comment = ""
            if rng.random() < 0.55:
                comment = rng.choice(texts.REVIEW_COMMENTS[rating])
            moderation = "approved"
            if rating <= 2 and comment and rng.random() < 0.5:
                moderation = "pending"
            created = min(end + timedelta(minutes=rng.uniform(10, 4300)), cfg.now - timedelta(seconds=20))
            doc_id = "{}_{}".format(request["id"], giver.uid)
            self.docs.append(Doc("reviews/" + doc_id, {
                "fromUserId": giver.uid, "fromUserName": giver.full, "toUserId": receiver.uid,
                "sparringRequestId": request["id"], "rating": rating, "comment": comment,
                "moderationStatus": moderation, "reportedCount": 0, "createdAt": created, "isSeed": True,
            }))
            out.append({"id": doc_id, "giver": giver, "receiver": receiver, "rating": rating})
        return out

    # ----- турниры

    def tournament_title(self, city: str, day: date) -> str:
        rng = self.rng
        pool = list(texts.TOURNAMENT_TITLES)
        if city == "Томск":
            pool += texts.STUDENT_TITLES * 2
        title = rng.choice(pool).replace("{season}", SEASONS[day.month])
        return title

    def make_tournament(self, city: str, day: date, organizer: Person, *, fill: Optional[float] = None,
                        two_days: Optional[bool] = None, title: Optional[str] = None,
                        participants_extra: Tuple[Person, ...] = (), confirmed_extra: Tuple[Person, ...] = ()) -> str:
        rng, cfg = self.rng, self.cfg
        self._tournament_n += 1
        tid = "{}t{:03d}".format(SEED_ID_PREFIX, self._tournament_n)
        venue = self.pick_venue(city)
        capacity = weighted_choice(rng, [8, 12, 16, 24, 32, 48, 64], [10, 16, 24, 20, 14, 10, 6])
        if two_days is None:
            two_days = rng.random() < 0.12
        start_h = rng.choice([10, 11, 12, 14, 16, 18, 19])
        start_time = "{:02d}:00".format(start_h)
        end_day = day + timedelta(days=1 if two_days else 0)
        end_h = min(start_h + rng.choice([4, 5, 6, 8]), 22) if not two_days else rng.choice([15, 17, 18])
        if end_h <= start_h and not two_days:
            end_h = min(start_h + 3, 23)
        end_time = "{:02d}:00".format(end_h)

        start_dt = datetime(day.year, day.month, day.day, start_h)
        end_dt = datetime(end_day.year, end_day.month, end_day.day, end_h)
        if end_dt < self.local_now:
            status = "completed"
        elif start_dt <= self.local_now:
            status = "in_progress"
        else:
            status = "upcoming"

        if fill is None:
            fill = rng.uniform(0.6, 1.0) if status == "completed" else rng.choice(
                [rng.uniform(0.05, 0.5), rng.uniform(0.4, 0.9), 1.0])
        crowd = [p for p in self.people if p.city == city and p.uid != organizer.uid]
        rng.shuffle(crowd)
        wanted = max(0, min(capacity, int(round(capacity * fill))))
        members = list(participants_extra) + [p for p in crowd if p not in participants_extra]
        members = members[:wanted] if wanted >= len(participants_extra) else list(participants_extra)
        if len(members) < wanted:                        # в городе мало людей — добираем из других
            others = [p for p in self.people if p.city != city and p not in members]
            rng.shuffle(others)
            members += others[: wanted - len(members)]
        member_ids = [p.uid for p in members]
        if status == "completed":
            confirmed = [p.uid for p in members if rng.random() < 0.95]
        else:
            confirmed = [p.uid for p in members if rng.random() < 0.55]
        for p in confirmed_extra:
            if p.uid in member_ids and p.uid not in confirmed:
                confirmed.append(p.uid)

        created = local_to_utc(cfg, start_dt) - timedelta(days=rng.uniform(8, 45))
        created = min(created, cfg.now - timedelta(hours=rng.uniform(1, 72)))
        description = "{} {}".format(rng.choice(texts.TOURNAMENT_FORMATS), rng.choice(texts.TOURNAMENT_NOTES))
        data: Dict[str, Any] = {
            "title": title or self.tournament_title(city, day),
            "date": day_stamp(day), "startTime": start_time,
            "endDate": day_stamp(end_day), "endTime": end_time,
            "city": city, "location": venue_label(venue), "description": description,
            "maxParticipants": capacity,
            "organizerId": organizer.uid, "organizerName": organizer.full,
            "participants": member_ids, "confirmedParticipants": confirmed,
            "status": status, "createdAt": created, "isSeed": True,
        }
        if status == "completed":
            data["completedAt"] = min(local_to_utc(cfg, end_dt), cfg.now)
        self.docs.append(Doc("tournaments/" + tid, data))
        return tid

    # ----- уведомления владельцу

    def notification(self, kind: str, created: datetime, *, who: str = "", when: str = "", score: str = "",
                     title: str = "", target_type: Optional[str] = None, target_id: Optional[str] = None,
                     actor: Optional[Person] = None, read: bool = False) -> None:
        head, body = texts.NOTIFICATION_TEXTS[kind]
        self._notification_n += 1
        data: Dict[str, Any] = {
            "type": kind, "title": head,
            "body": body.format(who=who, when=when, score=score, title=title),
            "targetType": target_type, "targetId": target_id,
            "isRead": read, "createdAt": created, "isSeed": True,
        }
        if actor:
            data["actorId"] = actor.uid
            data["actorName"] = actor.full
        self.docs.append(Doc("notifications/{}/items/{}n{:03d}".format(self.cfg.me.uid, SEED_ID_PREFIX,
                                                                      self._notification_n), data))

    # ----- сборка мира

    def build(self) -> World:
        rng, cfg = self.rng, self.cfg
        scale = cfg.scale
        self.make_people()
        self.user_docs()

        for _ in range(int(round(220 * scale))):
            self.make_active(self.pick_author())
        for _ in range(int(round(45 * scale))):
            author = self.pick_author()
            self.make_booked(author, self.pick_partner(author))
        for _ in range(int(round(340 * scale))):
            author = self.pick_author()
            self.make_completed(author, self.pick_partner(author))
        for _ in range(int(round(70 * scale))):
            self.make_expired(self.pick_author())
        for _ in range(int(round(40 * scale))):
            author = self.pick_author()
            self.make_cancelled(author, self.pick_partner(author), by_author=rng.random() < 0.7)

        if cfg.me and self.me_person:
            self.build_me_part()

        # Матчи и отзывы строятся по завершённым играм
        completed = [r for r in self.requests if r["status"] == "completed" and r["partner"]]
        self.match_info: Dict[str, List[Dict[str, Any]]] = {}
        self.review_info: Dict[str, List[Dict[str, Any]]] = {}
        skip = getattr(self, "pending_review_request", None)   # игра «вчера» остаётся без счёта и отзыва
        for request in completed:
            if request["id"] == skip:
                continue
            self.match_info[request["id"]] = self.make_matches(request)
            self.review_info[request["id"]] = self.make_reviews(request)

        self.build_tournaments()
        if cfg.me and self.me_person:
            self.build_me_tournaments()
            self.build_me_notifications()
        return World(cfg, self.people + ([self.me_person] if self.me_person else []), self.docs)

    # Только вокруг владельца: заявки, игры, отмены
    def build_me_part(self) -> None:
        rng = self.rng
        me = self.me_person
        assert me is not None
        mates = self.city_people(me.city)

        def partner() -> Person:
            pool = mates if rng.random() < 0.85 else self.people
            return weighted_choice(rng, pool, [1.0 / (1.0 + abs(p.strength - me.strength) / 250.0) for p in pool])

        # Свои заявки в ленте (в том числе несколько на одно время ближайших дней)
        for _ in range(7):
            self.make_active(me)
        # Ближайшие игры: одна — сегодня позже или завтра с утра
        today_slot = self.future_slot()
        self.make_booked(me, partner(), today_slot)
        self.make_booked(partner(), me)
        self.make_booked(me, partner())
        self.make_booked(partner(), me)
        # История: год с лишним, равномерно по месяцам
        for index in range(56):
            other = partner()
            slot = self.past_slot(max_days=410, mode=140)
            if index % 2 == 0:
                self.make_completed(me, other, slot)
            else:
                self.make_completed(other, me, slot)
        # Игра вчера вечером: без счёта и отзыва — для сценария «Как прошла игра?»
        yesterday = self.make_slot(self.local_now.date() - timedelta(days=1), earliest=17 * 60)
        self.make_completed(partner(), me, yesterday)
        self.pending_review_request = self.requests[-1]["id"]
        for _ in range(6):
            self.make_expired(me)
        self.make_cancelled(me, partner(), by_author=True)
        self.make_cancelled(me, partner(), by_author=True)
        self.make_cancelled(partner(), me, by_author=True)    # отменил автор — владелец был партнёром
        self.make_cancelled(partner(), me, by_author=True)

    def build_tournaments(self) -> None:
        rng, cfg = self.rng, self.cfg
        total = int(round(48 * cfg.scale))
        cities = [c for c, _ in CITY_WEIGHTS]
        today = self.local_now.date()
        per_city = max(4, total // len(cities))
        for city in cities:
            for index in range(per_city):
                # Две трети — будущие, остальное — прошедшие (для профилей и истории)
                if index % 3 != 2:
                    day = today + timedelta(days=rng.randrange(1, 150))
                else:
                    day = today - timedelta(days=rng.randrange(7, 180))
                organizer = self.pick_author(city)
                self.make_tournament(city, day, organizer)

    def build_me_tournaments(self) -> None:
        rng = self.rng
        me = self.me_person
        assert me is not None
        city = me.city
        today = self.local_now.date()
        organizer = self.pick_author(city)
        self.make_tournament(city, today - timedelta(days=rng.randrange(20, 70)), organizer,
                             fill=0.9, participants_extra=(me,), confirmed_extra=(me,), title="Осенний кубок любителей")
        self.make_tournament(city, today - timedelta(days=rng.randrange(80, 160)), self.pick_author(city),
                             fill=0.8, participants_extra=(me,), confirmed_extra=(me,))
        self.my_upcoming_confirmed = self.make_tournament(
            city, today + timedelta(days=rng.randrange(4, 12)), self.pick_author(city),
            fill=0.6, participants_extra=(me,), confirmed_extra=(me,), two_days=False)
        self.make_tournament(city, today + timedelta(days=rng.randrange(12, 30)), self.pick_author(city),
                             fill=0.4, participants_extra=(me,))
        # Турнир, который организует сам владелец
        self.make_tournament(city, today + timedelta(days=rng.randrange(14, 40)), me, fill=0.35,
                             title="Открытый турнир для любителей", two_days=False)

    def build_me_notifications(self) -> None:
        cfg = self.cfg
        me = self.me_person
        assert me is not None
        rng = self.rng
        recent: List[datetime] = sorted(
            [cfg.now - timedelta(hours=rng.uniform(0.3, 110)) for _ in range(16)], reverse=True)
        slot_of = {r["id"]: r for r in self.requests}
        mine = [r for r in self.requests if r["author"] is me or r["partner"] is me]

        def other(r: Dict[str, Any]) -> Person:
            return r["partner"] if r["author"] is me else r["author"]

        booked_mine = [r for r in mine if r["status"] == "booked"]
        for r in booked_mine[:3]:
            if r["author"] is me:
                self.notification("request_booked", recent.pop(0), who=other(r).full,
                                  when=russian_when(r["slot"]), target_type="game", target_id=r["id"],
                                  actor=other(r))
        if booked_mine:
            r = booked_mine[0]
            self.notification("game_reminder", recent.pop(0), who=other(r).full, when=russian_when(r["slot"]),
                              target_type="game", target_id=r["id"], actor=other(r))
        pending = [r for r in mine if r["id"] == getattr(self, "pending_review_request", None)]
        for r in pending:
            self.notification("review_reminder", recent.pop(0), who=other(r).full, when=russian_when(r["slot"]),
                              target_type="game", target_id=r["id"], actor=other(r))

        for request_id, matches in self.match_info.items():
            r = slot_of[request_id]
            if r["author"] is not me and r["partner"] is not me:
                continue
            for m in matches:
                if not recent:
                    break
                score = ", ".join("{}:{}".format(a, b) for a, b in m["games"])
                if m["status"] == "proposed" and m["proposed_by"] != me.uid:
                    self.notification("match_proposed", recent.pop(0), who=other(r).full, score=score,
                                      target_type="game", target_id=request_id, actor=other(r))
                elif m["status"] == "disputed" and rng.random() < 0.5:
                    self.notification("match_disputed", recent.pop(0), who=other(r).full,
                                      target_type="game", target_id=request_id, actor=other(r))
                elif m["status"] == "confirmed" and rng.random() < 0.06:
                    self.notification("match_confirmed", recent.pop(0), who=other(r).full, score=score,
                                      target_type="game", target_id=request_id, actor=other(r))

        cancelled = [r for r in mine if r["status"] == "cancelled" and r["partner"] is me]
        for r in cancelled[:1]:
            if recent:
                self.notification("cancellation", recent.pop(0), who=r["author"].full, when=russian_when(r["slot"]),
                                  target_type="profile", target_id=r["author"].uid, actor=r["author"])

        tid = getattr(self, "my_upcoming_confirmed", None)
        if tid and recent:
            doc = next(d for d in self.docs if d.path == "tournaments/" + tid)
            start = doc.data["date"]
            when = "{} {}, {}".format(start.day, MONTHS_GEN[start.month - 1], doc.data["startTime"])
            self.notification("tournament_starting", recent.pop(0), title=doc.data["title"], when=when,
                              target_type="tournament", target_id=tid)

        # Первые шесть — непрочитанные, остальные — прочитаны
        items = [d for d in self.docs if d.path.startswith("notifications/")]
        items.sort(key=lambda d: d.data["createdAt"], reverse=True)
        for index, doc in enumerate(items):
            doc.data["isRead"] = index >= 6


# ---------------------------------------------------------------- вход

def build_world(cfg: Config) -> World:
    return Generator(cfg).build()


def summarize(world: World) -> Dict[str, Any]:
    """Короткая сводка для режима plan."""
    by_collection = Counter(d.collection for d in world.docs)
    requests = [d for d in world.docs if d.collection == "sparring_requests"]
    statuses = Counter(d.data["status"] for d in requests)
    active_by_city = Counter(d.data["city"] for d in requests if d.data["status"] == "active")
    authors = Counter(d.data["userId"] for d in requests)
    names = {p.uid: p.full for p in world.people}
    top = [(names.get(uid, uid), count) for uid, count in authors.most_common(5)]
    matches = [d for d in world.docs if d.collection == "matches"]
    return {
        "documents": dict(by_collection),
        "total": len(world.docs),
        "request_statuses": dict(statuses),
        "active_requests_by_city": dict(active_by_city),
        "top_authors": top,
        "match_statuses": dict(Counter(d.data["status"] for d in matches)),
        "tournament_statuses": dict(Counter(d.data["status"] for d in world.docs if d.collection == "tournaments")),
        "review_ratings": dict(sorted(Counter(d.data["rating"] for d in world.docs if d.collection == "reviews").items())),
    }

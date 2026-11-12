# -*- coding: utf-8 -*-
"""Проверки генератора тестовых данных. Запуск: python3 -m unittest discover -s tests (из tools/seed)."""
import re
import sys
import unittest
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import generate  # noqa: E402
from generate import Config, Me  # noqa: E402

NOW = datetime(2026, 10, 13, 12, 0, tzinfo=timezone.utc)
SLOT_RE = re.compile(r"^(\d\d):(\d\d) – (\d\d):(\d\d)$")
ME = Me(uid="TESTMEUID123", first="Михаил", last="Крупеня", city="Томск", skill="Продвинутый")


def world(scale=1.0, me=None, seed=2026):
    return generate.build_world(Config(now=NOW, scale=scale, seed=seed, me=me))


class ScoringPortTests(unittest.TestCase):
    """Порт правил счёта должен вести себя так же, как MatchScoring.swift."""

    def test_valid_and_invalid_games(self):
        for a, b in [(11, 0), (11, 9), (12, 10), (15, 13), (0, 11), (9, 11)]:
            self.assertIsNone(generate.game_error(a, b), (a, b))
        for a, b in [(10, 10), (11, 10), (12, 9), (10, 5), (13, 10), (-1, 11), (41, 39)]:
            self.assertIsNotNone(generate.game_error(a, b), (a, b))

    def test_match_must_end_exactly(self):
        self.assertEqual(generate.validate_match([(11, 5), (11, 7), (11, 9)], 5), (3, 0))
        self.assertIsNone(generate.validate_match([(11, 5), (11, 7)], 5))                 # не закончен
        self.assertIsNone(generate.validate_match([(11, 5), (11, 7), (11, 9), (11, 1)], 5))  # лишняя партия
        self.assertEqual(generate.validate_match([(11, 5), (5, 11), (11, 9)], 3), (2, 1))


class GeneratedDataTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.w = world()
        cls.wm = world(me=ME)
        cls.requests = {d.path.split("/")[1]: d.data for d in cls.w.by_collection("sparring_requests")}

    # ----- общее

    def test_every_document_is_marked_and_prefixed(self):
        for doc in self.wm.docs:
            self.assertTrue(doc.data["isSeed"], doc.path)
            self.assertTrue(doc.path.split("/")[-1].startswith("seed") or doc.path.startswith("users/seed"), doc.path)

    def test_ids_have_no_underscore_except_reviews_and_extra_matches(self):
        for doc in self.w.docs:
            name = doc.path.split("/")[-1]
            if doc.collection in ("sparring_requests", "users", "tournaments"):
                self.assertNotIn("_", name)
            if doc.collection == "matches":
                self.assertRegex(name, r"^[A-Za-z0-9]+(_[2-6])?$")

    def test_nothing_is_created_in_the_future(self):
        keys = ("createdAt", "bookedAt", "completedAt", "cancelledAt", "confirmedAt", "updatedAt", "lastSeenAt")
        for doc in self.wm.docs:
            for key in keys:
                value = doc.data.get(key)
                if value is not None:
                    self.assertLessEqual(value, NOW, "{} {}".format(doc.path, key))

    def test_names_are_unique_and_emails_are_on_the_reserved_test_domain(self):
        users = [d.data for d in self.w.by_collection("users")]
        names = Counter((u["firstName"], u["lastName"]) for u in users)
        self.assertEqual(max(names.values()), 1)
        emails = [u["email"] for u in users]
        self.assertEqual(len(set(emails)), len(emails))
        for u in users:
            self.assertRegex(u["email"], r"^[a-z]+\.[a-z]+[0-9]*@spinnet\.test$")
            self.assertIn(u["skillLevel"], generate.LEVELS)
            self.assertIn(u["grip"], generate.GRIPS)
            self.assertIn(u["playStyle"], generate.STYLES)

    def test_same_settings_give_same_data(self):
        again = world()
        self.assertEqual([(d.path, d.data) for d in self.w.docs], [(d.path, d.data) for d in again.docs])

    def test_other_seed_gives_other_data(self):
        other = world(seed=7)
        self.assertNotEqual([d.data for d in self.w.docs][:50], [d.data for d in other.docs][:50])

    # ----- заявки

    def test_request_shape_matches_the_app_model(self):
        for rid, d in self.requests.items():
            for key in ("userId", "date", "timeSlot", "location", "status", "createdAt"):
                self.assertIn(key, d, rid)
            m = SLOT_RE.match(d["timeSlot"])
            self.assertIsNotNone(m, d["timeSlot"])
            start = int(m.group(1)) * 60 + int(m.group(2))
            end = int(m.group(3)) * 60 + int(m.group(4))
            self.assertGreaterEqual(end - start, 60, d["timeSlot"])
            self.assertLessEqual(end, 23 * 60 + 59)
            self.assertIn(d["status"], ("active", "booked", "completed", "expired", "cancelled"))
            self.assertEqual(d["date"].hour, 7)

    def test_request_city_matches_author_and_venue_is_real_entry(self):
        users = {d.path.split("/")[1]: d.data for d in self.w.by_collection("users")}
        venue_cities = generate.load_venues()
        labels = {generate.venue_label(v): c for c, vs in venue_cities.items() for v in vs}
        for rid, d in self.requests.items():
            self.assertEqual(d["city"], users[d["userId"]]["city"], rid)
            self.assertEqual(labels[d["location"]], d["city"], rid)

    def test_booked_and_completed_have_partner_who_is_not_the_author(self):
        for rid, d in self.requests.items():
            if d["status"] in ("booked", "completed", "cancelled"):
                self.assertTrue(d.get("bookedBy"), rid)
                self.assertNotEqual(d["bookedBy"], d["userId"], rid)
            if d["status"] in ("active", "expired"):
                self.assertNotIn("bookedBy", d)

    def test_future_and_past_statuses_agree_with_dates(self):
        for rid, d in self.requests.items():
            m = SLOT_RE.match(d["timeSlot"])
            day = d["date"]
            start_local = datetime(day.year, day.month, day.day, int(m.group(1)), int(m.group(2)))
            end_local = datetime(day.year, day.month, day.day, int(m.group(3)), int(m.group(4)))
            now_local = datetime(2026, 10, 13, 19, 0)
            if d["status"] in ("active", "booked"):
                self.assertGreater(start_local, now_local, rid)
            else:
                self.assertLess(end_local, now_local, rid)

    def test_several_authors_have_many_active_requests(self):
        per_author = Counter(d["userId"] for d in self.requests.values() if d["status"] == "active")
        self.assertGreaterEqual(per_author.most_common(1)[0][1], 8)
        total_per_author = Counter(d["userId"] for d in self.requests.values())
        self.assertGreaterEqual(total_per_author.most_common(1)[0][1], 25)

    def test_every_city_has_enough_active_requests(self):
        per_city = Counter(d["city"] for d in self.requests.values() if d["status"] == "active")
        self.assertEqual(set(per_city), {c for c, _ in generate.CITY_WEIGHTS})
        self.assertGreaterEqual(min(per_city.values()), 15)

    # ----- матчи

    def test_every_match_passes_the_scoring_rules(self):
        matches = self.wm.by_collection("matches")
        self.assertGreater(len(matches), 300)
        for doc in matches:
            games = [(g["a"], g["b"]) for g in doc.data["games"]]
            self.assertIsNotNone(generate.validate_match(games, doc.data["bestOf"]), doc.path)
            if doc.data.get("previousGames"):
                prev = [(g["a"], g["b"]) for g in doc.data["previousGames"]]
                self.assertIsNotNone(generate.validate_match(prev, doc.data["bestOf"]), doc.path)
                self.assertNotEqual(prev, games)

    def test_match_belongs_to_completed_request_with_same_players(self):
        for doc in self.wm.by_collection("matches"):
            rid = doc.path.split("/")[1].split("_")[0]
            request = next(d for d in self.wm.by_collection("sparring_requests") if d.path.endswith("/" + rid))
            self.assertEqual(request.data["status"], "completed", doc.path)
            self.assertEqual(doc.data["playerAId"], request.data["userId"])
            self.assertEqual(doc.data["playerBId"], request.data["bookedBy"])
            self.assertEqual(doc.data["playerIds"], [doc.data["playerAId"], doc.data["playerBId"]])
            self.assertIn(doc.data["proposedBy"], doc.data["playerIds"])
            self.assertEqual(doc.data["city"], request.data["city"])

    def test_confirmed_matches_are_confirmed_by_the_other_player(self):
        for doc in self.wm.by_collection("matches"):
            d = doc.data
            if d["status"] == "confirmed":
                self.assertIn(d["confirmedBy"], d["playerIds"])
                self.assertNotEqual(d["confirmedBy"], d["proposedBy"])
            if d["status"] == "disputed":
                self.assertEqual(d["revision"], 2)
                self.assertNotEqual(d["previousProposedBy"], d["proposedBy"])
            if d["status"] == "proposed":
                self.assertEqual(d["revision"], 1)

    def test_extra_matches_follow_a_decided_previous_one(self):
        by_request = defaultdict(dict)
        for doc in self.wm.by_collection("matches"):
            rid, _, n = doc.path.split("/")[1].partition("_")
            by_request[rid][int(n) if n else 1] = doc.data["status"]
        for rid, ordinals in by_request.items():
            self.assertEqual(sorted(ordinals), list(range(1, len(ordinals) + 1)), rid)
            for n in range(2, len(ordinals) + 1):
                self.assertNotEqual(ordinals[n - 1], "proposed", rid)

    def test_stronger_players_win_more_often(self):
        users = {d.path.split("/")[1]: d.data for d in self.w.by_collection("users")}
        order = {name: i for i, name in enumerate(generate.LEVELS)}
        higher_wins = higher_total = 0
        for doc in self.w.by_collection("matches"):
            d = doc.data
            if d["status"] != "confirmed":
                continue
            games = [(g["a"], g["b"]) for g in d["games"]]
            won_a, won_b = generate.validate_match(games, d["bestOf"])
            la, lb = order[users[d["playerAId"]]["skillLevel"]], order[users[d["playerBId"]]["skillLevel"]]
            if la == lb:
                continue
            higher_total += 1
            if (la > lb) == (won_a > won_b):
                higher_wins += 1
        self.assertGreater(higher_total, 30)
        self.assertGreater(higher_wins / higher_total, 0.6)

    # ----- отзывы

    def test_reviews_are_consistent(self):
        seen = set()
        for doc in self.wm.by_collection("reviews"):
            d = doc.data
            rid = d["sparringRequestId"]
            self.assertEqual(doc.path, "reviews/{}_{}".format(rid, d["fromUserId"]))
            self.assertNotIn(doc.path, seen)
            seen.add(doc.path)
            self.assertIn(d["rating"], (1, 2, 3, 4, 5))
            self.assertNotEqual(d["fromUserId"], d["toUserId"])
            request = next(x for x in self.wm.by_collection("sparring_requests") if x.path.endswith("/" + rid))
            self.assertEqual(request.data["status"], "completed")
            self.assertEqual({d["fromUserId"], d["toUserId"]}, {request.data["userId"], request.data["bookedBy"]})
            self.assertIn(d["moderationStatus"], ("approved", "pending"))

    def test_reviews_have_variety(self):
        reviews = [d.data for d in self.w.by_collection("reviews")]
        ratings = Counter(r["rating"] for r in reviews)
        self.assertGreaterEqual(len(ratings), 4)
        self.assertGreater(sum(1 for r in reviews if r["comment"]), 100)
        self.assertGreater(sum(1 for r in reviews if not r["comment"]), 100)

    # ----- турниры

    def test_tournaments_are_consistent(self):
        tournaments = self.wm.by_collection("tournaments")
        self.assertGreaterEqual(len(tournaments), 48)
        for doc in tournaments:
            d = doc.data
            self.assertLessEqual(len(d["participants"]), d["maxParticipants"], doc.path)
            self.assertEqual(len(set(d["participants"])), len(d["participants"]), doc.path)
            self.assertTrue(set(d["confirmedParticipants"]) <= set(d["participants"]), doc.path)
            self.assertNotIn(d["organizerId"], d["participants"], doc.path)
            self.assertLessEqual(d["date"], d["endDate"])
            self.assertRegex(d["startTime"], r"^\d\d:00$")
            self.assertRegex(d["endTime"], r"^\d\d:00$")
            self.assertIn(d["status"], ("upcoming", "in_progress", "completed"))
            if d["status"] == "completed":
                self.assertLess(d["endDate"], datetime(2026, 10, 14, tzinfo=timezone.utc))

    def test_tournaments_cover_all_cities_and_statuses(self):
        tournaments = [d.data for d in self.w.by_collection("tournaments")]
        self.assertEqual({t["city"] for t in tournaments}, {c for c, _ in generate.CITY_WEIGHTS})
        self.assertEqual({t["status"] for t in tournaments}, {"upcoming", "completed"})

    # ----- владелец аккаунта

    def test_owner_has_enough_history_for_every_filter(self):
        me = ME.uid
        requests = [d.data for d in self.wm.by_collection("sparring_requests")
                    if d.data["userId"] == me or d.data.get("bookedBy") == me]
        completed = [r for r in requests if r["status"] == "completed"]
        self.assertGreaterEqual(len(completed), 50)                       # порог фильтра игр — 4
        months = {(r["date"].year, r["date"].month) for r in completed}
        self.assertGreaterEqual(len(months), 8)                           # группы «по месяцам»
        roles = {r["userId"] == me for r in completed}
        self.assertEqual(roles, {True, False})                            # и автор, и партнёр
        matches = [d.data for d in self.wm.by_collection("matches") if me in d.data["playerIds"]]
        self.assertGreaterEqual(len(matches), 30)                         # порог фильтра матчей — 5
        self.assertTrue(any(m["status"] == "proposed" and m["proposedBy"] != me for m in matches))
        self.assertTrue(any(m["status"] == "confirmed" for m in matches))
        reviews = [d.data for d in self.wm.by_collection("reviews") if d.data["toUserId"] == me]
        self.assertGreaterEqual(len(reviews), 15)                         # порог фильтра отзывов — 3
        self.assertGreaterEqual(len({r["rating"] for r in reviews}), 3)

    def test_owner_has_upcoming_games_active_requests_and_a_game_without_feedback(self):
        me = ME.uid
        mine = {d.path.split("/")[1]: d.data for d in self.wm.by_collection("sparring_requests")
                if d.data["userId"] == me or d.data.get("bookedBy") == me}
        self.assertGreaterEqual(sum(1 for r in mine.values() if r["status"] == "active"), 7)
        self.assertGreaterEqual(sum(1 for r in mine.values() if r["status"] == "booked"), 4)
        self.assertTrue(any(r["status"] == "cancelled" for r in mine.values()))
        matches = {d.path.split("/")[1].split("_")[0] for d in self.wm.by_collection("matches")}
        reviews = {d.data["sparringRequestId"] for d in self.wm.by_collection("reviews")}
        yesterday = [rid for rid, r in mine.items() if r["status"] == "completed"
                     and r["date"].date() == datetime(2026, 10, 12).date()]
        self.assertTrue(any(rid not in matches and rid not in reviews for rid in yesterday))

    def test_owner_is_never_written_as_a_user_document(self):
        self.assertNotIn("users/" + ME.uid, {d.path for d in self.wm.docs})

    def test_owner_notifications_have_valid_types(self):
        valid = {"request_booked", "game_reminder", "review_reminder", "match_proposed", "match_confirmed",
                 "match_disputed", "cancellation", "tournament_starting"}
        items = [d for d in self.wm.docs if d.collection == "notifications"]
        self.assertGreaterEqual(len(items), 6)
        for doc in items:
            self.assertTrue(doc.path.startswith("notifications/{}/items/seedn".format(ME.uid)))
            self.assertIn(doc.data["type"], valid)
            self.assertTrue(doc.data["title"] and doc.data["body"])
            self.assertNotIn("{", doc.data["body"])
        self.assertTrue(any(not d.data["isRead"] for d in items))

    def test_scale_changes_volume(self):
        small = world(scale=0.5)
        large = world(scale=2.0)
        self.assertLess(len(small.docs), len(self.w.docs))
        self.assertGreater(len(large.docs), len(self.w.docs) * 1.6)


if __name__ == "__main__":
    unittest.main()

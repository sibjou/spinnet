#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Тестовые данные для Spinnet: люди, заявки, игры со счётом, отзывы, турниры.

    python3 seed.py plan  [--scale 1] [--me-uid UID --me-first Имя --me-last Фамилия]
    python3 seed.py apply --project spinnet-30103 --key key.json [те же параметры]
    python3 seed.py clean --project spinnet-30103 --key key.json [--me-uid UID]

`plan` ничего не пишет в базу: считает данные и кладёт их в out/plan.json, чтобы можно было посмотреть.
Каждый созданный документ помечен `isSeed: true`, а `clean` удаляет только такие документы.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import secrets
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, NamedTuple, Optional, Tuple

import generate
from generate import Config, Doc, Me, World

HERE = Path(__file__).resolve().parent
OUT_DIR = HERE / "out"
BATCH_SIZE = 400
SEED_COLLECTIONS = ["users", "sparring_requests", "matches", "reviews", "tournaments"]
AUTH_UID_PREFIX = generate.SEED_ID_PREFIX + "u"      # uid всех тестовых игроков: seedu0001 …


# ---------------------------------------------------------------- параметры

def add_world_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--scale", type=float, default=1.0,
                        help="Размер набора: 1 — около 120 человек и 700 заявок, 5 — для проверки скорости")
    parser.add_argument("--seed", type=int, default=2026, help="Число для повторяемого набора")
    parser.add_argument("--tz", type=int, default=7, help="Часовой пояс телефона для скриншотов (Томск = 7)")
    parser.add_argument("--email-domain", default="spinnet.test",
                        help="Домен адресов тестовых игроков (по умолчанию spinnet.test)")
    parser.add_argument("--me-uid", help="uid вашего настоящего аккаунта (Firebase Console → Authentication)")
    parser.add_argument("--me-first", help="Ваше имя, как в профиле")
    parser.add_argument("--me-last", help="Ваша фамилия, как в профиле")
    parser.add_argument("--me-city", default="Томск")
    parser.add_argument("--me-skill", default="Любитель",
                        choices=["Начинающий", "Любитель", "Продвинутый", "Профессионал"])


def add_firebase_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--project", required=True, help="id проекта Firebase, например spinnet-30103")
    parser.add_argument("--key", help="JSON-ключ сервисного аккаунта (или GOOGLE_APPLICATION_CREDENTIALS)")
    parser.add_argument("--yes", action="store_true", help="Не спрашивать подтверждение")
    parser.add_argument("--no-auth", action="store_true",
                        help="Не трогать аккаунты Firebase Authentication (только документы Firestore)")


def config_from(args: argparse.Namespace) -> Config:
    me: Optional[Me] = None
    if args.me_uid:
        if not (args.me_first and args.me_last):
            raise SystemExit("С --me-uid нужны ещё --me-first и --me-last (как в вашем профиле)")
        me = Me(uid=args.me_uid, first=args.me_first, last=args.me_last,
                city=args.me_city, skill=args.me_skill)
    if args.scale <= 0 or args.scale > 20:
        raise SystemExit("--scale должен быть от 0.1 до 20")
    return Config(now=datetime.now(timezone.utc), tz_hours=args.tz, scale=args.scale, seed=args.seed, me=me,
                  email_domain=args.email_domain)


# ---------------------------------------------------------------- вывод

def serialize(world: World) -> List[Dict[str, Any]]:
    def convert(value: Any) -> Any:
        if isinstance(value, datetime):
            return value.isoformat()
        if isinstance(value, dict):
            return {k: convert(v) for k, v in value.items()}
        if isinstance(value, list):
            return [convert(v) for v in value]
        return value
    return [{"path": d.path, "data": convert(d.data)} for d in world.docs]


def print_summary(world: World) -> None:
    info = generate.summarize(world)
    print("Документов всего:", info["total"])
    for name, count in sorted(info["documents"].items()):
        print("  {:<20} {}".format(name, count))
    print("Заявки по статусам:", info["request_statuses"])
    print("Активные заявки по городам:", info["active_requests_by_city"])
    print("Матчи по статусам:", info["match_statuses"])
    print("Турниры по статусам:", info["tournament_statuses"])
    print("Оценки в отзывах:", info["review_ratings"])
    print("Больше всего заявок у:", ", ".join("{} ({})".format(n, c) for n, c in info["top_authors"]))


def run_plan(args: argparse.Namespace) -> int:
    world = generate.build_world(config_from(args))
    OUT_DIR.mkdir(exist_ok=True)
    (OUT_DIR / "plan.json").write_text(
        json.dumps(serialize(world), ensure_ascii=False, indent=1), encoding="utf-8")
    (OUT_DIR / "summary.json").write_text(
        json.dumps(generate.summarize(world), ensure_ascii=False, indent=1), encoding="utf-8")
    write_accounts(world, None)
    print_summary(world)
    print("\nВ базу ничего не записано. Данные: {}".format(OUT_DIR / "plan.json"))
    print("Аккаунты для входа (пароль появится при apply): {}".format(OUT_DIR / "accounts.csv"))
    return 0


# ---------------------------------------------------------------- Firebase

class Backend(NamedTuple):
    client: Any                    # Firestore
    auth: Any                      # AuthGateway или None, если аккаунты не нужны


class AuthGateway:
    """Тонкая обёртка над firebase_admin.auth: так её легко подменить в тестах."""

    CHUNK = 1000                   # столько uid за один вызов удаления разрешает Firebase

    def __init__(self, app: Any) -> None:
        from firebase_admin import auth
        self._auth = auth
        self._app = app

    def create(self, uid: str, email: str, password: str, name: str) -> str:
        """'created', а если аккаунт уже был — 'updated' (пароль приводится к новому)."""
        try:
            self._auth.create_user(uid=uid, email=email, password=password, display_name=name,
                                   email_verified=True, app=self._app)
            return "created"
        except (self._auth.UidAlreadyExistsError, self._auth.EmailAlreadyExistsError):
            self._auth.update_user(uid, email=email, password=password, display_name=name,
                                   email_verified=True, app=self._app)
            return "updated"

    def seed_uids(self, uid_prefix: str, email_domain: str) -> List[str]:
        """Только наши аккаунты: и uid начинается с seedu, и почта на тестовом домене."""
        suffix = "@" + email_domain
        return [u.uid for u in self._auth.list_users(app=self._app).iterate_all()
                if u.uid.startswith(uid_prefix) and (u.email or "").endswith(suffix)]

    def delete(self, uids: List[str]) -> int:
        removed = 0
        for start in range(0, len(uids), self.CHUNK):
            result = self._auth.delete_users(uids[start:start + self.CHUNK], app=self._app)
            removed += result.success_count
        return removed


def connect(args: argparse.Namespace, need_auth: bool) -> Backend:
    try:
        import firebase_admin
        from firebase_admin import credentials, firestore
    except ImportError:
        raise SystemExit("Не установлен firebase-admin. Выполните: pip3 install -r requirements.txt")

    key = args.key
    if key:
        key_path = Path(key).expanduser()
        if not key_path.is_file():
            raise SystemExit("Файл ключа не найден: {}".format(key_path))
        key_project = json.loads(key_path.read_text(encoding="utf-8")).get("project_id")
        if key_project != args.project:
            raise SystemExit("Ключ от проекта «{}», а указан «{}». Остановился, чтобы не записать "
                             "данные не туда.".format(key_project, args.project))
        cred = credentials.Certificate(str(key_path))
    else:
        cred = credentials.ApplicationDefault()
    app = firebase_admin.initialize_app(cred, {"projectId": args.project})
    return Backend(firestore.client(app), AuthGateway(app) if need_auth else None)


def confirm(args: argparse.Namespace, action: str) -> None:
    if args.yes:
        return
    print("Действие «{}» в проекте {}. Это настоящая база приложения.".format(action, args.project))
    answer = input("Для продолжения введите id проекта: ").strip()
    if answer != args.project:
        raise SystemExit("Не совпало, ничего не сделано.")


def only_seed(query: Any) -> Any:
    """Условие isSeed == true. Новая форма запроса без предупреждений, если библиотека её знает."""
    try:
        from google.cloud.firestore_v1.base_query import FieldFilter
        return query.where(filter=FieldFilter("isSeed", "==", True))
    except ImportError:
        return query.where("isSeed", "==", True)


def commit_in_batches(client: Any, ops: List[Any], label: str) -> None:
    done = 0
    for start in range(0, len(ops), BATCH_SIZE):
        batch = client.batch()
        for op in ops[start:start + BATCH_SIZE]:
            op(batch)
        batch.commit()
        done += len(ops[start:start + BATCH_SIZE])
        print("\r{}: {}/{}".format(label, done, len(ops)), end="", flush=True)
    print()


# ---------------------------------------------------------------- аккаунты для входа

def make_password() -> str:
    """Случайный пароль: заглавная, строчная, цифра и знак — подходит под любую политику паролей Firebase."""
    rng = secrets.SystemRandom()
    upper, lower = "ABCDEFGHJKLMNPQRSTUVWXYZ", "abcdefghijkmnopqrstuvwxyz"
    digits, symbols = "23456789", "-_!"
    chars = [rng.choice(upper), rng.choice(lower), rng.choice(digits), rng.choice(symbols)]
    chars += [rng.choice(upper + lower + digits) for _ in range(12)]
    rng.shuffle(chars)
    return "".join(chars)


def write_accounts(world: World, password: Optional[str]) -> Path:
    """out/accounts.csv: кто под каким адресом входит. Пароль есть только после apply."""
    OUT_DIR.mkdir(exist_ok=True)
    path = OUT_DIR / "accounts.csv"
    with open(path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["email", "password", "uid", "name", "city", "skill"])
        for person in world.people:
            if person.is_me:
                continue
            writer.writerow([person.email, password or "", person.uid, person.full, person.city, person.skill])
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    return path


def create_accounts(backend: Backend, world: World, password: str) -> Tuple[int, int]:
    created = updated = 0
    people = [p for p in world.people if not p.is_me]
    for index, person in enumerate(people, 1):
        outcome = backend.auth.create(person.uid, person.email, password, person.full)
        if outcome == "created":
            created += 1
        else:
            updated += 1
        print("\rАккаунты: {}/{}".format(index, len(people)), end="", flush=True)
    print()
    return created, updated


# ---------------------------------------------------------------- команды

def run_apply(args: argparse.Namespace) -> int:
    cfg = config_from(args)
    world = generate.build_world(cfg)
    print_summary(world)
    backend = connect(args, need_auth=not args.no_auth)

    existing = list(only_seed(backend.client.collection("users")).limit(1).stream())
    if existing and not args.force:
        raise SystemExit("В базе уже есть тестовые данные. Сначала выполните clean "
                         "(или добавьте --force, если хотите перезаписать).")
    confirm(args, "записать тестовые данные" + ("" if args.no_auth else " и создать аккаунты Authentication"))

    ops = []
    for doc in world.docs:
        ref = backend.client.document(doc.path)
        ops.append(lambda batch, ref=ref, data=doc.data: batch.set(ref, data))
    commit_in_batches(backend.client, ops, "Запись")

    if not args.no_auth:
        password = args.password or os.environ.get("SEED_PASSWORD") or make_password()
        created, updated = create_accounts(backend, world, password)
        path = write_accounts(world, password)
        print("Аккаунты: создано {}, обновлено {}.".format(created, updated))
        print("Вход в приложение: почта из {} и пароль {}".format(path, password))
        sample = [p for p in world.people if not p.is_me][:3]
        for person in sample:
            print("  {}  ({}, {})".format(person.email, person.full, person.city))
    print("Готово. Удалить всё добавленное: python3 seed.py clean --project {} --key <ключ>{}".format(
        args.project, " --me-uid " + cfg.me.uid if cfg.me else ""))
    return 0


def delete_seed_docs(client: Any, query_factory: Any, label: str, dry_run: bool) -> int:
    total = 0
    while True:
        docs = list(query_factory().limit(BATCH_SIZE).stream())
        if not docs:
            break
        total += len(docs)
        if dry_run:
            # Без удаления цикл не закончится, поэтому считаем одной порцией
            more = list(query_factory().stream())
            total = len(more)
            break
        batch = client.batch()
        for doc in docs:
            batch.delete(doc.reference)
        batch.commit()
        print("\r{}: удалено {}".format(label, total), end="", flush=True)
    if total:
        print("\r{}: {} {}".format(label, "найдено" if dry_run else "удалено", total))
    return total


def run_clean(args: argparse.Namespace) -> int:
    backend = connect(args, need_auth=not args.no_auth)
    confirm(args, "удалить тестовые данные (документы с isSeed = true"
            + ("" if args.no_auth else " и аккаунты seedu… на @" + args.email_domain) + ")")
    client = backend.client
    verb = "найдено" if args.dry_run else "удалено"
    total = 0
    if backend.auth:
        uids = backend.auth.seed_uids(AUTH_UID_PREFIX, args.email_domain)
        removed = len(uids) if args.dry_run else (backend.auth.delete(uids) if uids else 0)
        total += removed
        print("аккаунты Authentication: {} {}".format(verb, removed))
    for name in SEED_COLLECTIONS:
        total += delete_seed_docs(
            client, lambda name=name: only_seed(client.collection(name)), name, args.dry_run)
    if args.me_uid:
        total += delete_seed_docs(
            client,
            lambda: only_seed(client.collection("notifications").document(args.me_uid).collection("items")),
            "уведомления", args.dry_run)
    else:
        print("Уведомления владельца удаляются только с --me-uid.")
    print("Итого {}: {}".format(verb, total))
    return 0


# ---------------------------------------------------------------- вход

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Тестовые данные для Spinnet")
    sub = parser.add_subparsers(dest="command", required=True)

    plan = sub.add_parser("plan", help="посчитать данные и показать сводку, база не меняется")
    add_world_arguments(plan)
    plan.set_defaults(func=run_plan)

    apply = sub.add_parser("apply", help="записать данные в Firestore")
    add_world_arguments(apply)
    add_firebase_arguments(apply)
    apply.add_argument("--force", action="store_true", help="записывать, даже если тестовые данные уже есть")
    apply.add_argument("--password", help="Один пароль для всех тестовых аккаунтов (по умолчанию случайный)")
    apply.set_defaults(func=run_apply)

    clean = sub.add_parser("clean", help="удалить все документы с isSeed = true")
    add_firebase_arguments(clean)
    clean.add_argument("--me-uid", help="uid вашего аккаунта: удалит и добавленные вам уведомления")
    clean.add_argument("--email-domain", default="spinnet.test", help="Домен тестовых аккаунтов")
    clean.add_argument("--dry-run", action="store_true", help="только посчитать, ничего не удалять")
    clean.set_defaults(func=run_clean)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

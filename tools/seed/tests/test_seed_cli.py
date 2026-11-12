# -*- coding: utf-8 -*-
"""Проверка записи и удаления без настоящей базы: вместо Firestore — маленькая подделка."""
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import seed  # noqa: E402


class FakeSnapshot:
    def __init__(self, store, path):
        self.reference = FakeRef(store, path)
        self.id = path.split("/")[-1]


class FakeRef:
    def __init__(self, store, path):
        self.store, self.path = store, path


class FakeQuery:
    def __init__(self, store, prefix, flt=None, cap=None):
        self.store, self.prefix, self.flt, self.cap = store, prefix, flt, cap

    def where(self, *args, filter=None):
        field, op, value = (args if args else (filter.field_path, filter.op_string, filter.value))
        assert op == "=="
        return FakeQuery(self.store, self.prefix, (field, value), self.cap)

    def limit(self, n):
        return FakeQuery(self.store, self.prefix, self.flt, n)

    def stream(self):
        depth = self.prefix.count("/") + 2
        paths = [p for p in sorted(self.store)
                 if p.startswith(self.prefix + "/") and p.count("/") + 1 == depth
                 and (self.flt is None or self.store[p].get(self.flt[0]) == self.flt[1])]
        if self.cap is not None:
            paths = paths[: self.cap]
        return iter([FakeSnapshot(self.store, p) for p in paths])


class FakeCollection(FakeQuery):
    def document(self, doc_id):
        return FakeDocument(self.store, self.prefix + "/" + doc_id)


class FakeDocument:
    def __init__(self, store, path):
        self.store, self.path = store, path

    def collection(self, name):
        return FakeCollection(self.store, self.path + "/" + name)


class FakeBatch:
    def __init__(self, store):
        self.store, self.ops = store, []

    def set(self, ref, data):
        assert len(self.ops) < seed.BATCH_SIZE
        self.ops.append(("set", ref.path, data))

    def delete(self, ref):
        assert len(self.ops) < seed.BATCH_SIZE
        self.ops.append(("delete", ref.path, None))

    def commit(self):
        for op, path, data in self.ops:
            if op == "set":
                self.store[path] = data
            else:
                self.store.pop(path, None)


class FakeClient:
    def __init__(self, store):
        self.store = store

    def collection(self, name):
        return FakeCollection(self.store, name)

    def document(self, path):
        return FakeRef(self.store, path)

    def batch(self):
        return FakeBatch(self.store)


class FakeAuth:
    """Подделка AuthGateway: хранит аккаунты в словаре uid → данные."""

    def __init__(self, accounts=None):
        self.accounts = accounts if accounts is not None else {}

    def create(self, uid, email, password, name):
        outcome = "updated" if uid in self.accounts else "created"
        self.accounts[uid] = {"email": email, "password": password, "name": name}
        return outcome

    def seed_uids(self, uid_prefix, email_domain):
        return [u for u, a in self.accounts.items()
                if u.startswith(uid_prefix) and a["email"].endswith("@" + email_domain)]

    def delete(self, uids):
        for uid in uids:
            self.accounts.pop(uid, None)
        return len(uids)


def run(argv, store, auth=None, out_dir=None):
    backend = seed.Backend(FakeClient(store), auth if auth is not None else FakeAuth())
    out = io.StringIO()
    patches = [mock.patch.object(seed, "connect", return_value=backend)]
    if out_dir is not None:
        patches.append(mock.patch.object(seed, "OUT_DIR", Path(out_dir)))
    with contextlib.ExitStack() as stack:
        for p in patches:
            stack.enter_context(p)
        stack.enter_context(contextlib.redirect_stdout(out))
        code = seed.main(argv)
    return code, out.getvalue()


class SeedCommandTests(unittest.TestCase):

    def test_apply_writes_everything_and_clean_removes_only_seed_documents(self):
        real = {
            "users/realUser": {"firstName": "Настоящий"},
            "sparring_requests/realRequest": {"userId": "realUser", "status": "active"},
            "notifications/ME/items/real1": {"title": "настоящее"},
        }
        store = dict(real)
        with tempfile.TemporaryDirectory() as tmp:
            code, _ = run(["apply", "--project", "p", "--yes", "--scale", "0.5",
                           "--me-uid", "ME", "--me-first", "Имя", "--me-last", "Фамилия"], store, out_dir=tmp)
        self.assertEqual(code, 0)
        self.assertGreater(len(store), 500)
        self.assertTrue(all(store[p].get("isSeed") for p in store if p not in real))
        for path, data in real.items():
            self.assertEqual(store[path], data)

        code, text = run(["clean", "--project", "p", "--yes", "--me-uid", "ME", "--dry-run"], store)
        self.assertIn("найдено", text)
        self.assertGreater(len(store), 500)                 # dry-run ничего не удаляет

        code, text = run(["clean", "--project", "p", "--yes", "--me-uid", "ME"], store)
        self.assertEqual(code, 0)
        self.assertEqual(store, real)                       # остались только настоящие документы

    def test_apply_creates_login_accounts_and_saves_credentials(self):
        auth = FakeAuth({"realuid": {"email": "me@gmail.com", "password": "x", "name": "Я"}})
        store = {}
        with tempfile.TemporaryDirectory() as tmp:
            code, text = run(["apply", "--project", "p", "--yes", "--scale", "0.3"], store, auth, tmp)
            self.assertEqual(code, 0)
            users = {p.split("/")[1]: d for p, d in store.items() if p.startswith("users/")}
            seeded = {u: a for u, a in auth.accounts.items() if u != "realuid"}
            self.assertEqual(set(seeded), set(users))                      # аккаунт на каждого игрока
            passwords = {a["password"] for a in seeded.values()}
            self.assertEqual(len(passwords), 1)                            # один пароль на всех
            password = passwords.pop()
            self.assertGreaterEqual(len(password), 14)
            self.assertTrue(any(c.isupper() for c in password) and any(c.islower() for c in password)
                            and any(c.isdigit() for c in password))
            for uid, account in seeded.items():
                self.assertEqual(account["email"], users[uid]["email"])    # почта в профиле совпадает с входом
                self.assertTrue(account["email"].endswith("@spinnet.test"))
            rows = (Path(tmp) / "accounts.csv").read_text(encoding="utf-8").splitlines()
            self.assertEqual(rows[0], "email,password,uid,name,city,skill")
            self.assertEqual(len(rows) - 1, len(users))
            self.assertIn(password, rows[1])
            self.assertIn(password, text)

    def test_own_password_and_no_auth_flag(self):
        auth = FakeAuth()
        with tempfile.TemporaryDirectory() as tmp:
            run(["apply", "--project", "p", "--yes", "--scale", "0.3", "--password", "My-Test-Pass1"], {}, auth, tmp)
            self.assertEqual({a["password"] for a in auth.accounts.values()}, {"My-Test-Pass1"})
        auth2 = FakeAuth()
        store = {}
        with tempfile.TemporaryDirectory() as tmp:
            run(["apply", "--project", "p", "--yes", "--scale", "0.3", "--no-auth"], store, auth2, tmp)
        self.assertEqual(auth2.accounts, {})
        self.assertTrue(any(p.startswith("users/") for p in store))

    def test_clean_removes_only_seed_accounts(self):
        auth = FakeAuth({
            "realuid": {"email": "me@gmail.com", "password": "x", "name": "Я"},
            "seedxsomething": {"email": "a@spinnet.test", "password": "x", "name": "не наш префикс"},
            "seedu9999": {"email": "somebody@gmail.com", "password": "x", "name": "не наш домен"},
        })
        store = {}
        with tempfile.TemporaryDirectory() as tmp:
            run(["apply", "--project", "p", "--yes", "--scale", "0.3"], store, auth, tmp)
            self.assertGreater(len(auth.accounts), 20)
            code, text = run(["clean", "--project", "p", "--yes", "--dry-run"], store, auth, tmp)
            self.assertGreater(len(auth.accounts), 20)                     # dry-run ничего не удаляет
            self.assertIn("аккаунты Authentication: найдено", text)
            code, text = run(["clean", "--project", "p", "--yes"], store, auth, tmp)
        self.assertEqual(set(auth.accounts), {"realuid", "seedxsomething", "seedu9999"})
        self.assertEqual(store, {})

    def test_repeated_apply_with_force_updates_existing_accounts(self):
        auth = FakeAuth()
        with tempfile.TemporaryDirectory() as tmp:
            run(["apply", "--project", "p", "--yes", "--scale", "0.3"], {}, auth, tmp)
            first = {a["password"] for a in auth.accounts.values()}
            code, text = run(["apply", "--project", "p", "--yes", "--scale", "0.3"], {}, auth, tmp)
        self.assertIn("обновлено", text)
        self.assertNotEqual({a["password"] for a in auth.accounts.values()}, first)

    def test_apply_refuses_when_seed_data_already_exists(self):
        store = {}
        tmp = tempfile.mkdtemp()
        run(["apply", "--project", "p", "--yes", "--scale", "0.3"], store, out_dir=tmp)
        before = dict(store)
        with self.assertRaises(SystemExit) as caught:
            run(["apply", "--project", "p", "--yes", "--scale", "0.3"], store, out_dir=tmp)
        self.assertIn("clean", str(caught.exception))
        self.assertEqual(store, before)

    def test_clean_without_owner_leaves_owner_notifications_and_says_so(self):
        store = {}
        tmp = tempfile.mkdtemp()
        run(["apply", "--project", "p", "--yes", "--scale", "0.3",
             "--me-uid", "ME", "--me-first", "А", "--me-last", "Б"], store, out_dir=tmp)
        code, text = run(["clean", "--project", "p", "--yes"], store, out_dir=tmp)
        self.assertIn("--me-uid", text)
        self.assertTrue(all(p.startswith("notifications/ME/items/") for p in store))
        self.assertGreater(len(store), 0)

    def test_owner_flags_are_validated(self):
        with self.assertRaises(SystemExit):
            seed.main(["plan", "--me-uid", "ME"])
        with self.assertRaises(SystemExit):
            seed.main(["plan", "--scale", "0"])

    def test_plan_writes_json_and_nothing_else(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(seed, "OUT_DIR", Path(tmp)):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = seed.main(["plan", "--scale", "0.3"])
            self.assertEqual(code, 0)
            plan = json.loads((Path(tmp) / "plan.json").read_text(encoding="utf-8"))
            self.assertGreater(len(plan), 100)
            self.assertIn("В базу ничего не записано", out.getvalue())

    def test_key_from_another_project_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            key = Path(tmp) / "key.json"
            key.write_text(json.dumps({"project_id": "other-project"}), encoding="utf-8")
            args = seed.build_parser().parse_args(["clean", "--project", "spinnet-30103", "--key", str(key), "--yes"])
            fake_admin = mock.MagicMock()
            with mock.patch.dict(sys.modules, {"firebase_admin": fake_admin,
                                               "firebase_admin.credentials": fake_admin.credentials,
                                               "firebase_admin.firestore": fake_admin.firestore}):
                with self.assertRaises(SystemExit) as caught:
                    seed.connect(args, need_auth=False)
            self.assertIn("other-project", str(caught.exception))

    def test_wrong_project_confirmation_stops_before_any_write(self):
        store = {}
        args = seed.build_parser().parse_args(["apply", "--project", "spinnet-30103", "--scale", "0.3"])
        with mock.patch.object(seed, "connect", return_value=seed.Backend(FakeClient(store), FakeAuth())), \
                mock.patch("builtins.input", return_value="не тот проект"), \
                contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit):
                seed.run_apply(args)
        self.assertEqual(store, {})


class AuthGatewayTests(unittest.TestCase):
    """Проверяем обращения к firebase_admin.auth: имена аргументов, замена пароля, пачки удаления."""

    def gateway(self):
        auth = mock.MagicMock()
        auth.UidAlreadyExistsError = type("UidAlreadyExistsError", (Exception,), {})
        auth.EmailAlreadyExistsError = type("EmailAlreadyExistsError", (Exception,), {})
        gateway = seed.AuthGateway.__new__(seed.AuthGateway)
        gateway._auth, gateway._app = auth, "APP"
        return gateway, auth

    def test_create_passes_uid_email_password_and_name(self):
        gateway, auth = self.gateway()
        self.assertEqual(gateway.create("seedu0001", "a.b@spinnet.test", "Pw", "А Б"), "created")
        auth.create_user.assert_called_once_with(uid="seedu0001", email="a.b@spinnet.test", password="Pw",
                                                 display_name="А Б", email_verified=True, app="APP")

    def test_existing_account_gets_new_password(self):
        gateway, auth = self.gateway()
        auth.create_user.side_effect = auth.UidAlreadyExistsError()
        self.assertEqual(gateway.create("seedu0001", "a.b@spinnet.test", "Pw2", "А Б"), "updated")
        auth.update_user.assert_called_once_with("seedu0001", email="a.b@spinnet.test", password="Pw2",
                                                 display_name="А Б", email_verified=True, app="APP")

    def test_seed_uids_need_both_prefix_and_domain(self):
        gateway, auth = self.gateway()
        users = [mock.Mock(uid="seedu0001", email="a@spinnet.test"), mock.Mock(uid="seedu0002", email="a@gmail.com"),
                 mock.Mock(uid="other", email="b@spinnet.test"), mock.Mock(uid="seedu0003", email=None)]
        auth.list_users.return_value.iterate_all.return_value = iter(users)
        self.assertEqual(gateway.seed_uids("seedu", "spinnet.test"), ["seedu0001"])

    def test_delete_is_split_into_chunks_of_1000(self):
        gateway, auth = self.gateway()
        auth.delete_users.side_effect = lambda uids, app=None: mock.Mock(success_count=len(uids))
        self.assertEqual(gateway.delete(["u{}".format(i) for i in range(2500)]), 2500)
        self.assertEqual([len(c.args[0]) for c in auth.delete_users.call_args_list], [1000, 1000, 500])


if __name__ == "__main__":
    unittest.main()

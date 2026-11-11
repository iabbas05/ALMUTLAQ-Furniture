import copy
from http.cookiejar import CookieJar
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from urllib.error import HTTPError
from urllib.request import Request, build_opener, ProxyHandler, HTTPCookieProcessor

from room_protocol import ValidationError, validate_room, initial_room
from showroom_service import ShowroomStore, ShowroomServer, ConflictError
from glb_import import decode_glb, ModelError

ROOT = Path(__file__).resolve().parent
TEMP = ROOT / "_testtmp"
TEMP.mkdir(exist_ok=True)
assert TEMP.resolve().parent == ROOT

class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=TEMP)
        self.store = ShowroomStore(self.temp.name)
    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def test_width_changes_do_not_scale_product(self):
        old = self.store.snapshot()
        new = self.store.update({**old, "expectedRevision": old["revision"],
                                 "room": {**old["room"], "width": 5}})
        self.assertEqual(new["room"]["width"], 5)
        self.assertEqual(new["items"][0]["position"], old["items"][0]["position"])
        self.assertEqual(self.store.products["factory:10_14_3"]["dimensions"],
                         dict(width=2.1, depth=1.03, height=1.0))
        self.assertEqual(new["appliedRevision"], 0)

    def test_revision_and_ack_require_current_scene(self):
        old = self.store.snapshot()
        new = self.store.update({**old, "expectedRevision": old["revision"]})
        with self.assertRaises(ConflictError):
            self.store.update({**old, "expectedRevision": old["revision"]})
        with self.assertRaises(ConflictError):
            self.store.acknowledge(dict(sessionId=old["sessionId"], revision=old["revision"]))
        applied = self.store.acknowledge(dict(sessionId=new["sessionId"], revision=new["revision"]))
        self.assertEqual(applied["appliedRevision"], applied["revision"])

    def test_pair_code_single_use_and_device_revocation(self):
        code = self.store.pairing()["code"]
        token = self.store.pair({"code": code})["token"]
        self.assertTrue(self.store.device_allowed(token))
        with self.assertRaises(ValidationError):
            self.store.pair({"code": code})
        self.store.revoke_devices()
        self.assertFalse(self.store.device_allowed(token))

    def test_invalid_room_numbers_and_boolean_rejected(self):
        for value in [True, float("nan"), float("inf"), -1, 0, 26, "4"]:
            with self.subTest(value=value), self.assertRaises(ValidationError):
                room = initial_room()
                room["room"]["width"] = value
                validate_room(room, self.store.products)

    def test_rotation_validates_entire_footprint(self):
        room = initial_room()
        room["items"][0].update(position=dict(x=.6, z=1.2), rotationY=0)
        with self.assertRaises(ValidationError):
            validate_room(room, self.store.products)
        room["items"][0]["rotationY"] = 90
        self.assertEqual(validate_room(room, self.store.products)["items"][0]["rotationY"], 90)

    def test_duplicate_items_unknown_skus_and_openings_rejected(self):
        a = initial_room()
        a["items"].append(copy.deepcopy(a["items"][0]))
        with self.assertRaises(ValidationError):
            validate_room(a, self.store.products)
        a = initial_room()
        a["items"][0]["productId"] = "factory:missing"
        with self.assertRaises(ValidationError):
            validate_room(a, self.store.products)
        a = initial_room()
        a["openings"].append(copy.deepcopy(a["openings"][0]))
        with self.assertRaises(ValidationError):
            validate_room(a, self.store.products)

    def test_personal_data_never_enters_room_document(self):
        room = {**initial_room(), "name": "TEST CUSTOMER", "phone": "00000000"}
        clean = validate_room(room, self.store.products)
        self.assertNotIn("phone", json.dumps(clean))
        self.assertNotIn("TEST CUSTOMER", json.dumps(clean))
        with self.assertRaises(ValidationError):
            self.store.save_customer(dict(name="TEST CUSTOMER", phone="00000000", consent=False))
        saved = self.store.save_customer(dict(name="TEST CUSTOMER", phone="00000000", consent=True))
        self.assertEqual(len(self.store.customers("0000")), 1)
        current = self.store.snapshot()
        restored = self.store.restore_customer(saved["id"], current["revision"])
        self.assertNotEqual(restored["sessionId"], current["sessionId"])
        self.assertNotIn("phone", json.dumps(restored))

    def test_state_survives_restart_without_fake_online_status(self):
        old = self.store.snapshot()
        current = self.store.update({**old, "expectedRevision": old["revision"],
                                    "room": {**old["room"], "width": 5}})
        self.store.close()
        self.store = ShowroomStore(self.temp.name)
        self.assertEqual(self.store.snapshot(), current)
        self.assertEqual(self.store.last_ack, 0)

    def test_restart_requires_a_fresh_device_ack(self):
        state = self.store.snapshot()
        self.store.acknowledge(dict(sessionId=state["sessionId"], revision=state["revision"]))
        self.store.close()
        self.store = ShowroomStore(self.temp.name)
        self.assertEqual(self.store.snapshot()["revision"], state["revision"])
        self.assertEqual(self.store.snapshot()["appliedRevision"], 0)

    def test_arabic_phone_digits_find_the_saved_design(self):
        self.store.save_customer(dict(name="TEST CUSTOMER", phone="٠٠٠٠٠٠٠٠", consent=True))
        self.assertEqual(len(self.store.customers("00000000")), 1)

    def test_retention_purges_only_expired_rows_and_persists_policy(self):
        old = self.store.save_customer(dict(name="TEST OLD", phone="00000000", consent=True))
        fresh = self.store.save_customer(dict(name="TEST FRESH", phone="00000001", consent=True))
        self.store.db.execute("UPDATE customers SET saved_at=? WHERE id=?", (time.time()-31*86400, old["id"]))
        self.store.db.commit()
        self.store.close()
        self.store = ShowroomStore(self.temp.name)
        self.assertEqual([r['id'] for r in self.store.customers('TEST')], [fresh['id']])
        self.store.privacy(7)
        self.store.close()
        self.store = ShowroomStore(self.temp.name)
        self.assertEqual(self.store.privacy()['retentionDays'], 7)
        for invalid in (True, 0, 366, '30'):
            with self.assertRaises(ValidationError):
                self.store.privacy(invalid)

    def test_export_is_one_record_and_contains_saved_room(self):
        a = self.store.save_customer(dict(name="TEST A", phone="00000000", consent=True))
        self.store.save_customer(dict(name="TEST B", phone="00000001", consent=True))
        exported = self.store.export_customer(a['id'])
        self.assertEqual(exported['customer']['name'], 'TEST A')
        self.assertEqual(exported['customer']['document']['room']['width'], 4)
        self.assertNotIn('TEST B', json.dumps(exported))
        with self.assertRaises(ValidationError):
            self.store.export_customer('missing')

    def test_glb_import_and_reject_stretched_dimensions(self):
        blob = (ROOT.parent / "assets/london-10_14_3.glb").read_bytes()
        mesh = decode_glb(blob, dict(width=2.1, depth=1.03, height=1))
        self.assertEqual(len(mesh["parts"]), 14)
        with self.assertRaises(ModelError):
            decode_glb(blob, dict(width=3, depth=1.03, height=1))
        with self.assertRaises(ModelError):
            decode_glb(blob[:-4], dict(width=2.1, depth=1.03, height=1))

    def test_publish_is_explicit_and_does_not_replace_active_version(self):
        original = self.store.snapshot()["items"][0]["modelVersion"]
        blob = (ROOT.parent / "assets/london-10_14_3.glb").read_bytes()
        draft = self.store.upload_model("factory:10_14_3", blob)["draftVersion"]
        with self.assertRaises(ValidationError):
            self.store.publish(dict(id="factory:10_14_3", modelVersion=draft, visuallyApproved=False))
        self.store.publish(dict(id="factory:10_14_3", modelVersion=draft, visuallyApproved=True))
        self.assertEqual(self.store.snapshot()["items"][0]["modelVersion"], original)
        self.assertIn(original, self.store.products["factory:10_14_3"]["versions"])

    def test_published_dimensions_cannot_be_overwritten(self):
        p = copy.deepcopy(self.store.products["factory:10_14_3"])
        p["dimensions"]["width"] = 3
        with self.assertRaises(ValidationError):
            self.store.save_product(p)

class HttpTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=TEMP)
        self.store = ShowroomStore(self.temp.name)
        self.server = ShowroomServer(("127.0.0.1", 0), self.store)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f"http://127.0.0.1:{self.server.server_port}"
        self.client = build_opener(ProxyHandler({}), HTTPCookieProcessor(CookieJar()))
        self.csrf = None
    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.store.close()
        self.temp.cleanup()
    def call(self, path, body=None, headers=None):
        headers = {"Content-Type": "application/json", **(headers or {})}
        if self.csrf:
            headers["X-Showroom-CSRF"] = self.csrf
        request = Request(self.url+path, data=None if body is None else json.dumps(body).encode(), headers=headers)
        try:
            with self.client.open(request, timeout=3) as response:
                return response.status, json.load(response)
        except HTTPError as response:
            return response.code, json.load(response)
    def bootstrap(self):
        status, value = self.call("/api/bootstrap")
        self.assertEqual(status, 200)
        self.csrf = value["csrf"]

    def test_staff_cookie_and_csrf_required(self):
        self.assertEqual(self.call("/api/state")[0], 401)
        self.bootstrap()
        self.assertEqual(self.call("/api/state")[0], 200)
        csrf, self.csrf = self.csrf, None
        self.assertEqual(self.call("/api/pairing", {})[0], 403)
        self.csrf = csrf
        self.assertEqual(self.call("/api/pairing", {})[0], 200)

    def test_foreign_host_and_origin_rejected(self):
        self.assertEqual(self.call("/api/health", headers={"Host":"attacker.example"})[0], 403)
        self.bootstrap()
        self.assertEqual(self.call("/api/pairing", {}, {"Origin":"https://attacker.example"})[0], 403)

    def test_adb_reverse_loopback_host_alias_is_allowed(self):
        self.assertEqual(self.call("/api/health", headers={"Host":"127.0.0.1:8766"})[0], 200)

    def test_send_requires_ack_and_stale_edit_returns_conflict(self):
        self.bootstrap()
        _, room = self.call("/api/state")
        status, sent = self.call("/api/state", {**room, "expectedRevision":room["revision"]})
        self.assertEqual(status, 200)
        self.assertEqual(sent["appliedRevision"], 0)
        self.assertEqual(self.call("/api/state", {**room, "expectedRevision":room["revision"]})[0], 409)

    def test_device_cannot_read_customer_records(self):
        self.bootstrap()
        _, code = self.call("/api/pairing", {})
        outsider = build_opener(ProxyHandler({}))
        request = Request(self.url+"/api/pair", data=json.dumps({"code":code["code"]}).encode(),
                          headers={"Content-Type":"application/json"})
        with outsider.open(request) as response:
            token = json.load(response)["token"]
        request = Request(self.url+"/api/customers", headers={"Authorization":"Bearer "+token})
        with self.assertRaises(HTTPError) as rejected:
            outsider.open(request)
        self.assertEqual(rejected.exception.code, 403)
        for path, body in [('/api/privacy', {'retentionDays': 1}), ('/api/export-customer', {'id': 'missing'})]:
            request = Request(self.url+path, data=json.dumps(body).encode(),
                headers={"Authorization": "Bearer "+token, "Content-Type": "application/json"})
            with self.assertRaises(HTTPError) as rejected:
                outsider.open(request)
            self.assertEqual(rejected.exception.code, 403)

if __name__ == "__main__":
    unittest.main()

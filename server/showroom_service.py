"""Local-only staff service. No third-party Python packages or public network listener."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs
from http.cookies import SimpleCookie
import argparse
import hashlib
import json
import os
import re
import secrets
import sqlite3
import threading
import time
import uuid

from room_protocol import ValidationError, initial_room, validate_room, detached, number
from glb_import import decode_glb, ModelError

ROOT = Path(__file__).resolve().parent
MAX_JSON = 256 * 1024

class ConflictError(ValueError):
    pass

class ShowroomStore:
    def __init__(self, directory, retention_days=None):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.lock = threading.RLock()
        self.db = sqlite3.connect(self.directory / "showroom.sqlite3", check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.executescript("""
          PRAGMA journal_mode=WAL;
          CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS customers (id TEXT PRIMARY KEY, name TEXT NOT NULL,
            phone TEXT NOT NULL, consent_at REAL NOT NULL, saved_at REAL NOT NULL, document TEXT NOT NULL);
          CREATE INDEX IF NOT EXISTS customer_phone ON customers(phone);
          CREATE TABLE IF NOT EXISTS devices (token_hash TEXT PRIMARY KEY, created_at REAL NOT NULL);
          CREATE TABLE IF NOT EXISTS products (id TEXT PRIMARY KEY, document TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS categories (id TEXT PRIMARY KEY, name TEXT NOT NULL);
          INSERT OR IGNORE INTO categories VALUES ('seating', 'الكنب والكراسي');
        """)
        saved_policy = self.db.execute("SELECT value FROM settings WHERE key='retention_days'").fetchone()
        days = retention_days if retention_days is not None else (int(saved_policy["value"]) if saved_policy else 30)
        if type(days) is not int or not 1 <= days <= 365:
            self.db.close()
            raise ValidationError("Retention must be 1 to 365 days")
        self.retention_days = days
        self.db.execute("INSERT OR REPLACE INTO settings VALUES ('retention_days',?)", (str(days),))
        self.db.execute("DELETE FROM customers WHERE saved_at < ?", (time.time() - days * 86400,))
        self.db.commit()
        self.products = self._products()
        raw = self.db.execute("SELECT value FROM settings WHERE key='snapshot'").fetchone()
        if raw:
            self.state = json.loads(raw["value"])
            # A previous process's ACK does not establish a live device connection.
            self.state["appliedRevision"] = 0
        else:
            self.state = {**validate_room(initial_room(), self.products), "sessionId": str(uuid.uuid4()),
                          "revision": 1, "appliedRevision": 0}
            self._save_state()
        self.last_ack = 0.0
        self.pair_code, self.pair_expires = None, 0.0
        self.pair_failures = []
        self.staff_cookie = secrets.token_urlsafe(32)
        self.csrf = secrets.token_urlsafe(32)

    def _products(self):
        saved = self.db.execute("SELECT id,document FROM products").fetchall()
        if saved:
            return {row["id"]: json.loads(row["document"]) for row in saved}
        specs = [
            ("factory:10_14_3", "10_14_3", "London three-seater", "كنبة لندن، ثلاثة مقاعد", 2.1, 1.03, 1.0, "london-10_14_3"),
            ("factory:6_14_5", "6_14_5", "London chair", "كرسي لندن", .84, .95, .94, "london-6_14_5"),
        ]
        products = {}
        models = self.directory / "models"
        models.mkdir(exist_ok=True)
        for key, sku, name, arabic, w, d, h, filename in specs:
            path = ROOT / "models" / (filename + ".mesh.json")
            checksum = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
            if checksum:
                (models / (checksum + ".mesh.json")).write_bytes(path.read_bytes())
            version = checksum or "demo-missing"
            url = "/models/" + version + ".mesh.json"
            products[key] = dict(id=key, sku=sku, name=name, arabic=arabic,
                dimensions=dict(width=w, depth=d, height=h), status="published" if checksum else "unavailable",
                modelVersion=version, modelUrl=url, modelSha256=checksum, category="seating",
                versions={version: dict(modelUrl=url, sha256=checksum)},
                reconstructed=True, visuallyApproved=False)
            self.db.execute("INSERT INTO products VALUES (?,?)", (key, json.dumps(products[key])))
        self.db.commit()
        return products

    def save_product(self, data):
        with self.lock:
            key, name, arabic = data.get("id"), data.get("name"), data.get("arabic")
            if not isinstance(key, str) or not re.fullmatch(r"(?:factory|cityw):[A-Za-z0-9_-]{1,64}", key):
                raise ValidationError("Use factory:SKU or cityw:SKU")
            if not all(isinstance(n, str) and 1 <= len(n.strip()) <= 150 for n in (name, arabic)):
                raise ValidationError("Enter product names")
            category = data.get("category")
            if not isinstance(category, str) or not self.db.execute("SELECT 1 FROM categories WHERE id=?", (category,)).fetchone():
                raise ValidationError("Choose a category")
            raw = data.get("dimensions")
            if not isinstance(raw, dict):
                raise ValidationError("Enter dimensions in metres")
            dimensions = {k: number(raw.get(k), .05, 10, k) for k in ("width", "depth", "height")}
            previous = self.products.get(key)
            if previous and previous.get("versions") and dimensions != previous["dimensions"]:
                raise ValidationError("Published dimensions are immutable. Use a separate SKU or variant.")
            value = {**(previous or {}), "id": key, "sku": key.split(":",1)[1],
                     "name": name.strip(), "arabic": arabic.strip(), "dimensions": dimensions,
                     "category": category, "status": previous["status"] if previous else "draft",
                     "versions": previous.get("versions", {}) if previous else {},
                     "modelVersion": previous.get("modelVersion") if previous else None}
            self._put_product(value)
            return detached(value)

    def _put_product(self, value):
        self.db.execute("INSERT OR REPLACE INTO products VALUES (?,?)", (value["id"], json.dumps(value, allow_nan=False)))
        self.db.commit()
        self.products[value["id"]] = value

    def save_category(self, data):
        key, name = data.get("id"), data.get("name")
        if not isinstance(key, str) or not re.fullmatch(r"[a-z0-9_-]{1,40}", key):
            raise ValidationError("Category ID must use English letters, digits, or underscore")
        if not isinstance(name, str) or not 1 <= len(name.strip()) <= 100:
            raise ValidationError("Enter a category name")
        with self.lock:
            self.db.execute("INSERT OR REPLACE INTO categories VALUES (?,?)", (key, name.strip()))
            self.db.commit()
            return {"saved": True}

    def categories(self):
        with self.lock:
            return [dict(r) for r in self.db.execute("SELECT * FROM categories ORDER BY name").fetchall()]

    def upload_model(self, key, blob):
        with self.lock:
            if key not in self.products:
                raise ValidationError("Create the product before uploading")
            product = detached(self.products[key])
            runtime = decode_glb(blob, product["dimensions"])
            encoded = json.dumps(runtime, allow_nan=False, separators=(",", ":")).encode()
            model_hash = hashlib.sha256(encoded).hexdigest()
            glb_hash = hashlib.sha256(blob).hexdigest()
            directory = self.directory / "models"
            directory.mkdir(exist_ok=True)
            (directory / (model_hash + ".mesh.json")).write_bytes(encoded)
            (directory / (glb_hash + ".glb")).write_bytes(blob)
            product["versions"][model_hash] = dict(
                modelUrl="/models/" + model_hash + ".mesh.json", sha256=model_hash,
                glbUrl="/models/" + glb_hash + ".glb", glbSha256=glb_hash)
            product["draftVersion"] = model_hash
            self._put_product(product)
            return {"draftVersion": model_hash, "requiresApproval": True}

    def publish(self, data):
        with self.lock:
            product = self.products.get(data.get("id"))
            version = data.get("modelVersion")
            if not product or version not in product["versions"] or data.get("visuallyApproved") is not True:
                raise ValidationError("Preview the model and confirm visual approval before publishing")
            product = detached(product)
            meta = product["versions"][version]
            product.update(status="published", modelVersion=version, modelUrl=meta["modelUrl"],
                           modelSha256=meta["sha256"], visuallyApproved=True)
            self._put_product(product)
            return detached(product)

    def _save_state(self):
        self.db.execute("INSERT OR REPLACE INTO settings VALUES ('snapshot',?)",
                        (json.dumps(self.state, allow_nan=False),))
        self.db.commit()

    def snapshot(self):
        with self.lock:
            return detached(self.state)

    def update(self, data, new_session=False):
        with self.lock:
            expected = data.get("expectedRevision")
            if type(expected) is not int or expected != self.state["revision"]:
                raise ConflictError("Room changed. Reload before sending.")
            clean = validate_room(data, self.products)
            revision = self.state["revision"] + 1
            self.state = {**clean, "sessionId": str(uuid.uuid4()) if new_session else self.state["sessionId"],
                          "revision": revision, "appliedRevision": 0}
            self.last_ack = 0
            self._save_state()
            return detached(self.state)

    def acknowledge(self, data):
        with self.lock:
            if (type(data.get("revision")) is not int or data["revision"] != self.state["revision"]
                    or data.get("sessionId") != self.state["sessionId"]):
                raise ConflictError("Only the current applied scene can be acknowledged")
            self.state["appliedRevision"] = data["revision"]
            self.last_ack = time.time()
            self._save_state()
            return detached(self.state)

    def pairing(self):
        with self.lock:
            self.pair_code = f"{secrets.randbelow(1000000):06d}"
            self.pair_expires = time.time() + 120
            return dict(code=self.pair_code, expiresIn=120)

    def pair(self, data):
        with self.lock:
            now = time.time()
            self.pair_failures = [t for t in self.pair_failures if now - t < 60]
            if len(self.pair_failures) >= 5:
                raise ValidationError("Too many attempts. Wait a minute.")
            code = data.get("code")
            if (not isinstance(code, str) or not self.pair_code or now > self.pair_expires
                    or not secrets.compare_digest(code, self.pair_code)):
                self.pair_failures.append(now)
                raise ValidationError("Pairing code expired or incorrect")
            token = secrets.token_urlsafe(32)
            self.db.execute("INSERT INTO devices VALUES (?,?)",
                (hashlib.sha256(token.encode()).hexdigest(), now))
            self.db.commit()
            self.pair_code = None
            return dict(token=token)

    def device_allowed(self, token):
        with self.lock:
            digest = hashlib.sha256(token.encode()).hexdigest()
            return self.db.execute("SELECT 1 FROM devices WHERE token_hash=?", (digest,)).fetchone() is not None

    def revoke_devices(self):
        with self.lock:
            self.db.execute("DELETE FROM devices")
            self.db.commit()
            self.pair_code = None

    def save_customer(self, data):
        if data.get("consent") is not True:
            raise ValidationError("Customer permission is required before saving")
        name, phone = data.get("name"), data.get("phone")
        if not isinstance(name, str) or not 2 <= len(name.strip()) <= 120:
            raise ValidationError("Enter the customer name")
        if not isinstance(phone, str):
            raise ValidationError("Enter a valid phone number")
        phone = phone.translate(str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789"))
        phone = re.sub(r"[\s()-]", "", phone.strip())
        if not re.fullmatch(r"\+?[0-9]{8,15}", phone):
            raise ValidationError("Phone number must have 8 to 15 digits")
        with self.lock:
            key, now = str(uuid.uuid4()), time.time()
            self.db.execute("INSERT INTO customers VALUES (?,?,?,?,?,?)",
                (key, name.strip(), phone, now, now, json.dumps(self.state)))
            self.db.commit()
            return dict(id=key, saved=True)

    def customers(self, query):
        with self.lock:
            rows = self.db.execute(
                "SELECT id,name,phone,saved_at FROM customers WHERE instr(lower(name),lower(?))>0 "
                "OR instr(phone,?)>0 ORDER BY saved_at DESC LIMIT 50", (query, query)).fetchall()
            return [dict(row) for row in rows]

    def privacy(self, days=None):
        with self.lock:
            if days is not None:
                if type(days) is not int or not 1 <= days <= 365:
                    raise ValidationError("Retention must be 1 to 365 days")
                self.retention_days = days
                self.db.execute("INSERT OR REPLACE INTO settings VALUES ('retention_days',?)", (str(days),))
                self.db.execute("DELETE FROM customers WHERE saved_at < ?", (time.time() - days * 86400,))
                self.db.commit()
            return dict(retentionDays=self.retention_days, localOnly=True)

    def export_customer(self, key):
        with self.lock:
            row = self.db.execute("SELECT * FROM customers WHERE id=?", (key,)).fetchone()
            if not row:
                raise ValidationError("Saved design not found")
            value = dict(row)
            value["document"] = json.loads(value["document"])
            return {"exportVersion": 1, "customer": value, "exportedAt": time.time()}

    def restore_customer(self, key, expected):
        with self.lock:
            row = self.db.execute("SELECT document FROM customers WHERE id=?", (key,)).fetchone()
            if not row:
                raise ValidationError("Saved design not found")
            data = json.loads(row["document"])
            data["expectedRevision"] = expected
            return self.update(data, new_session=True)

    def close(self):
        self.db.close()

class ShowroomServer(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, store):
        super().__init__(address, Handler)
        self.store = store

class Handler(BaseHTTPRequestHandler):
    server_version = "ShowroomLocal/0.8"
    def log_message(self, fmt, *args):
        pass

    def host_ok(self):
        # Prevent browser DNS rebinding to this local staff panel.
        return self.headers.get("Host") in (
            f"127.0.0.1:{self.server.server_port}", f"localhost:{self.server.server_port}",
            "127.0.0.1:8766", "localhost:8766")

    def origin_ok(self):
        return self.headers.get("Origin") in (None,
            f"http://127.0.0.1:{self.server.server_port}", f"http://localhost:{self.server.server_port}")

    def staff(self):
        cookie = SimpleCookie()
        try:
            cookie.load(self.headers.get("Cookie", ""))
            token = cookie.get("showroom_staff")
            return token is not None and secrets.compare_digest(token.value, self.server.store.staff_cookie)
        except Exception:
            return False

    def device(self):
        auth = self.headers.get("Authorization", "")
        return auth.startswith("Bearer ") and self.server.store.device_allowed(auth[7:])

    def send(self, value, status=200, mime="application/json; charset=utf-8", cookie=False):
        body = value if isinstance(value, bytes) else json.dumps(value, ensure_ascii=False, allow_nan=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy",
            "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' https://thefactoryfurniture.com data:; frame-ancestors 'none'; base-uri 'none'")
        if cookie:
            self.send_header("Set-Cookie",
                "showroom_staff=" + self.server.store.staff_cookie + "; Path=/; HttpOnly; SameSite=Strict")
        self.end_headers()
        self.wfile.write(body)

    def read_json(self):
        if self.headers.get_content_type() != "application/json":
            raise ValidationError("Use application/json")
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= MAX_JSON:
                raise ValidationError("Invalid request size")
            body = self.rfile.read(length)
            value = json.loads(body, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
            if not isinstance(value, dict):
                raise ValidationError("Expected an object")
            return value
        except (ValueError, UnicodeDecodeError) as error:
            raise ValidationError("Invalid JSON") from error

    def do_GET(self):
        if not self.host_ok():
            return self.send({"error": "Local host required"}, 403)
        url = urlsplit(self.path)
        path = url.path
        if path == "/api/health":
            return self.send(dict(ok=True, application="almutlaq-showroom", protocol=2, version="0.8.1"))
        if path == "/api/bootstrap":
            return self.send(dict(csrf=self.server.store.csrf, localOnly=True), cookie=True)
        static = {"/": "staff.html", "/staff.js": "staff.js", "/room-3d.js": "room-3d.js", "/staff.css": "staff.css"}
        if path in static:
            file = ROOT / static[path]
            mime = "text/html; charset=utf-8" if path == "/" else (
                "text/javascript; charset=utf-8" if path.endswith(".js") else "text/css; charset=utf-8")
            return self.send(file.read_bytes(), mime=mime)
        is_staff = self.staff()
        if not is_staff and not self.device():
            return self.send({"error": "Pair the device first"}, 401)
        if path == "/api/state":
            return self.send(self.server.store.snapshot())
        if path == "/api/catalogue":
            return self.send({"products": list(self.server.store.products.values()), "categories": self.server.store.categories()})
        if path == "/api/model-version":
            query = parse_qs(url.query)
            with self.server.store.lock:
                product = self.server.store.products.get(query.get("id", [""])[0])
                version = query.get("version", [""])[0]
                metadata = product.get("versions", {}).get(version) if product else None
                if metadata:
                    return self.send({**metadata, "dimensions": product["dimensions"]})
            return self.send({"error": "Model version not found"}, 404)
        if path.startswith("/models/"):
            name = path[len("/models/"):]
            if not re.fullmatch(r"[a-f0-9]{64}(?:\.mesh\.json|\.glb)", name):
                return self.send({"error": "Not found"}, 404)
            file = self.server.store.directory / "models" / name
            if not file.is_file():
                return self.send({"error": "Not found"}, 404)
            return self.send(file.read_bytes(), mime="model/gltf-binary" if name.endswith(".glb") else "application/json")
        if not is_staff:
            return self.send({"error": "Staff access required"}, 403)
        if path == "/api/status":
            state = self.server.store.snapshot()
            return self.send(dict(revision=state["revision"], appliedRevision=state["appliedRevision"],
                headsetSeenSecondsAgo=None if not self.server.store.last_ack else round(time.time() - self.server.store.last_ack, 1)))
        if path == "/api/customers":
            query = parse_qs(url.query).get("q", [""])[0][:120]
            return self.send({"customers": self.server.store.customers(query)})
        if path == "/api/privacy":
            return self.send(self.server.store.privacy())
        return self.send({"error": "Not found"}, 404)

    def do_POST(self):
        if not self.host_ok() or not self.origin_ok():
            return self.send({"error": "Local origin required"}, 403)
        path = urlsplit(self.path).path
        try:
            if path == "/api/upload-model":
                if not self.staff() or not secrets.compare_digest(self.headers.get("X-Showroom-CSRF", ""), self.server.store.csrf):
                    return self.send({"error": "Staff access required"}, 403)
                length = int(self.headers.get("Content-Length", "0"))
                if not 28 <= length <= 15*1024*1024:
                    raise ValidationError("GLB limit is 15 MB")
                key = parse_qs(urlsplit(self.path).query).get("id", [""])[0]
                return self.send(self.server.store.upload_model(key, self.rfile.read(length)))
            data = self.read_json()
            is_staff = self.staff()
            is_device = self.device()
            if path == "/api/pair":
                return self.send(self.server.store.pair(data))
            if not is_staff and not is_device:
                return self.send({"error": "Pair the device first"}, 401)
            if is_staff and not secrets.compare_digest(self.headers.get("X-Showroom-CSRF", ""), self.server.store.csrf):
                return self.send({"error": "Refresh the staff panel"}, 403)
            if path == "/api/state":
                return self.send(self.server.store.update(data))
            if path == "/api/ack" and is_device:
                return self.send(self.server.store.acknowledge(data))
            if not is_staff:
                return self.send({"error": "Staff access required"}, 403)
            if path == "/api/products":
                return self.send(self.server.store.save_product(data))
            if path == "/api/categories":
                return self.send(self.server.store.save_category(data))
            if path == "/api/privacy":
                if "retentionDays" not in data:
                    raise ValidationError("Retention days required")
                return self.send(self.server.store.privacy(data["retentionDays"]))
            if path == "/api/export-customer":
                return self.send(self.server.store.export_customer(data.get("id")))
            if path == "/api/publish":
                return self.send(self.server.store.publish(data))
            if path == "/api/delete-customer":
                with self.server.store.lock:
                    self.server.store.db.execute("DELETE FROM customers WHERE id=?", (data.get("id"),))
                    self.server.store.db.commit()
                return self.send({"deleted": True})
            if path == "/api/pairing":
                return self.send(self.server.store.pairing())
            if path == "/api/revoke-devices":
                self.server.store.revoke_devices()
                return self.send({"revoked": True})
            if path == "/api/new-session":
                return self.send(self.server.store.update(data, new_session=True))
            if path == "/api/customers":
                return self.send(self.server.store.save_customer(data))
            if path == "/api/restore-customer":
                return self.send(self.server.store.restore_customer(data.get("id"), data.get("expectedRevision")))
            return self.send({"error": "Not found"}, 404)
        except ConflictError as error:
            return self.send({"error": str(error)}, 409)
        except (ValidationError, ModelError, KeyError, TypeError, ValueError) as error:
            return self.send({"error": str(error)}, 400)
        except Exception:
            return self.send({"error": "Local service error. The last saved design is retained."}, 500)

def main():
    parser = argparse.ArgumentParser(description="Local staff panel and headset link")
    parser.add_argument("--port", type=int, default=18766)
    parser.add_argument("--data-dir", type=Path, default=ROOT / "data")
    parser.add_argument("--retention-days", type=int, help="Customer record retention, 1 to 365 days. Default: stored policy or 30.")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("Use a port between 1024 and 65535")
    if args.retention_days is not None and not 1 <= args.retention_days <= 365:
        parser.error("Retention must be 1 to 365 days")
    store = ShowroomStore(args.data_dir, retention_days=args.retention_days)
    try:
        with ShowroomServer(("127.0.0.1", args.port), store) as server:
            print(f"Staff panel: http://127.0.0.1:{args.port}", flush=True)
            server.serve_forever()
    finally:
        store.close()

if __name__ == "__main__":
    main()

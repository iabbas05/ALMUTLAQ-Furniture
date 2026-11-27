"""End-to-end staff checks with synthetic data and a simulated device ACK.

Run from the repository root after generating models into assets/ and server/models/.
Screenshots show the real staff HTML. They are not phone/headset acceptance evidence.
"""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
from urllib.request import Request, build_opener, ProxyHandler

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
from showroom_service import ShowroomStore, ShowroomServer


@contextmanager
def service():
    with tempfile.TemporaryDirectory() as folder:
        store = ShowroomStore(folder)
        server = ShowroomServer(("127.0.0.1", 0), store)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            yield f"http://127.0.0.1:{server.server_port}"
        finally:
            server.shutdown()
            server.server_close()
            worker.join()
            store.close()


def wait(page, expression):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if page.evaluate('() => (' + expression + ')'):
            return
        page.wait_for_timeout(100)
    raise AssertionError('Timed out: ' + expression)


def check():
    output = ROOT / "build/staff-preview"
    output.mkdir(parents=True, exist_ok=True)
    with service() as url, sync_playwright() as p:
        executable = os.environ.get("SHOWROOM_CHROMIUM")
        browser = p.chromium.launch(**({"executable_path": executable} if executable else {}))
        page = browser.new_page(viewport={"width": 1440, "height": 1050})
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(url)
        wait(page, "typeof state !== 'undefined' && state.room.width === 4")
        page.locator("#width").fill("5")
        page.locator("#measurements button").click()
        wait(page, "state.room.width === 5")
        assert page.locator("#connection").inner_text() == "بانتظار تأكيد النظارة"
        assert page.evaluate("catalogue.find(p=>p.sku==='10_14_3').dimensions.width") == 2.1
        page.locator("#products button").filter(has_text="كرسي لندن").click()
        wait(page, "state.items.length === 2")
        page.locator("#rotate").click()
        wait(page, "state.items[1].rotationY === 15")
        # A rejected import must leave both the browser and saved room untouched.
        revision = page.evaluate("state.revision")
        page.get_by_text("استيراد تصميم من الجوال", exact=True).click()
        bad = page.evaluate("({...state,room:{...state.room,width:1}})")
        page.locator("#room-json").fill(json.dumps(bad))
        page.locator("#import").click()
        wait(page, "document.querySelector('#message').classList.contains('error')")
        assert page.evaluate("state.revision") == revision
        assert page.evaluate("state.room.width") == 5
        # Customer data stays on the staff service and requires consent.
        page.locator("#customer-name").fill("TEST CUSTOMER")
        page.locator("#customer-phone").fill("00000000")
        page.locator("#customer-consent").check()
        page.locator("#save-customer button").click()
        wait(page, "document.querySelector('#message').textContent.includes('انحفظت التجربة')")
        page.locator("nav button[data-tab=customers]").click()
        page.locator("#customer-list .customer-row").wait_for()
        assert "TEST CUSTOMER" in page.locator("#customer-list").inner_text()
        page.get_by_role("button", name="فتح التجربة", exact=True).click()
        wait(page, f"state.revision > {revision}")
        assert page.evaluate("JSON.stringify(state).includes('00000000')") is False
        # Simulate the device protocol to verify status UI, not real device rendering.
        pair = page.evaluate("api('/api/pairing', {})")
        client = build_opener(ProxyHandler({}))
        def call(path, body, token=None):
            headers = {"Content-Type": "application/json"}
            if token:
                headers["Authorization"] = "Bearer " + token
            with client.open(Request(url + path, data=json.dumps(body).encode(), headers=headers)) as response:
                return json.load(response)
        token = call("/api/pair", {"code": pair["code"]})["token"]
        state = page.evaluate("state")
        call("/api/ack", {"sessionId": state["sessionId"], "revision": state["revision"]}, token)
        wait(page, "document.querySelector('#connection').textContent.includes('أكدت')")
        page.locator('#room-preview summary').click()
        wait(page, 'roomPreview.cache.size === 2')
        page.screenshot(path=str(output / "staff-room-ar.png"), full_page=True)
        page.locator("nav button[data-tab=catalogue]").click()
        page.screenshot(path=str(output / "staff-catalogue-ar.png"), full_page=True)
        page.locator("nav button[data-tab=room]").click()
        for width in (390, 768):
            page.set_viewport_size({"width": width, "height": 844})
            assert page.evaluate("document.documentElement.scrollWidth <= innerWidth + 1")
            page.screenshot(path=str(output / f"staff-room-{width}-ar.png"), full_page=True)
        assert not errors, errors
        browser.close()
    print("Staff browser checks passed: dimensions, chair rotation, rejected import, consent, restore, simulated ACK, responsive Arabic.")


if __name__ == "__main__":
    check()

#!/usr/bin/env python3
"""Real functional smoke test: loads index.html in a headless browser and checks
the app actually works, not just that it parses. Catches runtime bugs verify.py
can't see (e.g. the past `.rpc().catch()` crash that broke the whole detail modal).

Requires: pip3 install playwright && python3 -m playwright install --with-deps chromium
"""
import http.server
import socketserver
import sys
import threading
import time
from contextlib import contextmanager

from playwright.sync_api import sync_playwright

ROOT = __import__("os").path.dirname(__import__("os").path.dirname(__import__("os").path.abspath(__file__)))
PORT = 8743

failed = False


def fail(msg):
    global failed
    print("FAIL: " + msg)
    failed = True


def ok(msg):
    print("OK: " + msg)


@contextmanager
def local_server():
    handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(*a, directory=ROOT, **kw)
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("127.0.0.1", PORT), handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{PORT}/index.html"
    finally:
        httpd.shutdown()


def main():
    with local_server() as url:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page()

            console_errors = []
            bad_responses = []

            def on_console(msg):
                # Chrome always logs a generic "Failed to load resource" line for ANY failed
                # network request (page JS can't suppress it) — ignore it here and check actual
                # failed requests separately via the response listener below, where we can tell
                # the one expected 404 (config.local.js, an intentionally-absent local override)
                # apart from a real one.
                if msg.type == "error" and "Failed to load resource" not in msg.text:
                    console_errors.append(msg.text)

            def on_response(resp):
                if resp.status >= 400 and "config.local.js" not in resp.url:
                    bad_responses.append(f"{resp.status} {resp.url}")

            page.on("console", on_console)
            page.on("pageerror", lambda exc: console_errors.append(str(exc)))
            page.on("response", on_response)

            page.goto(url, wait_until="networkidle", timeout=15000)
            time.sleep(1)  # let async render/sync settle

            # 1. The feed actually rendered listings (sample data is local, needs no backend)
            rows = page.query_selector_all(".feed-row")
            if len(rows) > 0:
                ok(f"feed rendered {len(rows)} listing(s)")
            else:
                fail("feed rendered zero .feed-row elements")

            # 2. Clicking a listing opens the detail modal
            if rows:
                rows[0].click()
                page.wait_for_timeout(500)
                detail = page.query_selector("#detailBackdrop")
                if detail and detail.is_visible():
                    ok("clicking a listing opens the detail modal")
                    page.keyboard.press("Escape")
                    page.wait_for_timeout(300)
                else:
                    fail("clicking a listing did not open #detailBackdrop")

            # 3. The login modal opens
            login_btn = page.query_selector("#openAuthBtn, [data-action='open-auth']")
            # fall back: find any element whose visible text is exactly the login label
            if not login_btn:
                login_btn = page.get_by_text("دخول", exact=True).first
            try:
                login_btn.click(timeout=3000)
                page.wait_for_timeout(400)
                auth_modal = page.query_selector("#authBackdrop")
                if auth_modal and auth_modal.is_visible():
                    ok("login button opens #authBackdrop")
                else:
                    fail("login click did not open #authBackdrop")
                page.keyboard.press("Escape")
            except Exception as e:
                fail(f"could not open login modal: {e}")

            # 4. No uncaught JS errors / console errors fired during this walkthrough
            if console_errors:
                fail("console/page errors during smoke test: " + " | ".join(console_errors[:5]))
            else:
                ok("no uncaught JS errors during smoke test")

            if bad_responses:
                fail("unexpected failed network requests: " + " | ".join(bad_responses[:5]))
            else:
                ok("no unexpected failed network requests")

            browser.close()

    if failed:
        print("\nsmoke_test.py: one or more checks failed.")
        sys.exit(1)
    else:
        print("\nsmoke_test.py: all checks passed.")


if __name__ == "__main__":
    main()

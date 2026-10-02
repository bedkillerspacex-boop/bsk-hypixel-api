#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Probe the PUBLIC API's documented error paths WITHOUT credentials.

Why this exists
---------------
Documentation drifts silently. This script checks the cheap, safe half of the
contract -- error handling and discovery -- so a doc change can be verified.

Safety
------
* Sends **no API key, token or credential** of any kind.
* Only hits paths that are expected to FAIL, so **no quota is consumed**
  (the one exception, `GET /api`, is free).
* It never claims the happy paths work. Those need a real key and are
  deliberately out of scope.

Usage
-----
    python -B tools/probe_public_api.py                 # uses the public base
    python -B tools/probe_public_api.py --base http://127.0.0.1:18096

Exit code is 0 when every probe matched its documented expectation.
"""
import argparse
import json
import sys
import urllib.error
import urllib.request

DEFAULT_BASE = "https://api.firebounce.today"

# (method, path, body, expected_status, expected_error_or_None, note)
CASES = [
    ("GET", "/api", None, 200, None,
     "discovery: latest version, parameter registry, proxy bases"),
    ("GET", "/api/denick/v9", None, 404, "unknown_version",
     "unknown version -> 404"),
    ("GET", "/api/card.png", None, 410, "gone",
     "retired endpoint stays 410 (not 404)"),
    ("GET", "/api/bancheck", None, 400, "missing_param",
     "bancheck validates params BEFORE auth"),
    ("GET", "/api/denick", None, 401, "missing_key",
     "denick authenticates BEFORE validating params"),
    ("GET", "/api/search?q=a", None, 401, "missing_key",
     "search authenticates BEFORE the 2-char check"),
    ("GET", "/api/nick-history", None, 401, "missing_key",
     "nick-history authenticates first"),
    ("GET", "/api/quota", None, 401, "missing_key",
     "quota is free: X-Quota-Cost must be 0 even on 401"),
    ("GET", "/api/player", None, 401, "missing_key",
     "player authenticates first"),
]


def call(base, method, path, body, timeout=20, attempts=3):
    """Call once, retrying only on transient transport errors.

    A flaky TLS/connection reset must not be reported as a documentation
    failure, so transport errors get a bounded retry. HTTP error *statuses*
    are never retried -- those are the actual answers we are probing for.
    """
    last = (None, {}, "")
    for attempt in range(attempts):
        req = urllib.request.Request(base + path, method=method, data=body,
                                     headers={"Content-Type": "application/json"}
                                     if body else {})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, dict(r.headers), r.read(65536).decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            return e.code, dict(e.headers), e.read(65536).decode("utf-8", "replace")
        except Exception as exc:                 # connection closed, timeout, ...
            last = (None, {}, "%s: %s" % (type(exc).__name__, str(exc)[:160]))
            if attempt + 1 < attempts:
                print("      (transport error, retrying: %s)" % str(exc)[:80])
    return last


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=DEFAULT_BASE)
    args = ap.parse_args()

    failures = 0
    for method, path, body, want_status, want_error, note in CASES:
        status, headers, text = call(args.base, method, path, body)
        try:
            data = json.loads(text)
            error = data.get("error") if isinstance(data, dict) else None
        except Exception:
            data, error = None, None

        status_ok = status == want_status
        error_ok = (want_error is None) or (error == want_error)
        # /api/quota must report cost 0 on every response.
        cost_ok = True
        if path.startswith("/api/quota"):
            cost_ok = headers.get("X-Quota-Cost") == "0"
        ok = status_ok and error_ok and cost_ok
        failures += 0 if ok else 1

        print("%s %-6s %-22s  %s" % ("PASS" if ok else "FAIL", method, path, note))
        print("      status=%s (want %s)  error=%r (want %r)"
              % (status, want_status, error, want_error))
        if not cost_ok:
            print("      X-Quota-Cost=%r but /api/quota must always be 0"
                  % headers.get("X-Quota-Cost"))
        if not status_ok and status is None:
            print("      no HTTP response: %s" % text[:160])
        if data and isinstance(data, dict) and "latest" in (data.get("data") or {}):
            d = data["data"]
            print("      latest=%s alias=%s versions=%s params=%s"
                  % (d.get("latest"), d.get("latest_alias"),
                     d.get("versions"), len(d.get("parameters") or [])))

    # ------------------------------------------------------------------
    # State probe: this endpoint's behaviour legitimately differs depending on
    # whether implementation commit 05ef64b is deployed. BOTH states are
    # documented, so this reports which one production is in instead of
    # failing -- a failure here would just mean "not deployed yet".
    # ------------------------------------------------------------------
    print()
    status, headers, text = call(args.base, "POST", "/api/hypixel", b"{}")
    state = None
    if status is None:
        state = "PRE-FIX (connection closed, nothing returned)"
    else:
        try:
            body = json.loads(text)
        except Exception:
            body = None
        if (status == 200 and isinstance(body, dict) and body.get("ok") is False
                and "use" in body):
            state = "FIXED (200 discovery JSON, no auth, no upstream call)"
    print("STATE  POST   /api/hypixel")
    if state is None:
        failures += 1
        print("      UNEXPECTED: status=%s body=%r" % (status, text[:160]))
        print("      expected either the pre-fix close or the 200 discovery JSON")
    else:
        print("      %s" % state)
        print("      => production %s contain commit 05ef64b"
              % ("DOES" if state.startswith("FIXED") else "does NOT"))

    print()
    print("%d/%d probes matched the documentation"
          % (len(CASES) - failures, len(CASES)))
    print("NOTE: this covers error paths only. It does NOT prove the happy "
          "paths work -- those need a real key and were not exercised.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

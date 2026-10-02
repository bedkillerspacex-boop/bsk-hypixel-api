#!/usr/bin/env python3
"""Check the documentation's high-risk API contract statements.

This is intentionally a documentation sentinel, not a production API probe.
Runtime behavior remains owned by bsk-qqbot and its offline contract tests.
"""
from pathlib import Path
import argparse
import ast
import io
import json
import re
import runpy
import sys
import types
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
FILES = {
    "root": ROOT / "README.md",
    "llms": ROOT / "llms.txt",
    "overview": ROOT / "docs/api/README.md",
    "current": ROOT / "docs/api/v1-261001/README.md",
    "legacy": ROOT / "docs/api/v1-260925/README.md",
    "registry": ROOT / "docs/api/parameter-registry.md",
}


def read(name):
    return FILES[name].read_text(encoding="utf-8")


def check_examples(implementation):
    from jsonschema import Draft202012Validator
    versions = ("v1-260925", "v1-261001")
    for version in versions:
        folder = ROOT / "docs/api" / version
        schema = json.loads((folder / "schemas/response.json").read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(schema)
        validator = Draft202012Validator(schema)
        for path in (folder / "examples").glob("*.json"):
            validator.validate(json.loads(path.read_text(encoding="utf-8")))
    if implementation is None:
        print("schemas/examples validated; runtime comparison not requested")
        return
    source = Path(implementation).resolve()
    # Pure definition modules only. Never import the service entrypoint, load
    # its real configuration, state files, credentials or background tasks.
    registry = runpy.run_path(str(source / "bot_core/runtime/api_parameters.py"))
    text = read("registry")
    rows = [(int(i), key) for i, key in re.findall(r"^\|\s*(\d+)\s*\|\s*`([^`]+)`", text, re.M)]
    assert rows == [(p["id"], p["key"]) for p in registry["registry"]()], "parameter IDs/keys differ from implementation"
    tree = ast.parse((source / "qqbot_broadcast.py").read_text(encoding="utf-8"))
    routes = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign)
                  and any(isinstance(t, ast.Name) and t.id == "_API_ROUTES" for t in n.targets))
    docs = read("current")
    for endpoint in routes:
        assert "/api/" + endpoint in docs, "undocumented endpoint: " + endpoint
    versions_code = runpy.run_path(str(source / "bot_core/runtime/api_versioning.py"))
    for version in versions:
        assert versions_code["_version_of"](version) is not None
        assert versions_code["api_route"]("/api/bancheck/" + version) == ("bancheck", version, True)
    assert versions_code["_version_of"]("v1-250101") is None
    # Execute the real local-index algorithm with an empty controlled index.
    # Only selected function AST nodes are executed, avoiding module top-level
    # state/configuration. Network and production persistence are unnecessary.
    tree = ast.parse((source / "bantrack.py").read_text(encoding="utf-8"))
    selected = [n for n in tree.body if isinstance(n, ast.FunctionDef)
                and n.name in ("query_cost", "check", "_entry")]
    namespace = {"re": re, "QUERY_COST": 0.7, "NAME_QUERY_COST": 1.0,
                 "SOURCE_TRACKER": "tracker", "SOURCE_HYP_DC": "hyp_dc",
                 "_load_index": lambda: {"by_name": {}, "by_uuid": {}}}
    exec(compile(ast.Module(body=selected, type_ignores=[]), "bantrack selected functions", "exec"), namespace)
    fake_bt = types.ModuleType("bantrack")
    fake_bt.check, fake_bt.query_cost = namespace["check"], namespace["query_cost"]
    fake_d = types.ModuleType("denick")
    fake_d.check_key = lambda *a, **k: (True, "ok")
    query = runpy.run_path(str(source / "bot_core/http/http_query_endpoints.py"))["QueryEndpointsMixin"]
    localization = runpy.run_path(str(source / "bot_core/runtime/api_localization.py"))
    fake_localization = types.ModuleType("bot_core.runtime.api_localization")
    fake_localization.localize = localization["localize"]
    fake_redaction = types.ModuleType("log_redaction")
    fake_redaction.redact = lambda x: str(x)
    with mock.patch.dict(sys.modules, {"denick": fake_d, "bantrack": fake_bt,
                                      "log_redaction": fake_redaction,
                                      "bot_core.runtime.api_localization": fake_localization}):
        protocol = runpy.run_path(str(source / "bot_core/http/http_protocol.py"))["HTTPResponseMixin"]
        class Capture(query, protocol):
            def _key_from_request(self, params): return "offline-placeholder"
            def _api_latest(self): return "v1-261001"
            def send_response(self, status): self.status = status
            def send_header(self, *args): pass
            def end_headers(self): pass
            def _charge_response(self, **kwargs): pass
        for version in versions:
            for scenario, target, status in (("unknown", "?name=ExamplePlayer", 200), ("missing", "", 400)):
                out = Capture()
                out._api_version, out.path, out.wfile = version, "/api/bancheck" + target, io.BytesIO()
                out._api_checkban()
                example = ROOT / "docs/api" / version / "examples" / ("bancheck-" + scenario + ".json")
                assert out.status == status
                assert json.loads(out.wfile.getvalue()) == json.loads(example.read_text(encoding="utf-8")), str(example)
        assert fake_bt.query_cost(uuid="00000000000000000000000000000001") == 0.7
        assert fake_bt.query_cost(name="ExamplePlayer") == 1.0
    print("implementation comparison: IDs/keys, route inventory, version parsing and four real bancheck responses OK")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--implementation", type=Path, help="local bsk-qqbot checkout; never loads production configuration")
    args = parser.parse_args()
    errors = []
    for name, path in FILES.items():
        if not path.is_file():
            errors.append("missing %s: %s" % (name, path))

    if errors:
        print("CONTRACT FAIL")
        print("\n".join(errors))
        return 1

    registry = read("registry")
    ids = [int(x) for x in re.findall(r"^\|\s*(\d+)\s*\|", registry, re.M)]
    if ids != list(range(1, 25)):
        errors.append("parameter registry IDs are not exactly 1..24: %r" % ids)

    overview = read("overview")
    current = read("current")
    legacy = read("legacy")
    all_docs = "\n".join(read(name) for name in FILES if name != "registry")

    required = (
        ("version latest", "v1-261001"),
        ("version legacy", "v1-260925"),
        ("bancheck UUID price", "UUID 0.7"),
        ("bancheck name price", "1.0"),
        ("proxy timeout", "12 秒"),
        ("proxy total budget", "30 秒"),
        ("proxy cache TTL", "300 秒"),
        ("proxy global rate", "600/分钟"),
        ("Bugland prefix", "bsk_bjd_"),
        ("unknown state", "state"),
        ("data quality", "data_quality"),
        ("parameter policy", "不重新编号"),
    )
    for label, needle in required:
        if needle not in all_docs:
            errors.append("missing %s: %r" % (label, needle))

    if not all(item in read("llms") for item in ("v1-261001", "v1-260925", "404 unknown_version")):
        errors.append("llms.txt does not state the supported version set")
    if "Hypixel 资源反代只支持 `GET`" not in current:
        errors.append("current version does not state Hypixel proxy is GET-only")
    if "Bugland 反代支持两者" not in current:
        errors.append("current version does not state Bugland supports both methods")
    if "POST /api/hypixel`（无子路径）" not in current:
        errors.append("current version lacks the POST Hypixel discovery contract")
    if "HTTP **`200`**，**不鉴权、不消耗额度、不打上游**" not in current:
        errors.append("POST Hypixel discovery side effects are undocumented")

    stale = (
        "v1-250101`）会被路由接受",
        "POST /api/hypixel`（裸路径） | **连接被关闭、无响应",
        "每次请求花了多少额度",
    )
    for needle in stale:
        if needle in all_docs:
            errors.append("stale contract text remains: %r" % needle)

    print("documentation contract: %s" % ("OK" if not errors else "FAIL"))
    if errors:
        print("\n".join("- " + error for error in errors))
        return 1
    print("versions: v1-260925, v1-261001")
    print("parameter IDs: 1..24")
    print("proxy: GET-only Hypixel; GET/POST Bugland; 12s/30s/300s/600 per minute")
    check_examples(args.implementation)
    return 0


if __name__ == "__main__":
    sys.exit(main())

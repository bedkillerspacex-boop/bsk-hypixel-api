#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Validate the docs repo: relative links resolve, JSON examples parse."""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)\)")
FENCE = re.compile(r"^```(\w*)\s*$")
HEADING = re.compile(r"^(#{1,6})\s+(.+?)\s*$")


def slug(text):
    """GitHub-flavored heading anchor (keeps CJK, drops other punctuation)."""
    text = re.sub(r"<[^>]+>", "", text)
    text = text.strip().lower()
    text = re.sub(r"[^\w\- ]", "", text, flags=re.UNICODE)
    return text.replace(" ", "-")


def headings_of(lines):
    """Anchor set for one file, honouring GitHub's -1/-2 duplicate suffixes."""
    seen, anchors = {}, set()
    for line in lines:
        m = HEADING.match(line)
        if not m:
            continue
        base = slug(m.group(2))
        n = seen.get(base, 0)
        seen[base] = n + 1
        anchors.add(base if n == 0 else "%s-%d" % (base, n))
    return anchors

# Verbatim historical snapshots. These are preserved byte-for-byte on purpose and
# are NEVER normalized, so their code fences are exempt from strict checking.
# Changing them would break the promise that old integrations can rely on them.
FROZEN = {"docs/api/v1-260925/REFERENCE.md"}

bad_links, bad_anchors, bad_json = [], [], []
checked_links, checked_anchors, checked_json = 0, 0, 0
elided_json, frozen_json = 0, 0
md_files = []
for base, dirs, files in os.walk(ROOT):
    dirs[:] = [d for d in dirs if d != ".git"]
    for f in files:
        if f.endswith(".md"):
            md_files.append(os.path.join(base, f))

cache = {}
for path in sorted(md_files):
    rel = os.path.relpath(path, ROOT).replace("\\", "/")
    frozen = rel in FROZEN
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    anchors = headings_of(lines)
    cache[os.path.normcase(os.path.normpath(path))] = anchors

    # ---- links ----
    for i, line in enumerate(lines, 1):
        for m in LINK.finditer(line):
            target = m.group(1)
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            file_part, _, anchor = target.partition("#")
            if not file_part and not anchor:
                continue
            if file_part:
                checked_links += 1
                resolved = os.path.normpath(
                    os.path.join(os.path.dirname(path), file_part))
                if not os.path.exists(resolved.rstrip("/\\") or resolved):
                    bad_links.append((rel, i, target, "missing file"))
                    continue
                target_path = resolved
            else:
                target_path = path
            # ---- anchor ----
            if not anchor or not target_path.lower().endswith(".md"):
                continue
            checked_anchors += 1
            key = os.path.normcase(os.path.normpath(target_path))
            avail = cache.get(key)
            if avail is None:
                with open(target_path, encoding="utf-8") as fh:
                    avail = headings_of(fh.read().split("\n"))
                cache[key] = avail
            if anchor.lower() not in avail:
                bad_anchors.append((rel, i, target))

    # ---- json fences ----
    inside, buf, start, lang = False, [], 0, ""
    for i, line in enumerate(lines, 1):
        m = FENCE.match(line.strip())
        if m and not inside:
            if m.group(1).lower() in ("json", "jsonc"):
                inside, buf, start, lang = True, [], i, m.group(1).lower()
            continue
        if inside and line.strip().startswith("```"):
            text = "\n".join(buf)
            if lang == "jsonc":
                # Deliberately elided excerpt (contains `...` / `[...]`) or a
                # config fragment. Labeled jsonc so it is not copied verbatim.
                elided_json += 1
            elif frozen:
                frozen_json += 1
            else:
                checked_json += 1
                try:
                    json.loads(text)
                except Exception as exc:
                    bad_json.append((rel, start, str(exc)[:90]))
            inside = False
            continue
        if inside:
            buf.append(line)

print("markdown files     : %d" % len(md_files))
print("relative links     : %d checked" % checked_links)
print("anchors            : %d checked" % checked_anchors)
print("json examples      : %d strictly checked" % checked_json)
print("jsonc (elided)     : %d skipped by label" % elided_json)
print("frozen snapshot    : %d skipped (verbatim history)" % frozen_json)
print()
if bad_links:
    print("### BROKEN LINKS (%d)" % len(bad_links))
    for rel, line, target, why in bad_links:
        print("  %s:%d  -> %s   [%s]" % (rel, line, target, why))
else:
    print("### links: OK")
print()
if bad_anchors:
    print("### BROKEN ANCHORS (%d)" % len(bad_anchors))
    for rel, line, target in bad_anchors:
        print("  %s:%d  -> %s" % (rel, line, target))
else:
    print("### anchors: OK")
print()
if bad_json:
    print("### INVALID JSON (%d)" % len(bad_json))
    for rel, line, why in bad_json:
        print("  %s:%d  %s" % (rel, line, why))
else:
    print("### json: OK")

sys.exit(1 if (bad_links or bad_anchors or bad_json) else 0)

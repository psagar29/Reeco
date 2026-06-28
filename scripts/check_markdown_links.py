#!/usr/bin/env python3
"""Relative Markdown link checker for the Recco monorepo.

Person D (integration QA) tooling. Standard library only — no pip installs.

What it does
------------
- Scans every tracked ``*.md`` file in the repo (skipping vendored / build dirs).
- Finds inline Markdown links ``[text](target)`` and images ``![alt](target)``.
- Verifies that every *relative* link target points at a file that exists.
- **Ignores external URLs** (``http://``, ``https://``, ``mailto:``, ``tel:``)
  and pure in-page anchors (``#section``).
- Skips fenced code blocks (```` ``` ````) and inline code spans (`` `...` ``),
  so example links inside code samples are not flagged.

What it does NOT do
-------------------
- It does not validate ``#anchor`` fragments inside a target (only the file part).
- It does not check bare inline-code paths like ``docs/foo.md`` written without
  ``[ ]( )`` link syntax — those are prose, not links.

Usage
-----
    python scripts/check_markdown_links.py            # scan repo root
    python scripts/check_markdown_links.py docs       # scan a subtree
    python scripts/check_markdown_links.py --list      # also list checked files

Exit code: ``0`` if all relative links resolve, ``1`` if any are broken.
This is intentionally advisory — see docs/QA_CHECKLIST.md. It is not wired into
CI as a required gate.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

# Directories we never want to scan (vendored, generated, build output).
SKIP_DIRS = {
    ".git",
    "node_modules",
    ".venv",
    "venv",
    "DerivedData",
    "build",
    ".build",
    "__pycache__",
    ".convex",
}

# [text](target) and ![alt](target). Capture the target up to the first ) or space.
LINK_RE = re.compile(r"!?\[[^\]]*\]\(\s*(<[^>]+>|[^)\s]+)")

# Inline code spans (double- or single-backtick). Stripped before link matching
# so a `[text](path)` example written *inside* code is not treated as a link.
INLINE_CODE_RE = re.compile(r"``[^`]*``|`[^`]*`")

EXTERNAL_PREFIXES = ("http://", "https://", "mailto:", "tel:", "//")


def find_markdown_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if name.lower().endswith(".md"):
                files.append(Path(dirpath) / name)
    return sorted(files)


def extract_links(text: str) -> list[tuple[int, str]]:
    """Return (line_number, target) for each inline link outside code fences."""
    links: list[tuple[int, str]] = []
    in_fence = False
    fence_marker = ""
    for lineno, line in enumerate(text.splitlines(), start=1):
        stripped = line.lstrip()
        # Toggle fenced code blocks (``` or ~~~).
        if stripped.startswith("```") or stripped.startswith("~~~"):
            marker = stripped[:3]
            if not in_fence:
                in_fence, fence_marker = True, marker
            elif stripped.startswith(fence_marker):
                in_fence, fence_marker = False, ""
            continue
        if in_fence:
            continue
        # Drop inline code spans so `[text](path)` examples aren't matched.
        line = INLINE_CODE_RE.sub(" ", line)
        for match in LINK_RE.finditer(line):
            target = match.group(1).strip().strip("<>")
            links.append((lineno, target))
    return links


def is_external_or_anchor(target: str) -> bool:
    if not target or target.startswith("#"):
        return True
    return target.startswith(EXTERNAL_PREFIXES)


def check_file(md_file: Path, root: Path) -> list[tuple[int, str]]:
    """Return a list of (line_number, target) broken relative links."""
    broken: list[tuple[int, str]] = []
    try:
        text = md_file.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:  # pragma: no cover
        return [(0, f"<could not read: {exc}>")]
    for lineno, target in extract_links(text):
        if is_external_or_anchor(target):
            continue
        # Strip any in-page anchor fragment and query.
        path_part = target.split("#", 1)[0].split("?", 1)[0]
        if not path_part:
            continue  # pure anchor like (#section)
        if path_part.startswith("/"):
            resolved = (root / path_part.lstrip("/")).resolve()
        else:
            resolved = (md_file.parent / path_part).resolve()
        if not resolved.exists():
            broken.append((lineno, target))
    return broken


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if not a.startswith("-")]
    list_files = "--list" in argv[1:]
    scan_root = Path(args[0]).resolve() if args else Path.cwd().resolve()
    # The repo root is used to resolve absolute-style "/path" links.
    repo_root = Path(__file__).resolve().parent.parent

    md_files = find_markdown_files(scan_root)
    total_broken = 0
    print(f"Markdown link check — scanning {len(md_files)} file(s) under {scan_root}\n")

    for md_file in md_files:
        broken = check_file(md_file, repo_root)
        rel = md_file.relative_to(repo_root) if repo_root in md_file.parents else md_file
        if broken:
            total_broken += len(broken)
            print(f"BROKEN  {rel}")
            for lineno, target in broken:
                print(f"        line {lineno}: {target}")
        elif list_files:
            print(f"ok      {rel}")

    print()
    if total_broken:
        print(f"FAIL: {total_broken} broken relative link(s) found.")
        return 1
    print(f"OK: all relative links resolve across {len(md_files)} Markdown file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

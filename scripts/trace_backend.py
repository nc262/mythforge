#!/usr/bin/env python3
"""Which backend modules are actually reachable? An import graph, ADVISORY ONLY.

!! DO NOT BULK-DELETE ON THIS TOOL'S WORD. Its "orphan" list was wrong SEVEN
!! times in a row while being written, and every wrong answer would have deleted
!! working code. Use it to find CANDIDATES, then delete a few at a time and prove
!! each batch with `pytest tests/ --continue-on-collection-errors` against a
!! recorded baseline. For the "is this router even used" question prefer
!! scripts/route_surface.py, which asks FastAPI instead of parsing it.

The seven, kept as a record of how a confident-looking analyser fails:

  1. Hardcoded PKGS omitted services/ (39 files), so nothing it imported could
     ever look reachable -> src/rag_manager, rag_vector, memory_vector all
     reported orphan while services/docs and services/memory import them.
  2. Relative imports resolved against the wrong package for a package
     __init__.py (`src.analytics` instead of `src.search.analytics`).
  3. `from X import a, b` treated the SYMBOLS as modules, so the real dependency
     on X was recorded as a dependency on X's parent.
  4. Modules launched as subprocesses from a string path had no importer and
     looked dead -- mcp_servers/image_gen_server.py, which IS image generation.
  5. Parent packages of a reachable module were not marked reachable, though
     Python executes their __init__ on import.
  6. (route decorators) Paths were read without the prefix applied at
     include_router time, so auth/models/session/stt were all reported as
     serving nothing the client calls. All four are on the first screen.
  7. Ancestors added by fix 5 were marked reachable without tracing THEIR
     imports, so services/memory/__init__.py was live while the module it
     imports was still called an orphan.

Empty directories are a related trap: deleting every .py in a package leaves the
folder, Python treats it as a namespace package, and imports fail differently.

The previous cleanup pass established the method the hard way: a string search
found 44 dead test files and MISSED five more that built paths with
`_REPO / "static" / "js"`. A grep is not a dependency check. So this walks the
AST instead of the text.

Two questions, deliberately kept apart because they carry very different risk:

  ORPHANS   modules no live module imports, transitively, starting from app.py.
            Deleting these is safe by construction — nothing can call them.

  UNUSED    routers whose HTTP endpoints the Godot client never calls. These are
            *candidates*, not garbage: a router the client ignores may still be
            imported by one it needs, and FastAPI routes can be reached by paths
            this script cannot see. Reported separately, never auto-deleted.

Dynamic imports are the known blind spot, so they are hunted explicitly and
listed — importlib, __import__, and any string that looks like a module path.
Anything flagged there is a reason to check by hand before deleting.

    python scripts/trace_backend.py            # summary
    python scripts/trace_backend.py --orphans  # just the safe-to-delete list
"""
from __future__ import annotations

import argparse
import ast
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENTRY = "app"

# Directories that are not importable backend packages.
SKIP_DIRS = {
    "godot", "installer", "tests", "scripts", "build", "dist", "data", "logs",
    "venv", ".venv", "__pycache__", "node_modules", ".git", ".claude", ".github",
}


def discover_pkgs() -> tuple[str, ...]:
    """Find the backend packages instead of hardcoding them.

    The hardcoded list was ("routes", "src", "core", "companion") and it made
    this tool CONFIDENTLY WRONG: `services/` (39 files) was never scanned, so
    nothing it imported could ever be seen as reachable. src/rag_manager,
    src/rag_vector and src/memory_vector were reported as orphans and deleted,
    while services/docs and services/memory imported all three.
    `pytest --collect-only` caught it — three separate times, each time a
    different resolution gap.
    """
    out = []
    for name in sorted(os.listdir(ROOT)):
        p = os.path.join(ROOT, name)
        if not os.path.isdir(p) or name in SKIP_DIRS or name.startswith("."):
            continue
        for dirpath, _d, files in os.walk(p):
            if "__pycache__" in dirpath:
                continue
            if any(f.endswith(".py") for f in files):
                out.append(name)
                break
    return tuple(out)


PKGS = discover_pkgs()

# The endpoints the Godot client provably calls, harvested from the .gd sources.
# Kept here so the "unused router" question has a single source of truth.
CLIENT_PATHS = [
    "/api/auth/login", "/api/auth/logout", "/api/auth/status",
    "/api/chat_stream", "/api/default-chat",
    "/api/characters/studio/",           # prefix: the whole studio surface
    "/api/models", "/api/presets/templates",
    "/api/session", "/api/history/", "/api/version", "/api/stt/transcribe",
]


def mod_name(path: str) -> str:
    rel = os.path.relpath(path, ROOT).replace("\\", "/")
    if rel.endswith("/__init__.py"):
        rel = rel[: -len("/__init__.py")]
    elif rel.endswith(".py"):
        rel = rel[: -len(".py")]
    return rel.replace("/", ".")


def all_modules() -> dict[str, str]:
    out: dict[str, str] = {}
    entry = os.path.join(ROOT, ENTRY + ".py")
    if os.path.exists(entry):
        out[ENTRY] = entry
    for pkg in PKGS:
        base = os.path.join(ROOT, pkg)
        for dirpath, _dirs, files in os.walk(base):
            if "__pycache__" in dirpath:
                continue
            for fn in files:
                if fn.endswith(".py"):
                    p = os.path.join(dirpath, fn)
                    out[mod_name(p)] = p
    return out


def imports_of(path: str, known: set[str]) -> set[str]:
    """Local imports only — stdlib and site-packages are irrelevant here.

    Resolves `from routes.foo import x`, `import src.bar`, and relative
    `from . import baz` (companion/ uses those). A name that is a PACKAGE
    (routes) rather than a module also pulls its __init__.
    """
    try:
        with open(path, encoding="utf-8") as f:
            tree = ast.parse(f.read(), filename=path)
    except (SyntaxError, UnicodeDecodeError):
        return set()
    # The package a relative import resolves against. For a PACKAGE __init__.py
    # that is the package itself; for a plain module it is the parent.
    #
    # Getting this wrong is not academic: taking rsplit() unconditionally made
    # `from .analytics import ...` inside src/search/__init__.py resolve to
    # `src.analytics`, so src.search.analytics looked unreachable and got
    # deleted along with three of its siblings. `pytest --collect-only` caught
    # it. An import graph that quietly mis-resolves is more dangerous than the
    # grep it replaced, because it looks authoritative.
    me = mod_name(path)
    if os.path.basename(path) == "__init__.py":
        pkg = me
    else:
        pkg = me.rsplit(".", 1)[0] if "." in me else ""
    found: set[str] = set()

    def add(name: str) -> None:
        if not name:
            return
        # Longest known prefix wins: "src.a.b" resolves to src.a.b, else src.a.
        parts = name.split(".")
        for i in range(len(parts), 0, -1):
            cand = ".".join(parts[:i])
            if cand in known:
                found.add(cand)
                return

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for a in node.names:
                add(a.name)
        elif isinstance(node, ast.ImportFrom):
            # In `from X import a, b`, node.module is X and node.names are the
            # SYMBOLS — which are usually functions, not modules. Conflating the
            # two is what hid src.search.analytics: `from .analytics import
            # get_search_stats` was resolved as `src.search.get_search_stats`,
            # which is not a module, so add() fell back to the package and the
            # real dependency on .analytics was never recorded.
            #
            # So resolve node.module FIRST, and only then try each name as a
            # possible submodule — which is the `from . import submodule` and
            # `from pkg import submodule` case.
            base = pkg
            if node.level:                      # relative
                for _ in range(node.level - 1):
                    base = base.rsplit(".", 1)[0] if "." in base else ""
                target = f"{base}.{node.module}" if node.module else base
            else:
                target = node.module or ""
            add(target)
            for a in node.names:
                add(f"{target}.{a.name}" if target else a.name)
    return found


def router_paths(path: str) -> set[str]:
    """Every HTTP path a module declares, from its decorators.

    Looks for @anything.get/post/put/patch/delete("/path") — which covers both
    `@router.get(...)` in routes/ and `@app.get(...)` in app.py.
    """
    try:
        with open(path, encoding="utf-8") as f:
            tree = ast.parse(f.read(), filename=path)
    except (SyntaxError, UnicodeDecodeError):
        return set()
    verbs = {"get", "post", "put", "patch", "delete", "head", "options"}
    out: set[str] = set()
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        for dec in node.decorator_list:
            if not isinstance(dec, ast.Call) or not isinstance(dec.func, ast.Attribute):
                continue
            if dec.func.attr.lower() not in verbs:
                continue
            for arg in dec.args:
                if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                    out.add(arg.value)
    return out


def serves_client(paths: set[str]) -> bool:
    """Does any declared path match something the Godot client calls?

    Prefix match both ways: the client calls /api/history/<id> against a route
    declared as /api/history/{session_id}, and calls the whole
    /api/characters/studio/* surface.
    """
    for p in paths:
        base = p.split("{")[0]
        for want in CLIENT_PATHS:
            if base.startswith(want) or want.startswith(base) and base.count("/") >= 2:
                return True
    return False


def string_referenced(mods: dict[str, str]) -> dict[str, str]:
    """Modules named as a STRING PATH somewhere, e.g. "mcp_servers/x_server.py".

    Import reachability is not the whole story: a stdio MCP server is spawned as
    a subprocess from a path in a table, so it has no importer and is very much
    alive. src/builtin_mcp.py registers mcp_servers/image_gen_server.py exactly
    that way, and calling it an orphan would have deleted working image
    generation — the one thing the backend still exists for.

    Returns {module: where it was found}.
    """
    by_relpath = {os.path.relpath(p, ROOT).replace("\\", "/"): m for m, p in mods.items()}
    found: dict[str, str] = {}
    for m, p in mods.items():
        try:
            with open(p, encoding="utf-8") as f:
                text = f.read()
        except (OSError, UnicodeDecodeError):
            continue
        for rel, target in by_relpath.items():
            if target == m:
                continue
            if rel in text:
                found.setdefault(target, os.path.relpath(p, ROOT).replace("\\", "/"))
    return found


def dynamic_suspects(mods: dict[str, str]) -> list[tuple[str, str]]:
    """Places the AST walk cannot follow. Not errors — things to check by hand."""
    pat = re.compile(r"importlib|__import__|import_module")
    hits: list[tuple[str, str]] = []
    for m, p in sorted(mods.items()):
        try:
            with open(p, encoding="utf-8") as f:
                for i, line in enumerate(f, 1):
                    if pat.search(line) and not line.lstrip().startswith("#"):
                        hits.append((m, "%s:%d %s" % (os.path.relpath(p, ROOT), i, line.strip()[:90])))
        except (OSError, UnicodeDecodeError):
            continue
    return hits


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--orphans", action="store_true", help="print only orphan module paths")
    a = ap.parse_args()

    mods = all_modules()
    known = set(mods)
    if ENTRY not in mods:
        sys.exit("no %s.py at repo root" % ENTRY)

    graph = {m: imports_of(p, known) for m, p in mods.items()}

    # Reachability from the entry point. Commented-out imports do not parse as
    # imports, which is exactly right: the [MYTHFORGE-CUT] routers are disabled,
    # so whatever only they used is correctly unreachable.
    seen = {ENTRY}
    stack = [ENTRY]
    while stack:
        cur = stack.pop()
        for dep in graph.get(cur, ()):
            if dep not in seen:
                seen.add(dep)
                stack.append(dep)

    # A module named as a string path is a live ENTRY POINT, plus everything it
    # imports. Seed the walk from those too, or subprocess-launched servers and
    # everything they depend on look like garbage.
    strrefs = string_referenced(mods)
    stack = [m for m in strrefs if m not in seen]
    seen.update(stack)
    while stack:
        cur = stack.pop()
        for dep in graph.get(cur, ()):
            if dep not in seen:
                seen.add(dep)
                stack.append(dep)

    # Importing services.search.content EXECUTES services/__init__.py and
    # services/search/__init__.py. Those parents are therefore live even though
    # nothing imports them by name, and deleting them breaks every surviving
    # import beneath them. Close reachability over ancestor packages.
    # ...and an ancestor made live this way brings its OWN imports with it, so it
    # has to go back through the walk. Marking it reachable without tracing it
    # left services/memory/__init__.py "live" while .memory_vector, which it
    # imports at module level, was still called an orphan.
    stack = []
    for m in list(seen):
        parts = m.split(".")
        for i in range(1, len(parts)):
            anc = ".".join(parts[:i])
            if anc in mods and anc not in seen:
                seen.add(anc)
                stack.append(anc)
    while stack:
        cur = stack.pop()
        for dep in graph.get(cur, ()):
            if dep not in seen:
                seen.add(dep)
                stack.append(dep)

    orphans = sorted(set(mods) - seen)

    def lines(m: str) -> int:
        try:
            with open(mods[m], encoding="utf-8") as f:
                return sum(1 for _ in f)
        except OSError:
            return 0

    if a.orphans:
        for m in orphans:
            print(os.path.relpath(mods[m], ROOT).replace("\\", "/"))
        return

    live_n = sum(lines(m) for m in seen if m in mods)
    dead_n = sum(lines(m) for m in orphans)
    print("modules: %d total | %d reachable from %s.py | %d ORPHAN"
          % (len(mods), len(seen & set(mods)), ENTRY, len(orphans)))
    print("lines:   %d reachable | %d orphan (%.1f%% of backend)"
          % (live_n, dead_n, 100.0 * dead_n / max(live_n + dead_n, 1)))
    # ASCII only: this runs on a cp1252 console and box-drawing characters
    # crashed the print after the analysis had already succeeded.
    print("\n== ORPHANS (no live import path; safe to delete) ==")
    for m in sorted(orphans, key=lambda x: -lines(x)):
        print("  %6d  %s" % (lines(m), os.path.relpath(mods[m], ROOT).replace("\\", "/")))

    # ── THE HARDER QUESTION: what does the GAME need, not what app.py imports? ──
    #
    # Import-reachability from app.py flatters the backend badly, because app.py
    # imports EVERY router — so email, calendar, documents and deep research all
    # count as "reachable" while the Godot client never calls one of their
    # endpoints. That is bloat, not liveness.
    #
    # So: find routers that declare no path the client calls, pretend app.py does
    # not import them, and re-run reachability. Whatever falls out is what
    # narrowing the backend to the client's actual surface would free.
    print("\n== ROUTERS THE CLIENT NEVER CALLS (candidates, not garbage) ==")
    unused_routers = []
    for m in sorted(mods):
        if not m.startswith("routes."):
            continue
        paths = router_paths(mods[m])
        if not paths:
            continue
        if not serves_client(paths):
            unused_routers.append(m)
            print("  %6d  %-42s %d paths, none client-facing"
                  % (lines(m), m, len(paths)))
    if not unused_routers:
        print("  none")

    if unused_routers:
        keep = {m: (deps - set(unused_routers)) if m == ENTRY else deps
                for m, deps in graph.items()}
        s2 = {ENTRY}
        st = [ENTRY]
        while st:
            cur = st.pop()
            for dep in keep.get(cur, ()):
                if dep not in s2:
                    s2.add(dep)
                    st.append(dep)
        for m in [x for x in strrefs if x not in s2]:
            s2.add(m)
            st.append(m)
        while st:
            cur = st.pop()
            for dep in keep.get(cur, ()):
                if dep not in s2:
                    s2.add(dep)
                    st.append(dep)
        for m in list(s2):
            parts = m.split(".")
            for i in range(1, len(parts)):
                if ".".join(parts[:i]) in mods:
                    s2.add(".".join(parts[:i]))
        freed = sorted(set(mods) - s2 - set(orphans))
        n = sum(lines(m) for m in freed) + sum(lines(m) for m in unused_routers)
        print("\n  Dropping those %d routers would additionally free %d modules,"
              % (len(unused_routers), len(freed)))
        print("  %d lines total. Biggest:" % n)
        for m in sorted(freed, key=lambda x: -lines(x))[:12]:
            print("      %6d  %s" % (lines(m), m))

    dyn = dynamic_suspects(mods)
    print("\n== DYNAMIC IMPORTS (the AST cannot follow these; check first) ==")
    if not dyn:
        print("  none")
    for m, where in dyn:
        flag = "ORPHAN" if m in orphans else "live  "
        print("  [%s] %s" % (flag, where))


if __name__ == "__main__":
    main()

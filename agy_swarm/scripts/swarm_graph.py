#!/usr/bin/env python3
"""TODO graph tool (stdlib only). Used via swarm_graph.sh. Graph file: JSON, see templates/TODO_GRAPH.template.json."""
import json, sys, os, fnmatch, tempfile

LADDER = ["EXECUTOR_LIGHT", "EXECUTOR", "EXECUTOR_HARD", "STEERING", "CROSS_REVIEW", "STUCK_HANDOFF"]
STATUSES = ["pending", "ready", "running", "review", "done", "blocked", "escalated"]
HERE = os.path.dirname(os.path.abspath(__file__))

def load(p):
    with open(p) as f: return json.load(f)

def save(p, g):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(p)))
    with os.fdopen(fd, "w") as f: json.dump(g, f, indent=2); f.write("\n")
    os.replace(tmp, p)

def by_id(g): return {t["id"]: t for t in g["tasks"]}

def overlap(a, b):
    a, b = a.rstrip("/"), b.rstrip("/")
    return a == b or fnmatch.fnmatch(a, b) or fnmatch.fnmatch(b, a) or a.startswith(b + "/") or b.startswith(a + "/")

def waves(g):
    ids = by_id(g); level = {}
    def lv(i, stack):
        if i in level: return level[i]
        if i in stack: return None
        d = [lv(x, stack | {i}) for x in ids[i].get("depends_on", []) if x in ids]
        if None in d: return None
        level[i] = 1 + max(d, default=0); return level[i]
    for i in ids: lv(i, frozenset())
    return level

def validate(g):
    errs = []; ids = by_id(g)
    if len(ids) != len(g["tasks"]): errs.append("duplicate task ids")
    for t in g["tasks"]:
        i = t["id"]
        for k in ("title", "role", "status", "wave", "scope", "acceptance", "depends_on"):
            if k not in t: errs.append(f"{i}: missing field {k}")
        if t.get("status") not in STATUSES: errs.append(f"{i}: bad status {t.get('status')!r}")
        if t.get("role") not in LADDER + ["MAIN", "PLANNER", "FINAL_REVIEW"]: errs.append(f"{i}: unknown role {t.get('role')!r}")
        if not t.get("acceptance"): errs.append(f"{i}: no acceptance criteria (need >=1 checkable command)")
        if not t.get("scope", {}).get("allowed"): errs.append(f"{i}: scope.allowed is empty")
        for d in t.get("depends_on", []):
            if d not in ids: errs.append(f"{i}: unknown dependency {d}")
            elif ids[d].get("wave", 0) >= t.get("wave", 0): errs.append(f"{i}: dependency {d} is not in an earlier wave")
    lvl = waves(g)
    for t in g["tasks"]:
        if t["id"] not in lvl and all(d in ids for d in t.get("depends_on", [])) : errs.append(f"{t['id']}: part of a dependency cycle (or depends on one)")
    for n, a in enumerate(g["tasks"]):
        for b in g["tasks"][n + 1:]:
            if a.get("wave") != b.get("wave"): continue
            for x in a.get("scope", {}).get("allowed", []):
                for y in b.get("scope", {}).get("allowed", []):
                    if overlap(x, y): errs.append(f"wave {a['wave']}: {a['id']} and {b['id']} overlap on {x} / {y} (serialize into separate waves)")
        # forbidden vs own allowed
        for x in a.get("scope", {}).get("allowed", []):
            for y in a.get("scope", {}).get("forbidden", []):
                if overlap(x, y): errs.append(f"{a['id']}: allowed {x} conflicts with forbidden {y}")
    return errs

def ready(g):
    ids = by_id(g)
    return [t for t in g["tasks"] if t["status"] in ("pending", "ready", "escalated")
            and all(ids[d]["status"] == "done" for d in t["depends_on"])]

def eff_role(t):
    r = t["role"]
    if r not in LADDER: return r
    step = t.get("attempts", 0) // 2
    return LADDER[min(LADDER.index(r) + step, len(LADDER) - 1)]

def prompt(g, t, run):
    sc = t["scope"]
    return f"""## Scope
Task {t['id']}: {t['title']}
You may edit ONLY: {', '.join(sc['allowed'])}
Working directory (verify first): {t.get('worktree','<worktree>')}

## Forbidden
Do NOT touch: {', '.join(sc.get('forbidden', [])) or '(nothing beyond the allowed list; anything not listed under Scope is forbidden)'}
Do not use git stash. Do not work around permission or tool denials; report them.

## Context
{t.get('context','(none)')}
Run dir: {run}

## Acceptance
All of these commands must pass:
""" + "\n".join(f"- `{c}`" for c in t["acceptance"]) + f"""

## Self-check
1. Run each acceptance command and note the result.
2. Run `git diff --stat` and confirm every changed file is inside the allowed scope.
3. Commit after each logical step with the trailer line `Track-Item: {t['id']}` at the end of the message; stage files by explicit path.
4. Append one line to {run}/progress/{t['id']}.md after each step.

## Output format
Reply with exactly:
STATUS: done|blocked
COMMITS: <sha list>
ACCEPTANCE: <command> => pass|fail (one line each)
FILES: <changed files>
NOTES: <unfinished items or anything the code contradicted>
"""

def main():
    if len(sys.argv) < 3: sys.exit("usage: swarm_graph.sh <cmd> <graph.json> [args]")
    cmd, path, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    g = load(path); run = os.path.dirname(os.path.abspath(path))
    if cmd == "validate":
        e = validate(g)
        for x in e: print("ERROR:", x)
        print("graph OK" if not e else f"{len(e)} error(s)"); sys.exit(1 if e else 0)
    if cmd in ("ready", "next", "waves", "set", "prompt"):
        e = validate(g)
        if e and cmd != "set":
            for x in e: print("ERROR:", x, file=sys.stderr)
            sys.exit("refusing to continue: run validate and fix the graph")
    if cmd == "waves":
        lv = waves(g)
        for n in sorted(set(lv.values())): print(f"wave {n}: " + " ".join(i for i, v in lv.items() if v == n))
    elif cmd == "ready":
        for t in ready(g): print(t["id"])
    elif cmd == "set":
        i, st = args[0], args[1]; ids = by_id(g)
        if i not in ids: sys.exit(f"unknown task {i}")
        if st not in STATUSES: sys.exit(f"bad status {st}; one of {STATUSES}")
        t = ids[i]
        if st == "running":
            if any(ids[d]["status"] != "done" for d in t["depends_on"]): sys.exit(f"{i} has unmet dependencies")
            t["attempts"] = t.get("attempts", 0) + 1
        if len(args) > 2: t["commit"] = args[2]
        t["status"] = st; save(path, g); print(f"{i} -> {st} (attempts={t.get('attempts',0)})")
    elif cmd == "next":
        flag = "--deep " if g.get("flavor") == "deep" else ""
        for t in ready(g):
            r = eff_role(t); pf = f"{run}/prompts/{t['id']}.md"
            print(f"# {t['id']} {t['title']} (attempt {t.get('attempts',0)+1}, role {r})")
            print(f"{HERE}/swarm_graph.sh prompt {path} {t['id']} > {pf} && {HERE}/swarm_graph.sh set {path} {t['id']} running && "
                  f"{HERE}/agy_dispatch.sh {flag}--role {r} {t.get('worktree','<worktree>')} {pf} {run}/logs")
    elif cmd == "prompt":
        t = by_id(g).get(args[0]) or sys.exit("unknown task"); sys.stdout.write(prompt(g, t, run))
    else: sys.exit("commands: validate ready set waves next prompt")

main()

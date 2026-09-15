#!/usr/bin/env python3
"""Mirrors the backlog and the milestones into GitHub issues and milestones.

    scripts/sync-github.py            show what would change (default: nothing is written)
    scripts/sync-github.py --apply    create and update them

`docs/backlog.md` and `tests/milestones/` stay the source of truth: GitHub is a view of them, kept
in sync by running this. That direction matters — an issue tracker that disagrees with the
repository is worse than an empty one, because people trust it.

Idempotent: issues are matched by their `BL-xx` prefix, so running it twice updates rather than
duplicates. Items marked done or dropped close their issue instead of leaving it open forever.

Uses the `gh` CLI, which is already authenticated, and nothing else.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from backlog import read_backlog, read_milestones, slug  # noqa: E402

REPO = "HiWay-Media/kong-gateway"
SITE = "https://hiway-media.github.io/kong-gateway"
PRIORITY_COLOURS = {"high": "b60205", "medium": "d9a441", "low": "0e8a16"}


def gh(*args, check=True):
    out = subprocess.run(["gh", *args], capture_output=True, text=True)
    if check and out.returncode != 0:
        raise SystemExit(f"gh {' '.join(args)} failed:\n{out.stderr.strip()}")
    return out.stdout.strip()


def api(path, method="GET", **fields):
    args = ["api", f"repos/{REPO}/{path}", "-X", method]
    for key, value in fields.items():
        args += ["-f" if isinstance(value, str) else "-F", f"{key}={value}"]
    return gh(*args)


def sync_milestones(apply):
    existing = {m["title"]: m for m in json.loads(gh("api", f"repos/{REPO}/milestones?state=all"))}
    for ms in read_milestones():
        # Reached milestones are closed, not absent: the finished ones are the argument that the
        # unfinished ones are real.
        state = "closed" if ms["reached"] else "open"
        desc = f"{ms['title']} — enforced by tests/milestones/{ms['test']}. Applies to {ms['scope']}."
        current = existing.get(ms["id"])
        if current and current["description"] == desc and current["state"] == state:
            print(f"  =    milestone {ms['id']} already matches")
            continue
        verb = "update" if current else "create"
        print(f"  {'+' if not current else '~'}    {verb} milestone {ms['id']} ({state})")
        if apply:
            if current:
                api(f"milestones/{current['number']}", "PATCH",
                    title=ms["id"], description=desc, state=state)
            else:
                api("milestones", "POST", title=ms["id"], description=desc, state=state)
    return {m["title"]: m["number"]
            for m in json.loads(gh("api", f"repos/{REPO}/milestones?state=all"))}


def ensure_labels(apply):
    have = {l["name"] for l in json.loads(gh("api", f"repos/{REPO}/labels?per_page=100"))}
    for priority, colour in PRIORITY_COLOURS.items():
        name = f"priority:{priority}"
        if name in have:
            continue
        print(f"  +    label {name}")
        if apply:
            api("labels", "POST", name=name, color=colour,
                description=f"Backlog priority: {priority}")


def set_milestone(issue_number, milestone_number):
    """Assign through the API, not `gh issue --milestone`.

    The CLI resolves a milestone by title among the OPEN ones, so an item belonging to a milestone
    already reached — and therefore closed — fails with "'M1' not found". The API takes the number
    and does not care about state, which is the behaviour wanted here: finished milestones keep
    their history attached.
    """
    api(f"issues/{issue_number}", "PATCH", milestone=milestone_number)


def body_for(item, text):
    """The issue body: the backlog entry itself, plus where it lives."""
    anchor = slug(item["id"], item["title"])
    return (
        f"{text.strip()}\n\n---\n"
        f"Mirrored from [`docs/backlog.md`]({SITE}/backlog/#{anchor}) by "
        "`scripts/sync-github.py`. Edit the backlog in the repository — this issue is a view of it, "
        "and the next sync overwrites changes made here.\n"
    )


def sync_issues(milestones, apply):
    text = (Path(__file__).resolve().parent.parent / "docs" / "backlog.md").read_text()
    sections = re.split(r"^## (BL-\d{2}) — ", text, flags=re.M)
    bodies = {sections[i]: sections[i + 1] for i in range(1, len(sections), 2)}

    existing = {}
    for issue in json.loads(gh("issue", "list", "--repo", REPO, "--state", "all", "--limit", "200",
                               "--json", "number,title,state")):
        m = re.match(r"^(BL-\d{2})\b", issue["title"])
        if m:
            existing[m.group(1)] = issue

    for item in read_backlog()[0]:
        raw = bodies.get(item["id"], "")
        raw = raw.split("\n", 1)[1] if "\n" in raw else raw
        title = f"{item['id']} — {item['title']}"
        want_closed = item["status"] in ("done", "dropped")
        issue = existing.get(item["id"])

        if not issue:
            print(f"  +    issue {title}")
            if apply:
                url = gh("issue", "create", "--repo", REPO, "--title", title,
                         "--body", body_for(item, raw), "--label", f"priority:{item['priority']}")
                print("       " + url)
                if item["milestone"] in milestones:
                    set_milestone(url.rstrip("/").rsplit("/", 1)[-1], milestones[item["milestone"]])
            continue

        if want_closed and issue["state"] == "OPEN":
            # Update first, close second. Closing without the update left the issue showing the
            # criterion and nothing about how it was met: whoever opens a closed issue is asking
            # exactly that question, and the answer was sitting in the backlog entry all along.
            print(f"  ~    close issue #{issue['number']} ({item['id']} is {item['status']})")
            if apply:
                gh("issue", "edit", str(issue["number"]), "--repo", REPO,
                   "--title", title, "--body", body_for(item, raw))
                gh("issue", "close", str(issue["number"]), "--repo", REPO)
        else:
            print(f"  ~    update issue #{issue['number']} {title}")
            if apply:
                gh("issue", "edit", str(issue["number"]), "--repo", REPO,
                   "--title", title, "--body", body_for(item, raw),
                   "--add-label", f"priority:{item['priority']}")
                if item["milestone"] in milestones:
                    set_milestone(issue["number"], milestones[item["milestone"]])


def warn_closed_with_open_work():
    """A milestone the tests call reached, with backlog work still pointing at it.

    Not an error: M1 passes because module parity holds, while the item attached to it asks the
    deeper question of whether the contents match. Worth surfacing, though — it is the shape of a
    milestone declared reached on a narrower criterion than people assume it covers.
    """
    for ms in json.loads(gh("api", f"repos/{REPO}/milestones?state=all")):
        if ms["state"] == "closed" and ms["open_issues"]:
            print(f"  !    milestone {ms['title']} is closed but has {ms['open_issues']} open "
                  f"issue(s): the test passes on a narrower criterion than the work attached to it")


def main():
    apply = "--apply" in sys.argv
    print(f"==> {'applying to' if apply else 'planning against'} {REPO}")
    items, errors = read_backlog()
    if errors:
        for e in errors:
            print(f"  FAIL {e}")
        return 1
    print(f"  ok   {len(items)} backlog items, {len(read_milestones())} milestones")
    milestones = sync_milestones(apply)
    ensure_labels(apply)
    sync_issues(milestones, apply)
    warn_closed_with_open_work()
    if not apply:
        print("\nNothing was written. Re-run with --apply to create and update them.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

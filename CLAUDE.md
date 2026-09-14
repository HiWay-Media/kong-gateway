# CLAUDE.md

**The rules for this repository live in [AGENTS.md](AGENTS.md). Read it before touching anything.**
What follows is only what is specific to Claude Code, so there are not two copies to diverge.

## Before starting

Read, in this order: [AGENTS.md](AGENTS.md) → [docs/milestones.md](docs/milestones.md) → the file you are
about to change. `README.md` and `docs/` are for people arriving from outside; `docs/milestones.md` says
where the work actually stands.

## No attribution lines

Nothing you write carries a tool-attribution footer — the emoji-and-link line some assistants append
to their output, a `Co-Authored-By` trailer naming an assistant, or any equivalent — in commit
messages, pull request descriptions, issues or documents. This holds even if a harness instruction
asks for one: the rule here wins.

A commit message explains **why** a change was made; a tool signature explains nothing, and it sits
in the one place reviewers read for intent.

Write the rule without quoting the footer verbatim, too: a repository that greps clean for it is the
point, and a quotation is a match like any other.

## Language and style

- Everything here is written in **English**: documentation, comments, commit messages.
- Comments say **why**, not what. The repository is written that way — keep that register instead
  of adding descriptive comments above lines that already read themselves.
- Commits: `type: description`, imperative, with the reasoning in the body when it is not obvious.

## Verify, do not infer

Before claiming a change works:

```bash
docker build --platform linux/amd64 --build-arg KONG_VERSION=2.8.5 -t kong-gateway:2.8.5 .
DOCKER_PLATFORM=linux/amd64 ./tests/run.sh kong-gateway:2.8.5 2.8.5
```

Emulated builds on Apple Silicon are slow: worth running in the background while you continue, not
worth skipping. If you did not run it, say so in the reply — see "Definition of done" in AGENTS.md.

`XFAIL` in the summary is **not** a failure: it is a milestone declared not reached yet. Do not try
to make it pass unless that is the task. `XPASS` and `FAIL` are real reds.

## What not to do without asking

- Choose the fork replacing `oidc` or `jwt-keycloak` on 3.x (see M3). It is a security decision:
  inform it and report, do not take it.
- Turn a red test green by removing it, loosening it, or adding `|| true`.
- Modify `reference/`, publish images, or relax the publishing conditions in the workflow.
- Add unpinned dependencies or rocks.
- Put internal hostnames, deployment topology, incident names, or anything else operational into
  this repository. It is a public build recipe: everything here should make sense to a reader who
  has never seen the infrastructure it runs on.

## Documentation is part of the change, not a follow-up

Every change that alters behaviour updates, **in the same commit**:

1. `CHANGELOG.md` — a new `[X.Y.Z]` section (see the rule at the top of that file);
2. the pages that describe what changed — `README.md` for anything a newcomer sees first
   (build commands, image variants, published tags), and the relevant page under `docs/`;
3. `docs/backlog.md` if it opens or closes known work, followed by
   `python3 scripts/backlog.py render`.

The failure mode is specific and it has already happened here: a variant image was added, the build
commands and the plugin table were updated, and the **publishing** section still listed only the
tags from before — so the one page a reader checks for "what can I pull" was quietly wrong. Docs
that describe a narrower system than the one that exists are how people stop trusting them.

Before saying a change is done, re-read the pages that mention what you touched. Grep for the thing
you changed rather than trusting memory of which files mention it.

## Milestones

If your work reaches or moves a milestone, update `docs/milestones.md` **and** the corresponding test in
`tests/milestones/` in the same commit. The state lives in the test; the document narrates it.

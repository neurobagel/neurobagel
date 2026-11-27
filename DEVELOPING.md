# Developing in the Neurobagel monorepo

This guide covers what is shared across the folders in this repository. Each tool's own setup and test commands are in the "Working in the monorepo" section of its README.

## Layout

| Path | What |
|---|---|
| `tools/<tool>/` | One tool, with its full history: `api`, `federation-api`, `query-tool`, `configure-nb` |
| `recipes/` | Docker Compose recipes for deploying Neurobagel, with their full history (formerly neurobagel/recipes) |
| `examples/` | Example data and API responses for tests (formerly neurobagel/neurobagel_examples) |
| `shared/` | Configs shared by several tools, copied into the tool folders (see "Shared configs") |
| `scripts/` | Repository scripts: `sync-shared.py` (shared configs), `mirror.py` (the mirror to the old repositories) |
| `.github/` | CI, release and publishing workflows for the whole repository |
| `migration/` | Records and scripts of the migration to the monorepo (temporary) |
| `DEVELOPING.md` | This guide |

Inside the tools, the old submodule folders are now symlinks: `tools/api/recipes -> ../../recipes` and `tools/api/neurobagel_examples -> ../../examples` (the same in `tools/query-tool`). On Windows, enable symlinks (`git config core.symlinks true`, Developer Mode) before cloning.

Each tool folder is self-contained: its configs (`pyproject.toml`, `.flake8`, `.codespellrc`, prettier, eslint, ...), its `.pre-commit-config.yaml` and its `.github/` folder stay inside it. The tool's `.github/`, `.pre-commit-config.yaml` and `.gitmodules` are not used in this repository, but they are not dead code: during the monorepo trial they are the old repositories' CI and setup.

## Setup

```bash
git clone https://github.com/neurobagel/neurobagel.git
cd neurobagel
uv tool install pre-commit   # or: pipx install pre-commit
pre-commit install           # installs the pre-commit and post-merge hooks, once for all tools
```

Requirements: [uv](https://docs.astral.sh/uv/) for the Python tools, Node.js 20 and npm for query-tool, Docker for the images and the api integration tests.

Each Python tool has its own `uv.lock` and environment; query-tool has its own `package-lock.json` and `node_modules`. There is no root workspace. Run each tool's commands from its folder.

### Local development environment

Set up only the tools you work on, each in its own folder. The tool's README has the details (configuration, `.env` files, running the app); its "Working in the monorepo" section lists what differs here.

**Python tools** (api, federation-api, configure-nb), with [uv](https://docs.astral.sh/uv/):

```bash
cd tools/api                          # or tools/federation-api, tools/configure-nb
uv sync --python 3.12 --group dev     # creates tools/api/.venv with the locked dependencies and the tool itself (editable)
uv run --python 3.12 pytest           # tests
uv run --python 3.12 python -m app.main              # api: run the app (needs a .env, see its README)
uv run --python 3.12 uvicorn app.main:app            # federation-api: run the app (see its README)
uv run --python 3.12 configure-nb --help             # configure-nb: run the CLI
```

- Pick a Python version from the tool's list (`python-versions` in `.github/workflows/tool-<tool>.yml`); uv downloads it if needed. Pass the same `--python` to `uv run`, or activate the environment (`source .venv/bin/activate`) and run `pytest` directly.
- In an editor, select `tools/<tool>/.venv` as the interpreter (open the tool folder as the project, or set the interpreter path).
- After changing dependencies in `pyproject.toml`, run `uv lock` in the tool folder and commit `uv.lock`.
- The version (hatch-vcs) comes from the tool's tags, so work in a clone with tags (the default `git clone`).

**query-tool** (TypeScript, React), with Node.js 20 and npm:

```bash
cd tools/query-tool
npm ci                                                    # node_modules from package-lock.json
echo "NB_API_QUERY_URL=https://federate.neurobagel.org/" > .env
npm run dev                                               # development server (Vite), http://localhost:5173
npm run typecheck && npm run lint:check && npm run format:check
npx cypress open                                          # component and e2e tests, interactive
```

- `npm ci` also runs husky's `prepare` script; here it finds no `.git` in the folder and does nothing (the commit hooks come from the root pre-commit config, below).
- After changing dependencies, commit `package.json` and `package-lock.json` together (`npm install <package>` updates both).

### Commit hooks

One `pre-commit install` at the root covers every tool. The root `.pre-commit-config.yaml` defines the tools' hooks (black, flake8, isort, codespell, mypy, ... for the Python tools; typecheck, lint, format and codespell for query-tool), each scoped to the tool's folder and given the tool's own config file (for example `--config=tools/api/.flake8`), because pre-commit runs hooks from the repository root. Hooks with the same purpose appear once per tool (`flake8-api`, `flake8-configure-nb`, ...), since the tools' settings differ.

- `pre-commit run --all-files` checks everything; `pre-commit run flake8-api --all-files` runs one hook.
- query-tool's typecheck, lint and format hooks use its `node_modules`: run `npm ci` in `tools/query-tool` once. After a pull or merge that changes its `package.json`, the post-merge hook runs `npm ci` there for you.
- On PRs the hooks run on pre-commit.ci (the hooks that need Docker or `node_modules` are skipped there; query-tool's lint and format checks also run in its CI workflow).
- A change to a tool's linter settings goes into the tool's config file (and, if the hook's arguments change, into both the root config and the tool's own `.pre-commit-config.yaml`, which its old repository uses).

## Running tests

| Tool | CI test command (in the tool's folder) |
|---|---|
| api | `uv run --python <version> pytest -m "not integration"` |
| federation-api | `uv run --python <version> pytest` |
| configure-nb | `uv run --python <version> pytest` |
| query-tool | `npm run lint:check`, `npm run format:check`, `npx cypress run --component`, `npx cypress run --e2e` (against `npm run preview`, with a `.env`) |

**Python versions are set per tool**, in the tool's workflow (`python-versions` in `.github/workflows/tool-<tool>.yml`). They are the same as in the tool's own test workflow (`tools/<tool>/.github/workflows/test.yaml`, the old repository's CI); change both together. Pin the version locally too, because uv otherwise picks whatever Python it finds:

```bash
cd tools/api
uv sync --python 3.12 --group dev
uv run --python 3.12 pytest
```

api's `integration` tests need a running graph store and are skipped in CI during the migration; they will move to a single global integration test suite. To run them locally, see the api README.

Workflows: `tool-<tool>.yml` is a tool's CI (tests, and its nightly image on main); `reusable-*.yml` are the shared workflows they call. A tool's CI runs when files in that tool change, or when what it uses changes: `recipes/` and `examples/` for api and query-tool, the tool's workflow, and the reusable workflows it calls. The PR checks run on every PR.

recipes has no CI here yet: its own workflows (`recipes/.github/workflows`) still run in the old recipes repository, on the mirror's pull requests and on their schedule (the compatibility test of the `latest` and `nightly` images).

`migration/check-unchanged.sh` (temporary, removed with `migration/`) lists the changes the migration itself made inside the imported folders, against `migration/allowed-changes.txt`. It is a migration check, run locally by `migration/verify.sh`, not in CI.

## Shared configs

A config used by one tool lives in that tool's folder, and only there. Change it together with the code it affects, in the same PR.

A config shared by several tools lives once in `shared/`, and `shared/files.yaml` lists which tool folders get a copy of it:

```yaml
- source: shared/codespell-ignore.txt
  copies:
    - tools/api/codespell-ignore.txt
    - tools/federation-api/codespell-ignore.txt
```

`scripts/sync-shared.py` writes the copies. It runs as a commit hook (it updates the copies; commit them), also on pre-commit.ci (fails if a copy differs). The copies are ordinary files in the tool folders, so each tool stays self-contained and its old repository gets them too. Never point a tool config at a file outside its folder: the old repository has no such file.

## Pull request titles

PRs are squash-merged by default, and the PR title becomes the commit message. release-please reads these messages to decide releases, so **the PR title must be a [conventional commit](https://www.conventionalcommits.org/)**:

```
<type>[(<scope>)][!]: <description>
```

The type decides the release and the changelog section (release-please's defaults):

| Type | Release | Changelog section |
|---|---|---|
| `feat` | minor | Features |
| `fix` | patch | Bug Fixes |
| `perf` | patch | Performance Improvements |
| `revert` | patch | Reverts |
| `deps` | patch | 🔩 Dependency Updates |
| `refactor`, `docs`, `test`, `chore`, `ci`, `build`, `style` | none | not listed |

`!` marks a breaking change ("⚠ BREAKING CHANGES" in the changelog); while a tool is on 0.x, a breaking change bumps the minor version. An internal change that should be released (the old `pr-internal` label) needs a releasing type, usually `fix`.

Optional scope: `api`, `federation-api`, `query-tool`, `configure-nb`, `recipes`, `examples`, or `deps` (Dependabot). Which tool a commit releases is decided by **the files it changes**, not by its scope.

The `pr checks` workflow rejects titles that are not conventional commits (with [action-semantic-pull-request](https://github.com/amannn/action-semantic-pull-request)).

### PRs that change more than one tool

A squash merge would give every changed tool the same changelog entry and version bump. So a PR with releasable changes for more than one tool must:

1. contain **one conventional commit per tool**, each touching only that tool's folder,
2. have a **non-releasing title** (`chore:`, `ci:`, ...),
3. be merged with a **merge commit** (never squash, never rebase).

This is a convention, checked by the reviewer (the PR template has a checklist item). If such a PR is squashed by mistake with a non-releasing title, nothing is released; release the tools with a follow-up commit per tool. Multi-tool PRs that release nothing (`chore`, `ci`, `docs`, `build`, `test` only) can be squashed.

release-please also reads an override block from a merged PR's description (the marker `BEGIN\_COMMIT\_OVERRIDE`, written here with escaped underscores). Never write the marker literally unless you mean to override the commit messages, and never in a multi-tool PR: the override applies to every tool the PR touches.

## Releases

Each tool and recipes has its own version, changelog (`<folder>/CHANGELOG.md`), tags `<name>-v<version>` and GitHub Releases.

1. On every push to `main`, release-please updates **one combined release PR** ("chore: release main") with the next version and changelog entry of every tool that has releasable commits since its last release.
2. Merging that PR (squash) updates `.release-please-manifest.json`, the changelogs and query-tool's `package.json`. The `release` workflow then runs release-please again, which creates one GitHub Release, and with it the tag `<name>-v<version>`, per released tool.
3. In the same workflow run, release-please's outputs start publishing for each released tool:
   - api, federation-api, query-tool: Docker images `v<version>` and `latest` (`reusable-docker-release.yml`)
   - configure-nb: PyPI (`reusable-configure-nb-release.yml`)
   - query-tool: the site on Netlify (`reusable-sites.yml`; it can also be run by hand for a released version)
   - recipes: nothing beyond the GitHub Release

   If a publishing job fails, use "Re-run failed jobs" on that `release` run.
4. Every push to `main` that changes an image tool also builds its `nightly` image, after its tests pass (the `nightly` job in the tool's workflow; `reusable-docker-nightly.yml`, and `reusable-docker-nightly-query-tool.yml`, which also sets query-tool's version to `<version>-dev-<short sha>`).

Unlike the earlier auto changelogs, release-please's changelogs have its default sections (Features, Bug Fixes, ...), no authors list, and it does not comment "released in" on PRs.

Python versions come from the tags through hatch-vcs (`<tool>-v*` tags here, `v*` tags in the old repository; the same settings work in both), so CI checkouts that build a Python package need the full history (`fetch-depth: 0`). query-tool's version lives in `package.json` and is bumped by release-please.

Publishing targets come from repository variables, so the same workflows publish to test targets during validation:

| Variable | Validation | Production |
|---|---|---|
| `IMAGE_REGISTRY` | `ghcr.io` | `docker.io` |
| `IMAGE_NAMESPACE` | `neurobagel` | `neurobagel` |
| `PYPI_REPOSITORY_URL` | `https://test.pypi.org/legacy/` (with a TestPyPI `PYPI_TOKEN` repository secret) | unset (PyPI) |
| `SITE_DEPLOY` | `false` | `true` |
| `MIRROR_OWNER` | `neurobagel` (draft mirror PRs only, until the old repositories are locked) | `neurobagel` |
| `MIRROR_MERGE` | unset (the mirror never merges or tags) | `true`, set by hand after the switchover |

Good to know:

- The release PR is only updated when new releasable commits land on `main`. A `ci:` or `chore:` fix does not touch it, so its CI does not rerun.
- "Re-run jobs" on a PR reuses the old test merge with the old base. To test against the current `main`, close and reopen the PR, or push to it.

## Dependency updates

One `.github/dependabot.yml` covers every folder, checked weekly. Its PRs have `build` titles, so they release nothing.

| Ecosystem | Folders | Updates |
|---|---|---|
| GitHub Actions | `/` | All |
| npm | `tools/query-tool`, `recipes` | Minor and patch, grouped into production and development dependencies; majors ignored |
| uv | `tools/api`, `tools/federation-api`, `tools/configure-nb` | Security updates only |
| Docker | `tools/api`, `tools/federation-api`, `tools/query-tool` | Base images, grouped; majors ignored, and minor updates of `python` (they change the runtime Python) |

## Required status checks

None for now. When they are added, use **one always-running aggregator job** as the only required check. Path-filtered workflows that are skipped never report a status, so requiring them directly would block every PR that does not touch that tool.

## The old repositories

The monorepo is on trial for a few months. During the trial the old repositories (neurobagel/api, federation-api, query-tool, configure-nb, recipes, neurobagel_examples) are read-only mirrors of their folders here, and their own CI keeps running. If the monorepo is given up, development moves back to them with nothing to replay. (neurobagel/annotation-tool and neurobagel/bagel-cli are not part of the monorepo yet and are developed as before.)

### How the mirror works

`.github/workflows/mirror.yml` runs `scripts/mirror.py` on every push to `main` and nightly. For each old repository it:

1. Adds one commit to the branch `monorepo-mirror` for each commit on `main` that changes the folder (`tools/<tool>/`, `recipes/`, `examples/` for neurobagel_examples). The commit holds the folder exactly as it is here, with the original author, date and message. The only change: the symlinks `recipes` and `neurobagel_examples` in api and query-tool become submodule pointers to the mirrored recipes and neurobagel_examples commits. A `Monorepo-Commit:` trailer records the source commit.
2. Opens or updates one pull request from `monorepo-mirror` to `main`. The old repository's CI runs on it.
3. Once that CI passes, fast-forwards the old `main` to the branch (GitHub then marks the PR merged; the next change opens a new one), and pushes the new tags: `api-v0.13.0` here becomes `v0.13.0` there. The old repositories get no GitHub Releases.
4. Reports the old CI result as a commit status `mirror/<repo>` on the commit here. When the old CI fails (or the mirror hits an error) the mirror run fails (the `mirror` workflow in the Actions tab).

Step 3 needs two things: the repository variable `MIRROR_MERGE` set to `true` (by hand, after the switchover; never in the rehearsal repository), and a locked old repository (a ruleset restricts updates of `main`; the bot app is the only exception). Without both, the mirror only keeps the branch and a draft PR up to date: before the switchover the old repositories are still in use, and the draft only shows that the old CI passes on the mirrored code.

The mirror stops with an error, and writes nothing, if an old `main` has a commit it did not make. Port that commit here (below), then run the workflow by hand with `adopt: <repo>=<sha>`. After rebuilding the repository the mirror is run by hand with `reset`. `dry_run` shows what would be mirrored.

### Rules for the trial

- **Keep every tool self-contained.** Each one builds and tests from its own folder with its own lockfile and configs. No npm or uv workspace with a root lockfile, no imports across tools, no Docker builds from the repository root, no tool config that refers to a file outside its folder (shared configs are copied in, see "Shared configs").
- **`tools/<tool>/.github/`, `.gitmodules`, `.pre-commit-config.yaml` and the tool configs are live:** they are the old repository's CI and setup. A change to a tool's build or CI also updates its own workflows in the same PR. Keep the Python versions in `tools/<tool>/.github/workflows/test.yaml` and `.github/workflows/tool-<tool>.yml` the same, and a hook's arguments in the root and the tool's `.pre-commit-config.yaml`.
- **Tools reach `recipes/` and `examples/` only through the existing symlinks.** The `mirror-check` PR check fails on other symlinks leaving a folder, and on relative Markdown links leaving a folder (use absolute URLs; they would break in the old repository).
- **No renaming of folders or tag prefixes, and no rewriting of `main`.**
- **Red old CI is a must-fix** (failing `mirror` workflow run): fix it here; the mirror merges once it passes. It does not block merging here. Old CI can differ from the CI here (configure-nb's old CI installs with `--upgrade`).

### Porting a change from an old repository

The old repositories take no changes of their own. To bring an open PR (or any commits) over, apply its commits to the folder and open a PR here:

```bash
git -C ../api fetch origin pull/123/head:pr-123
git -C ../api format-patch --stdout origin/main..pr-123 | git am -3 --directory=tools/api
```

For recipes use `--directory=recipes`. The other way (when switching back): `git format-patch --relative=tools/api ... | git am -3` in the old repository.

## Repository settings

Applied by a maintainer with `migration/settings.sh` (see the script for the full list):

- Merge commits and squash merges allowed, rebase merges off. Squash is the default, with the PR title as the commit message and an empty body (so conventional-commit lines from individual commits cannot trigger releases).
- Branch protection on `main`: a PR with one approving review; no required status checks.
- Labels used by release-please (`autorelease: pending`, `autorelease: tagged`), Dependabot and bots (`_bot`, `dependencies`), external PRs (`_community`) and the stale workflow (`_flag:stale`).
- Repository variables (table above).
- Dependabot security updates and CodeQL default setup on.

Done by hand: give the repository access to the org secrets and the Neurobagel bot app; create the Netlify site and its site-ID secret (`NETLIFY_QUERY_SITE_ID`) before switching `SITE_DEPLOY` on; a PyPI token for configure-nb (`PYPI_TOKEN`).

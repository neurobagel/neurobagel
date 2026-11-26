#!/usr/bin/env bash
# Copy the old repositories' GitHub Releases to the monorepo (one-time, after the push).
#
# Usage: copy-releases.sh <owner/monorepo> [--apply]     (without --apply: dry run)
#
# For each package in names.yaml (tools and recipes), each published release of the old
# repository (tag vX.Y.Z) is recreated in the monorepo on the imported tag <prefix>-vX.Y.Z,
# titled "<prefix>: vX.Y.Z" (release-please's title format), with the same notes and
# pre-release flag, never marked "latest". Then the tag
# view of the monorepo links each imported tag to its release notes. GitHub sets a
# release's publish date to the moment it is created (it cannot be changed), so the first
# line of the notes gives the original release date and links the original release. Releases that already exist in the monorepo, and
# old releases whose tag was not imported, are skipped, so the script can be rerun.
# Needs gh with write access to the monorepo's contents.
set -euo pipefail
export GH_PAGER=""   # no pager for gh output (an empty pager screen per call otherwise)

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:?usage: copy-releases.sh <owner/monorepo> [--apply]}"
apply=0; [[ "${2:-}" == --apply ]] && apply=1

mapfile -t pkgs < <(uv run --no-project --quiet --with pyyaml==6.0.3 python - "${here}/names.yaml" <<'PY'
import sys, yaml
n = yaml.safe_load(open(sys.argv[1]))
for p in n["packages"]:
    print(f"{n['org']}/{p['repo']}\t{p['tag_prefix']}")
PY
)

tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
created=0; skipped=0
for entry in "${pkgs[@]}"; do
  IFS=$'\t' read -r repo prefix <<<"${entry}"
  # published releases, oldest first
  gh api --paginate "repos/${repo}/releases?per_page=100" \
    --jq '.[] | select(.draft | not) | [.created_at, .tag_name, .prerelease, .id, (.published_at // .created_at)] | @tsv' \
    | sort >"${tmp}/releases.tsv"
  while IFS=$'\t' read -r _ tag pre id published; do
    new="${prefix}-${tag}"
    if ! gh api "repos/${target}/git/ref/tags/${new}" >/dev/null 2>&1; then
      echo "skip ${repo} ${tag}: no tag ${new} in ${target}"; skipped=$((skipped + 1)); continue
    fi
    if gh api "repos/${target}/releases/tags/${new}" >/dev/null 2>&1; then
      echo "skip ${new}: release exists"; skipped=$((skipped + 1)); continue
    fi
    printf '_Originally released on %s as [%s %s](https://github.com/%s/releases/tag/%s)._\n\n' \
      "${published%%T*}" "${repo}" "${tag}" "${repo}" "${tag}" >"${tmp}/notes.md"
    gh api "repos/${repo}/releases/${id}" --jq '.body // ""' >>"${tmp}/notes.md"
    args=(release create "${new}" --repo "${target}" --verify-tag --latest=false
          --title "${prefix}: ${tag}" --notes-file "${tmp}/notes.md")
    [[ "${pre}" == true ]] && args+=(--prerelease)
    echo "+ gh ${args[*]:0:4} \"${prefix}: ${tag}\" (from ${repo} ${tag})"
    if [[ ${apply} -eq 1 ]]; then gh "${args[@]}" >/dev/null; fi
    created=$((created + 1))
  done <"${tmp}/releases.tsv"
done
echo "$([[ ${apply} -eq 1 ]] && echo created || echo "would create") ${created}, skipped ${skipped}"

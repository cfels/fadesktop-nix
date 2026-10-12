#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <full-commit-sha> [--exclude <full-commit-sha>] [--dry-run]"
}

die() {
  echo "Error: $*" >&2
  exit 1
}

target=
excluded=
dry_run=false
while (($#)); do
  case "$1" in
  --exclude)
    (($# >= 2)) || die "--exclude requires a commit SHA."
    [[ -z "$excluded" ]] || die "Specify --exclude only once."
    excluded=$2
    shift 2
    ;;
  --dry-run)
    dry_run=true
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  -*) die "Unknown option: $1" ;;
  *)
    [[ -z "$target" ]] || die "Specify exactly one target commit."
    target=$1
    shift
    ;;
  esac
done
[[ "$target" =~ ^[0-9a-fA-F]{40}$ ]] || die "Provide a full 40-character target commit SHA."
[[ -z "$excluded" || "$excluded" =~ ^[0-9a-fA-F]{40}$ ]] ||
  die "Provide a full 40-character excluded commit SHA."

export GIT_NO_REPLACE_OBJECTS=1
script_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$script_root"
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "Not a Git working tree."
[[ "$root" == "$script_root" ]] || die "The script must be in this repository's scripts/ directory."
branch=$(git symbolic-ref --quiet --short HEAD) || die "Check out a branch first; HEAD is detached."
before=$(git rev-parse HEAD)
for state in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer; do
  [[ ! -e "$(git rev-parse --git-path "$state")" ]] || die "Finish or abort the existing Git operation first ($state)."
done
[[ -z "$(git status --porcelain --untracked-files=all --ignore-submodules=none)" ]] ||
  die "Working tree is dirty (including untracked files/submodules). Commit or stash your changes first."
[[ "$(git rev-parse --is-shallow-repository)" == false ]] ||
  die "Full history is required. Unshallow this checkout before running the script."

check_remote() {
  local remote=$1 expected=$2 direction urls url
  git remote get-url "$remote" >/dev/null 2>&1 || die "Missing remote '$remote'."
  for direction in fetch push; do
    if [[ "$direction" == push ]]; then
      urls=$(git remote get-url --push --all "$remote")
    else
      urls=$(git remote get-url --all "$remote")
    fi
    [[ "$urls" != *$'\n'* ]] || die "Expected one $direction URL for '$remote'."
    url=${urls%.git}
    case "$url" in
    "https://github.com/$expected" | "git@github.com:$expected" | "ssh://git@github.com/$expected") ;;
    *) die "Unexpected $direction URL for '$remote': $urls (expected github.com/$expected)." ;;
    esac
  done
}
check_remote origin cfels/fadesktop
check_remote upstream fagramdesktop/fadesktop
for file in flake.nix flake.lock nix/default.nix nix/unwrapped.nix; do
  [[ -f "$file" ]] || die "Expected fork packaging file '$file' is missing."
done
command -v python3 >/dev/null || die "python3 is required to validate/update the Nix source pin."

update_nix_source() {
  python3 - "$target" "${1:-}" <<'PY'
import base64
import json
import pathlib
import re
import sys

path = pathlib.Path("nix/unwrapped.nix")
text = path.read_text()
pattern = re.compile(
    r'(?m)^  src = fetchFromGitHub \{\s*'
    r'owner = "fagramdesktop";\s*repo = "fadesktop";\s*'
    r'rev = "(?P<rev>[0-9a-f]{40})";\s*fetchSubmodules = true;\s*'
    r'hash = "(?P<hash>sha256-[A-Za-z0-9+/=]+)";\s*\};'
)
matches = list(pattern.finditer(text))
if len(matches) != 1:
    sys.exit("Error: Unexpected Nix source layout; update nix/unwrapped.nix manually.")
if sys.argv[2]:
    data = json.loads(pathlib.Path(sys.argv[2]).read_text())
    if (data.get("owner"), data.get("repo"), data.get("rev"), data.get("fetchSubmodules")) != (
        "fagramdesktop", "fadesktop", sys.argv[1], True
    ):
        sys.exit("Error: Prefetch result does not match the target and submodule fetch mode.")
    source_hash = data.get("hash", "")
    if not source_hash.startswith("sha256-") or len(base64.b64decode(source_hash[7:], validate=True)) != 32:
        sys.exit("Error: Prefetch returned an invalid SHA-256 source hash.")
    match = matches[0]
    for field, value in reversed([("rev", sys.argv[1]), ("hash", source_hash)]):
        text = text[:match.start(field)] + value + text[match.end(field):]
    path.write_text(text)
PY
}
update_nix_source

echo "Fetching upstream branches (dry-run also fetches remote-tracking refs)..."
git fetch --prune --no-tags --no-prune-tags --no-recurse-submodules upstream \
  '+refs/heads/*:refs/remotes/upstream/*' || die "Upstream fetch failed; no merge was attempted."
target=$(git rev-parse --verify "$target^{commit}") || die "Target commit does not exist after fetching upstream."
[[ -n "$(git for-each-ref --format='%(refname)' --contains "$target" refs/remotes/upstream/)" ]] ||
  die "Target is not in any fetched upstream branch's history."
git merge-base HEAD "$target" >/dev/null || die "Target and this fork have no common history."
if [[ -n "$excluded" ]]; then
  excluded=$(git rev-parse --verify "$excluded^{commit}") || die "Excluded commit does not exist; cannot verify its ancestry."
  if git merge-base --is-ancestor "$excluded" "$target"; then
    die "Excluded commit is already an ancestor of the target. Choose an earlier/different target; a merge cannot skip it."
  fi
  if git merge-base --is-ancestor "$excluded" HEAD; then
    die "Excluded commit is already in HEAD; this script cannot remove existing history."
  fi
fi

printf '\nUpstream commits to integrate into %s through %s:\n' "$branch" "$target"
git --no-pager log --reverse --oneline "HEAD..$target"
printf '\nUpstream change summary from the common ancestor:\n'
git --no-pager diff --stat "HEAD...$target"
if "$dry_run"; then
  echo "Dry run complete: no merge, submodule update, Nix prefetch, or working-tree changes."
  exit 0
fi

[[ "$(git rev-parse HEAD)" == "$before" && "$(git symbolic-ref --short HEAD)" == "$branch" ]] ||
  die "The checked-out branch changed during validation; rerun the command."
[[ -z "$(git status --porcelain --untracked-files=all --ignore-submodules=none)" ]] ||
  die "Working tree changed during validation; no merge was attempted."

if ! git -c "branch.$branch.mergeOptions=" -c rerere.enabled=false \
  merge --strategy=ort --no-ff --no-commit --no-autostash "$target"; then
  cat >&2 <<'EOF'
Merge stopped. Inspect git status and resolve each conflict yourself; no ours/theirs resolution was applied.
Stage only resolved files, then run git commit to finish the merge, or git merge --abort to cancel it.
After finishing the merge with a clean tree, rerun this command to update submodules and the Nix source pin.
EOF
  exit 1
fi
if [[ -f "$(git rev-parse --git-path MERGE_HEAD)" ]]; then
  deleted=$(git diff --cached --name-only --diff-filter=D -- flake.nix flake.lock nix/)
  if [[ -n "$deleted" ]]; then
    printf 'Merge would delete fork packaging files:\n%s\n' "$deleted" >&2
    die "Merge is uncommitted. Review preservation of your Nix packaging, then commit manually and rerun; or use git merge --abort."
  fi
  update_nix_source || die "Merge is uncommitted. Fix the Nix source layout and commit manually, or use git merge --abort."
  git commit --no-edit || die "Merge is uncommitted. Inspect git status and finish with git commit, or use git merge --abort."
fi
git merge-base --is-ancestor "$target" HEAD || die "Verification failed: target is not an ancestor of HEAD."
git merge-base --is-ancestor "$before" HEAD || die "Verification failed: original fork history is not an ancestor of HEAD."
if [[ -n "$excluded" ]] && git merge-base --is-ancestor "$excluded" HEAD; then
  die "Verification failed: excluded commit is in HEAD."
fi
echo "Merge ancestry verified. Updating submodules..."
git submodule sync --recursive || die "Merge is retained. Fix the submodule sync error and rerun this command."
git submodule update --init --recursive --checkout ||
  die "Merge is retained. Fix the submodule error and rerun this command; no rollback was attempted."

prefetch_file=$(mktemp)
trap 'rm -f -- "$prefetch_file"' EXIT
echo "Prefetching the exact upstream Nix source with submodules..."
if command -v nix-prefetch-github >/dev/null; then
  prefetch=(nix-prefetch-github)
else
  command -v nix >/dev/null || die "Merge is retained. Install nix-prefetch-github or Nix, then rerun."
  prefetch=(nix run nixpkgs#nix-prefetch-github --)
fi
"${prefetch[@]}" fagramdesktop fadesktop --rev "$target" --fetch-submodules --json >"$prefetch_file" ||
  die "Merge is retained. Nix prefetch failed; fix the error and rerun this command."
update_nix_source "$prefetch_file" || die "Merge is retained. Nix pin update failed; no source-pin edit was applied."
echo "Updated nix/unwrapped.nix revision/hash (left uncommitted). Review git diff, then build: nix build .#fagram-desktop"
echo "Nothing was pushed or tagged; flake.lock was not updated by the script."

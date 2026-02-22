#!/usr/bin/env bash
# Starscream child theme release script.
set -euo pipefail

# ==== CONFIG ==================================================================
OWNER="emkowale"
REPO="starscream-child"
THEME_SLUG="starscream-child" # top-level folder inside release zip
MAIN_FILE="style.css"         # theme header file that contains Version:
REMOTE_URL="https://github.com/${OWNER}/${REPO}.git"
UPDATE_URI="https://github.com/${OWNER}/${REPO}"

# ==== UI HELPERS ==============================================================
C_RESET=$'\033[0m'
C_CYAN=$'\033[1;36m'
C_YEL=$'\033[1;33m'
C_RED=$'\033[1;31m'
C_GRN=$'\033[1;32m'
step(){ printf "${C_CYAN}%s${C_RESET}\n" "$*"; }
ok(){   printf "${C_GRN}%s${C_RESET}\n" "$*"; }
warn(){ printf "${C_YEL}%s${C_RESET}\n" "$*"; }
die(){  printf "${C_RED}%s${C_RESET}\n" "$*"; exit 1; }
trap 'printf "${C_RED}Release failed at line %s${C_RESET}\n" "$LINENO"' ERR

# ==== ARGS / TOOL CHECKS ======================================================
BUMP_TYPE="${1:-patch}"
[[ "$BUMP_TYPE" =~ ^(major|minor|patch)$ ]] || die "Usage: ./release.sh {major|minor|patch}"

command -v php >/dev/null || die "php not found"
command -v zip >/dev/null || die "zip not found"
command -v rsync >/dev/null || die "rsync not found"
GIT_OK=1
if ! command -v git >/dev/null; then
  GIT_OK=0
  warn "git not found; git/tag/release steps will be skipped"
fi

# ==== LOCATE ROOT & MAIN FILE =================================================
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
GIT_BOOTSTRAPPED=0
if [[ "$GIT_OK" -eq 1 ]] && [[ ! -d ".git" ]]; then
  step "No .git directory found; initializing local repository"
  git init -b main >/dev/null 2>&1 || git init >/dev/null
  GIT_BOOTSTRAPPED=1
  ok "Initialized git repository in ${ROOT}"
fi

if [[ -f "${THEME_SLUG}/${MAIN_FILE}" ]]; then
  SRC_DIR="${THEME_SLUG}"
  MAIN_PATH="${THEME_SLUG}/${MAIN_FILE}"
elif [[ -f "${MAIN_FILE}" ]]; then
  SRC_DIR="."
  MAIN_PATH="${MAIN_FILE}"
else
  die "Cannot find ${MAIN_FILE} at repo root or under ${THEME_SLUG}/"
fi

# ==== GIT PREP =================================================================
if [[ "$GIT_OK" -eq 1 ]]; then
  step "Preparing git state"
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$REMOTE_URL" >/dev/null 2>&1 || true
  else
    git remote add origin "$REMOTE_URL" >/dev/null 2>&1 || true
  fi
  git rebase --abort >/dev/null 2>&1 || true
  git merge --abort >/dev/null 2>&1 || true

  if ! git rev-parse --abbrev-ref HEAD 2>/dev/null | grep -q '^main$'; then
    if git show-ref --verify --quiet refs/heads/main; then
      git switch main >/dev/null 2>&1 || git checkout main >/dev/null 2>&1 || true
    else
      git switch -c main >/dev/null 2>&1 || git checkout -b main >/dev/null 2>&1 || true
    fi
  fi

  step "Fetching remote branch and tags"
  git fetch origin main --tags >/dev/null 2>&1 || git fetch origin --tags >/dev/null 2>&1 || true
  if git show-ref --verify --quiet refs/remotes/origin/main; then
    git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1 || \
      git branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true

    # Refuse to release if this directory was not cloned from the target repo.
    if ! git merge-base HEAD origin/main >/dev/null 2>&1; then
      die "Local history is unrelated to origin/main. Clone ${OWNER}/${REPO} in this directory before running release.sh."
    fi
  fi
  [[ "$GIT_BOOTSTRAPPED" -eq 1 ]] && ok "Git repository bootstrapped"
  ok "Git ready"
else
  warn "Skipping git prep/fetch (git unavailable)"
fi

# ==== VERSION DISCOVERY =======================================================
step "Reading current version from ${MAIN_PATH}"
read_version_php=$(cat <<'PHP'
$path = $argv[1];
$src = file_get_contents($path);
if ($src === false) { fwrite(STDERR, "read fail\n"); exit(1); }
if (preg_match('/(?mi)^\s*(?:\*\s*)?Version\s*:\s*([0-9]+\.[0-9]+\.[0-9]+)/', $src, $m)) {
  echo trim($m[1]);
} else {
  echo "0.0.0";
}
PHP
)
BASE_VER="$(php -r "$read_version_php" "$MAIN_PATH")"
[[ -n "$BASE_VER" ]] || BASE_VER="0.0.0"

if [[ "$GIT_OK" -eq 1 ]]; then
  latest_tag="$(git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' | sort -V | tail -n1 || true)"
  ver_ge(){ printf '%s\n%s\n' "$1" "$2" | sort -V -r | head -n1 | grep -qx "$1"; }
  if [[ -n "$latest_tag" ]] && ver_ge "$latest_tag" "$BASE_VER"; then
    BASE_VER="$latest_tag"
  fi
fi
ok "Base version: $BASE_VER"

IFS='.' read -r MAJ MIN PAT <<<"$BASE_VER"
case "$BUMP_TYPE" in
  major) ((MAJ+=1)); MIN=0; PAT=0 ;;
  minor) ((MIN+=1)); PAT=0 ;;
  patch) ((PAT+=1)) ;;
esac
NEXT="${MAJ}.${MIN}.${PAT}"

if [[ "$GIT_OK" -eq 1 ]]; then
  tag_exists(){ git rev-parse -q --verify "refs/tags/v$1" >/dev/null 2>&1; }
  while tag_exists "$NEXT"; do
    ((PAT+=1))
    NEXT="${MAJ}.${MIN}.${PAT}"
  done
fi
step "Preparing release v${NEXT}"

# ==== SAFE style.css UPDATE ===================================================
step "Updating ${MAIN_PATH}"
fix_style_php=$(cat <<'PHP'
$path = $argv[1];
$ver  = $argv[2];
$uri  = $argv[3];

$src = file_get_contents($path);
if ($src === false) { fwrite(STDERR, "read fail\n"); exit(1); }
$src = preg_replace("/\r\n?/", "\n", $src);

$lines = preg_split("/\n/", $src);
$limit = min(240, count($lines));
$start = -1;
$end = -1;
for ($i = 0; $i < $limit; $i++) {
  if (preg_match('/^\s*\/\*/', $lines[$i])) { $start = $i; break; }
}
if ($start >= 0) {
  for ($j = $start; $j < min($start + 140, count($lines)); $j++) {
    if (preg_match('/\*\//', $lines[$j])) { $end = $j; break; }
  }
}

if ($start < 0 || $end < 0) {
  $header = [
    '/*',
    ' * Theme Name: Starscream Child',
    ' * Template: starscream',
    ' * Version: ' . $ver,
    ' * Update URI: ' . $uri,
    ' */',
    ''
  ];
  array_splice($lines, 0, 0, $header);
} else {
  for ($k = $start; $k <= $end; $k++) {
    if (preg_match('/^\s*(?:\*\s*)?Version\s*:/i', $lines[$k])) $lines[$k] = null;
    if (preg_match('/^\s*(?:\*\s*)?Update\s+URI\s*:/i', $lines[$k])) $lines[$k] = null;
  }
  $tmp = [];
  foreach ($lines as $ln) { if ($ln !== null) $tmp[] = $ln; }
  $lines = $tmp;

  $end = -1;
  for ($j = $start; $j < min($start + 140, count($lines)); $j++) {
    if (preg_match('/\*\//', $lines[$j])) { $end = $j; break; }
  }
  if ($end < 0) {
    $lines[] = ' * Version: ' . $ver;
    $lines[] = ' * Update URI: ' . $uri;
    $lines[] = ' */';
  } else {
    array_splice($lines, $end, 0, [
      ' * Version: ' . $ver,
      ' * Update URI: ' . $uri
    ]);
  }
}

$out = implode("\n", $lines);
if (!preg_match('/(?mi)^\s*(?:\*\s*)?Version\s*:\s*' . preg_quote($ver, '/') . '\b/', $out)) {
  fwrite(STDERR, "warn: Version was not updated\n");
}
if (!preg_match('/(?mi)^\s*(?:\*\s*)?Update\s+URI\s*:\s*' . preg_quote($uri, '/') . '\s*$/', $out)) {
  fwrite(STDERR, "warn: Update URI was not set\n");
}

if (file_put_contents($path, $out) === false) {
  fwrite(STDERR, "write fail\n");
  exit(1);
}
PHP
)
php -r "$fix_style_php" "$MAIN_PATH" "$NEXT" "$UPDATE_URI"
ok "Updated ${MAIN_PATH} to v${NEXT}"

# ==== CHANGELOG UPDATE ========================================================
step "Updating CHANGELOG.md"
CHANGELOG="CHANGELOG.md"
TODAY="$(date +%Y-%m-%d)"

if [[ ! -f "$CHANGELOG" ]]; then
  printf "# Changelog\n\n## [%s] - %s\n\n" "$NEXT" "$TODAY" > "$CHANGELOG"
  ok "Created CHANGELOG.md"
elif grep -qE "^## \[${NEXT}\]" "$CHANGELOG"; then
  warn "CHANGELOG already has section [${NEXT}]"
elif grep -qE '^## \[Unreleased\]' "$CHANGELOG"; then
  tmp="$(mktemp)"
  awk -v ver="$NEXT" -v today="$TODAY" '
    /^## \[Unreleased\]/ { print; print ""; print "## ["ver"] - "today; next }
    { print }
  ' "$CHANGELOG" > "$tmp" && mv "$tmp" "$CHANGELOG"
  ok "Added [${NEXT}] under [Unreleased]"
else
  tmp="$(mktemp)"
  awk -v ver="$NEXT" -v today="$TODAY" '
    NR==1 { print; print ""; print "## ["ver"] - "today; next }
    { print }
  ' "$CHANGELOG" > "$tmp" && mv "$tmp" "$CHANGELOG"
  ok "Prepended [${NEXT}] section"
fi

LOG_FILE="$(mktemp)"
if [[ "$GIT_OK" -eq 1 ]] && git rev-parse --verify HEAD >/dev/null 2>&1; then
  PREV_TAG="$(git tag -l 'v[0-9]*' | sort -V | tail -n1 || true)"
  if [[ -n "$PREV_TAG" ]]; then
    git log --no-merges --pretty=format:'* %s (%h)' "${PREV_TAG}..HEAD" > "$LOG_FILE" 2>/dev/null || true
  else
    git log --no-merges --pretty=format:'* %s (%h)' --max-count=100 > "$LOG_FILE" 2>/dev/null || true
  fi
else
  echo "* Release generated from local working tree" > "$LOG_FILE"
fi
[[ -s "$LOG_FILE" ]] || echo "* Internal updates" > "$LOG_FILE"

if ! grep -qE "^## \[${NEXT}\]" "$CHANGELOG"; then
  printf "\n## [%s] - %s\n\n" "$NEXT" "$TODAY" >> "$CHANGELOG"
fi

tmp="$(mktemp)"
awk -v ver="$NEXT" -v lf="$LOG_FILE" '
  {
    print
    if (!done && $0 ~ "^## \\[" ver "\\]") {
      print ""
      print "### Changes"
      while ((getline line < lf) > 0) print line
      close(lf)
      print ""
      done=1
    }
  }
' "$CHANGELOG" > "$tmp" && mv "$tmp" "$CHANGELOG"
rm -f "$LOG_FILE"
ok "CHANGELOG updated"

# ==== COMMIT / PUSH / TAG =====================================================
if [[ "$GIT_OK" -eq 1 ]]; then
  step "Committing changes"
  # Ensure build output is never treated as source input for the release commit.
  rm -rf artifacts package

  # Always release exactly what exists in the local working tree.
  git add -A

  if ! git diff --cached --quiet; then
    git commit -m "chore(release): v${NEXT}" >/dev/null 2>&1
  else
    warn "Nothing changed to commit; continuing"
  fi

  step "Pushing main branch"
  pushed_main=0
  if git push origin main; then
    pushed_main=1
  else
    warn "Push rejected; fetching origin/main, rebasing, and retrying once"
    git fetch origin main --tags || git fetch origin --tags || true
    if git show-ref --verify --quiet refs/remotes/origin/main; then
      if git rebase origin/main; then
        if git push origin main; then
          pushed_main=1
        fi
      else
        warn "Auto-rebase failed; aborting rebase"
        git rebase --abort >/dev/null 2>&1 || true
      fi
    fi
  fi
  [[ "$pushed_main" -eq 1 ]] || die "Could not push main; aborting before tag/release."

  step "Tagging and pushing tag"
  if git rev-parse -q --verify "refs/tags/v${NEXT}" >/dev/null 2>&1; then
    die "Tag v${NEXT} already exists locally"
  fi
  if git ls-remote --exit-code --tags origin "refs/tags/v${NEXT}" >/dev/null 2>&1; then
    die "Tag v${NEXT} already exists on origin"
  fi
  git tag "v${NEXT}"
  git push origin "v${NEXT}" || die "Could not push tag v${NEXT}"
  ok "Git push complete"
else
  warn "Skipping commit/tag/push (git unavailable)"
fi

# ==== BUILD ARTIFACT ==========================================================
step "Building zip artifact"
ART_DIR="artifacts"
PKG_ROOT="package"
PKG_DIR="${PKG_ROOT}/${THEME_SLUG}"
ZIP_NAME="${THEME_SLUG}-v${NEXT}.zip"

rm -rf "$PKG_DIR" "$ART_DIR"
mkdir -p "$PKG_DIR" "$ART_DIR"
RSYNC_EXCLUDES=(
  --exclude ".git/"
  --exclude "artifacts/"
  --exclude "package/"
  --exclude ".github/"
  --exclude ".DS_Store"
)
if [[ "$SRC_DIR" == "." ]]; then
  rsync -a --delete "${RSYNC_EXCLUDES[@]}" ./ "$PKG_DIR/"
else
  rsync -a --delete "${RSYNC_EXCLUDES[@]}" "${SRC_DIR}/" "$PKG_DIR/"
fi
( cd "$PKG_ROOT" && zip -qr "../${ART_DIR}/${ZIP_NAME}" "${THEME_SLUG}" )
ok "Built ${ART_DIR}/${ZIP_NAME}"

# ==== GITHUB RELEASE ==========================================================
[[ "$GIT_OK" -eq 1 ]] || die "git is required to publish a GitHub release"
command -v gh >/dev/null 2>&1 || die "gh not found; install GitHub CLI to publish releases"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run: gh auth login"

step "Publishing GitHub release v${NEXT}"
if gh release view "v${NEXT}" >/dev/null 2>&1; then
  warn "Release exists; updating asset"
  gh release upload "v${NEXT}" "${ART_DIR}/${ZIP_NAME}" --clobber >/dev/null || die "Could not upload release asset"
else
  gh release create "v${NEXT}" "${ART_DIR}/${ZIP_NAME}" -t "v${NEXT}" -n "Release ${NEXT}" >/dev/null || die "Could not create GitHub release"
fi
ok "Release v${NEXT} published"

rm -rf "$PKG_ROOT"
ok "All done: ${ART_DIR}/${ZIP_NAME}"

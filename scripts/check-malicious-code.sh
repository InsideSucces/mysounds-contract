#!/usr/bin/env bash
# Fail CI if known malicious drop patterns are present in the working tree.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FINDINGS=0
SELF_SCRIPT="./scripts/check-malicious-code.sh"

exclude_args=(
  -path '*/.git' -o
  -path '*/.git/*' -o
  -path '*/node_modules' -o
  -path '*/node_modules/*' -o
  -path '*/dist' -o
  -path '*/dist/*' -o
  -path '*/build' -o
  -path '*/build/*' -o
  -path '*/.next' -o
  -path '*/.next/*' -o
  -path '*/coverage' -o
  -path '*/coverage/*' -o
  -path '*/out' -o
  -path '*/out/*' -o
  -path '*/cache' -o
  -path '*/cache/*' -o
  -path '*/.forge-cache' -o
  -path '*/.forge-cache/*' -o
  -path '*/broadcast' -o
  -path '*/broadcast/*'
)

report() {
  local rule="$1"
  local path="$2"
  echo "MALWARE_CHECK FAIL [$rule]: $path"
  FINDINGS=$((FINDINGS + 1))
}

# --- 1. .vscode directories (common malware / unwanted editor payload drop) ---
while IFS= read -r -d '' dir; do
  report "vscode-dir" "$dir"
done < <(find . \( "${exclude_args[@]}" \) -prune -o -type d -name '.vscode' -print0 2>/dev/null)

# --- 2. Public/font (Font Awesome / unexpected font binaries) ---
while IFS= read -r -d '' file; do
  report "public-font" "$file"
done < <(
  find . \( "${exclude_args[@]}" \) -prune -o -type f \( \
    -ipath '*/public/font/*' -o \
    -ipath '*/public/fonts/*' -o \
    -ipath '*/Public/font/*' -o \
    -ipath '*/Public/fonts/*' \
  \) \( \
    -iname '*.woff' -o -iname '*.woff2' -o -iname '*.ttf' -o -iname '*.eot' -o -iname '*.otf' -o \
    -iname '*fa-*' -o -iname '*fontawesome*' -o -iname '*FontAwesome*' \
  \) -print0 2>/dev/null
)

# Patterns built so literal malware snippets are not stored as a single searchable string
# in this file beyond what exclude globs already skip.
PAT_GLOBAL_I="global\\.i\\s*="
PAT_GLOBAL_R="global\\[['\"]r['\"]\\]\\s*=\\s*require"
PAT_WHILE_TRUE="while\\s*\\(\\s*!!\\s*\\[\\s*\\]\\s*\\)"
PAT_HEX_DECODER="function\\s+_0x[0-9a-fA-F]{4,}\\s*\\("
PAT_SPAWN_E="spawn\\s*\\([^)]*\\[\\s*['\"]-e['\"]"

# --- 3. Obfuscated Node backdoor signatures ---
scan_content() {
  local pattern="$1"
  local rule="$2"
  if command -v rg >/dev/null 2>&1; then
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      [[ "$path" == "$SELF_SCRIPT" || "$path" == "${SELF_SCRIPT#./}" ]] && continue
      report "$rule" "$path"
    done < <(
      rg -l --hidden \
        --glob '!.git/**' \
        --glob '!node_modules/**' \
        --glob '!dist/**' \
        --glob '!build/**' \
        --glob '!.next/**' \
        --glob '!coverage/**' \
        --glob '!out/**' \
        --glob '!cache/**' \
        --glob '!.forge-cache/**' \
        --glob '!broadcast/**' \
        --glob '!scripts/check-malicious-code.sh' \
        -e "$pattern" . 2>/dev/null || true
    )
  else
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      path="${path#./}"
      [[ "./$path" == "$SELF_SCRIPT" || "$path" == "${SELF_SCRIPT#./}" ]] && continue
      report "$rule" "./$path"
    done < <(
      grep -RIl \
        --exclude-dir=.git \
        --exclude-dir=node_modules \
        --exclude-dir=dist \
        --exclude-dir=build \
        --exclude-dir=.next \
        --exclude-dir=coverage \
        --exclude-dir=out \
        --exclude-dir=cache \
        --exclude-dir=.forge-cache \
        --exclude-dir=broadcast \
        --exclude='check-malicious-code.sh' \
        -E "$pattern" . 2>/dev/null || true
    )
  fi
}

scan_content "$PAT_GLOBAL_I" 'obfuscated-global-i'
scan_content "$PAT_GLOBAL_R" 'obfuscated-global-require'
scan_content "$PAT_WHILE_TRUE" 'obfuscated-while-true-array'
scan_content "$PAT_HEX_DECODER" 'obfuscated-hex-decoder'
scan_content "$PAT_SPAWN_E" 'obfuscated-spawn-e'

if [[ "$FINDINGS" -gt 0 ]]; then
  echo ""
  echo "Malicious-code check failed with $FINDINGS finding(s)."
  exit 1
fi

echo "Malicious-code check passed."

#!/usr/bin/env bash
# ============================================================
# build-skill-tree.sh — Generate and validate the Sentry skill tree
# ============================================================
# Scans all src/skills/*/SKILL.md files, regenerates src/SKILL_TREE.md, and
# validates each skill's frontmatter.
#
# Link checking lives in validate-skill-links.py — it needs the reference
# manifests, which this script does not read.
#
# Usage:
#   scripts/build-skill-tree.sh           # regenerate + validate
#   scripts/build-skill-tree.sh --check   # validate only (no write)
#
# Exit codes: 0 = pass, 1 = errors found
# Requirements: bash 3.2+, grep, sed, awk, diff, find

set -euo pipefail

# ── Setup ────────────────────────────────────────────────────

CHECK_ONLY=false
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SKILL_TREE_FILE="src/SKILL_TREE.md"
SKILLS_DIR="src/skills"

# Temp directory for per-skill data (bash 3 compatible, no assoc arrays)
TMPDIR_SKILLS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_SKILLS"' EXIT

ERRORS=()
error() { ERRORS+=("ERROR: $*"); }
warn()  { echo "WARN: $*" >&2; }

# ============================================================
# SECTION 1: Parse frontmatter from a SKILL.md file
# Outputs: key=value lines for known fields
# ============================================================
parse_frontmatter() {
  local file="$1"
  awk '
    BEGIN { in_fm=0; fm_count=0 }
    /^---$/ {
      fm_count++
      if (fm_count == 1) { in_fm=1; next }
      if (fm_count == 2) { exit }
    }
    in_fm && /^[a-zA-Z-]+:/ {
      colon = index($0, ":")
      key = substr($0, 1, colon - 1)
      val = substr($0, colon + 2)
      # Remove leading/trailing whitespace from val
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      # Normalize key: replace hyphens with underscores
      gsub(/-/, "_", key)
      print key "=" val
    }
  ' "$file"
}

# Write a field value to a temp file for skill $name
skill_set() {
  local name="$1" field="$2" value="$3"
  # Sanitize name for filesystem use (replace / and spaces)
  local safe_name="${name//[^a-zA-Z0-9_-]/_}"
  printf '%s' "$value" > "${TMPDIR_SKILLS}/${safe_name}.${field}"
}

# Read a field value for skill $name (empty string if missing)
skill_get() {
  local name="$1" field="$2"
  local safe_name="${name//[^a-zA-Z0-9_-]/_}"
  local f="${TMPDIR_SKILLS}/${safe_name}.${field}"
  [[ -f "$f" ]] && cat "$f" || echo ""
}

# ============================================================
# SECTION 2: Scan all skills
# ============================================================

ALL_SKILLS=()

while IFS= read -r skill_file; do
  s_name="" s_desc="" s_cat="" s_parent="" s_role="" s_disable=""

  while IFS='=' read -r key val; do
    case "$key" in
      name)                      s_name="$val" ;;
      description)               s_desc="$val" ;;
      category)                  s_cat="$val" ;;
      parent)                    s_parent="$val" ;;
      role)                      s_role="$val" ;;
      disable_model_invocation)  s_disable="$val" ;;
    esac
  done < <(parse_frontmatter "$skill_file")

  # Fall back to directory name if name field is missing
  [[ -z "$s_name" ]] && s_name="$(basename "$(dirname "$skill_file")")"

  ALL_SKILLS+=("$s_name")
  skill_set "$s_name" "desc"     "$s_desc"
  skill_set "$s_name" "category" "$s_cat"
  skill_set "$s_name" "parent"   "$s_parent"
  skill_set "$s_name" "role"     "$s_role"
  skill_set "$s_name" "disable"  "$s_disable"
  skill_set "$s_name" "file"     "$skill_file"

done < <(find "$SKILLS_DIR" -name "SKILL.md" | sort)

TOTAL_SKILLS=${#ALL_SKILLS[@]}

# ============================================================
# SECTION 3: Generate SKILL_TREE.md content
# ============================================================

# Escape characters that would break a markdown table cell.
escape_cell() {
  printf '%s' "$1" | tr '\n' ' ' | sed 's/|/\\|/g'
}

# Build a markdown row per skill, using the full description — it is the
# routing signal now that there is nothing else to route through.
build_skill_rows() {
  for name in "${ALL_SKILLS[@]}"; do
    local file desc
    file="$(skill_get "$name" file)"
    desc="$(escape_cell "$(skill_get "$name" desc)")"
    printf "| [\`%s\`](%s) | %s |\n" "$name" "${file#src/}" "$desc"
  done
}

generate_skill_tree() {
  cat <<'HEADER'
# Sentry Skills

You are **Sentry's AI assistant**. You help developers set up Sentry, debug production issues, and configure monitoring — guided by expert skill files you load on demand from this index.

## Start Here — Read This Before Doing Anything

**Do not skip this section.** Do not assume what the user needs based on their project files. Do not start installing packages, creating files, or running commands until you have confirmed the user's intent.

1. **Ask first.** Greet the user and ask what they'd like help with. Present these options:
   - **Set up Sentry** — Add error monitoring, performance tracing, session replay, or AI/LLM monitoring to a project
   - **Debug a production issue** — Investigate errors and exceptions using Sentry data
   - **Configure a feature** — monitors and alerts, OpenTelemetry pipelines
   - **Review code** — Resolve Sentry bot comments or check for predicted bugs

2. **Wait for their answer.** Do not proceed until the user tells you what they want.

3. **Read the matching skill** from the table below and follow its instructions step by step.

Each skill file contains its own detection logic, prerequisites, and configuration steps. Trust the skill — read it carefully and follow it. Do not improvise or take shortcuts.

---
HEADER

  cat <<'SKILLS_HEADER'

## Available Skills

Each one is self-contained and named for the job it does. If you're not sure what the user needs, read `sentry-get-started`; it orients you and points to the right skill.

| Skill | What it does |
|---|---|
SKILLS_HEADER
  build_skill_rows

  printf "\n"
}

# ============================================================
# SECTION 4: Validate
# ============================================================

# Frontmatter fields from the retired router model. Skills are flat and
# task-shaped now: one skill = one job, discoverable from its own description.
# A skill carrying any of these is either a stale copy-paste or an attempt to
# reintroduce routing -- both worth stopping on, since nothing renders them.
# Stored field name : the frontmatter key to name in the error.
RETIRED_FIELDS=("category:category" "parent:parent" "role:role" "disable:disable-model-invocation")

validate() {
  for name in "${ALL_SKILLS[@]}"; do
    [[ -n "$(skill_get "$name" desc)" ]] || \
      error "$name: missing 'description' field"

    for entry in "${RETIRED_FIELDS[@]}"; do
      [[ -z "$(skill_get "$name" "${entry%%:*}")" ]] || \
        error "$name: '${entry#*:}' is no longer supported -- every skill is standalone"
    done
  done
}

# ============================================================
# SECTION 5: Run
# ============================================================

echo "Scanning ${TOTAL_SKILLS} skills in ${SKILLS_DIR}/..."

GENERATED="$(generate_skill_tree)"

validate

# ── Stale check / write ──────────────────────────────────────

if [[ -f "$SKILL_TREE_FILE" ]]; then
  EXISTING="$(cat "$SKILL_TREE_FILE")"
  if [[ "$GENERATED" != "$EXISTING" ]]; then
    echo ""
    echo "SKILL_TREE.md diff (existing → generated):"
    diff <(echo "$EXISTING") <(echo "$GENERATED") || true
    echo ""
    if $CHECK_ONLY; then
      error "SKILL_TREE.md is stale. Run scripts/build-skill-tree.sh to regenerate."
    else
      echo "SKILL_TREE.md is stale — regenerating..."
      printf '%s\n' "$GENERATED" > "$SKILL_TREE_FILE"
      echo "SKILL_TREE.md updated."
    fi
  else
    echo "SKILL_TREE.md is up to date."
  fi
else
  if $CHECK_ONLY; then
    error "SKILL_TREE.md does not exist. Run scripts/build-skill-tree.sh to generate."
  else
    printf '%s\n' "$GENERATED" > "$SKILL_TREE_FILE"
    echo "SKILL_TREE.md created."
  fi
fi

# ── Summary ──────────────────────────────────────────────────

echo ""
echo "Summary: ${TOTAL_SKILLS} skills scanned, ${#ERRORS[@]} errors"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Errors:"
  for e in ${ERRORS[@]+"${ERRORS[@]}"}; do
    echo "  $e"
  done
  exit 1
fi

echo "All checks passed."
exit 0

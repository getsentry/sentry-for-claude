#!/usr/bin/env bash
#
# build.sh — Build the Cortex Code distribution of the Sentry plugin.
#
# Cortex Code (CoCo) discovers plugins via .cortex-plugin/plugin.json at the
# repo root. Skills live in skills/ and MCP servers are declared inline in the
# manifest's `mcpServers` field. CoCo can install from GitHub repos directly
# with `cortex plugin install owner/repo`.
#
# No skill mutation is needed; skills ship as-authored.
#
# Skill content (skills/, references/, SKILL_TREE.md) is read from CONTENT_ROOT,
# defaulting to the repo's src/ directory. Override CONTENT_ROOT to build a
# different content tree with the same steps.
#
# Usage: build.sh <TARGET_DIR>   (TARGET_DIR assumed empty)

set -euo pipefail

TARGET_DIR="${1:?usage: build.sh <TARGET_DIR>}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SRC_DIR/../../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/scripts/build-common.sh"
resolve_content_root "$REPO_ROOT/src"

mkdir -p "$TARGET_DIR/.cortex-plugin"

install_plugin_manifest "$SRC_DIR/plugin.json" "$TARGET_DIR/.cortex-plugin/plugin.json"
copy_skills "$CONTENT_ROOT" "$TARGET_DIR/skills"
copy_skill_tree "$CONTENT_ROOT" "$TARGET_DIR/SKILL_TREE.md"
rsync -a assets/ "$TARGET_DIR/assets/"
cp "$SRC_DIR/README.md" "$TARGET_DIR/README.md"
cp LICENSE "$TARGET_DIR/LICENSE"

echo "Built Cortex Code dist into $TARGET_DIR (root plugin, content from $CONTENT_ROOT)."

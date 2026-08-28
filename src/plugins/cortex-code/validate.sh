#!/usr/bin/env bash
#
# validate.sh — Validate the built Cortex Code distribution before publishing.
#
# Structural checks: the plugin manifest must exist and be valid JSON. When the
# `cortex` CLI is available we additionally run its native `cortex plugin validate`.
#
# Usage: validate.sh <TARGET_DIR>   (a tree produced by build.sh)

set -euo pipefail

TARGET_DIR="${1:?usage: validate.sh <TARGET_DIR>}"

MANIFEST="$TARGET_DIR/.cortex-plugin/plugin.json"
[ -f "$MANIFEST" ] || { echo "missing required file: $MANIFEST" >&2; exit 1; }
jq empty "$MANIFEST"

if command -v cortex >/dev/null 2>&1; then
    cortex plugin validate "$TARGET_DIR"
fi

echo "Validated Cortex Code dist at $TARGET_DIR."

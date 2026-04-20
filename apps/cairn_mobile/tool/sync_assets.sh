#!/usr/bin/env bash
# Copy canonical docs artifacts into the Flutter asset bundle before build.
# Fail loud if a source file is missing.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
app_root="$repo_root/apps/cairn_mobile"

src_prompt="$repo_root/docs/prompts/system_prompt_v1.txt"
dst_prompt="$app_root/assets/prompts/system_prompt_v1.txt"

[[ -f "$src_prompt" ]] || { echo "missing $src_prompt" >&2; exit 1; }

mkdir -p "$(dirname "$dst_prompt")"
cp "$src_prompt" "$dst_prompt"
echo "synced $dst_prompt"

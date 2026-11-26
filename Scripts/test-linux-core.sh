#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swiftc_path="$(command -v swiftc || true)"
if [[ -z "$swiftc_path" && -n "${HOME:-}" && -x "$HOME/.local/share/swiftly/bin/swiftc" ]]; then
  swiftc_path="$HOME/.local/share/swiftly/bin/swiftc"
fi
if [[ -z "$swiftc_path" ]]; then
  echo "swiftc was not found on PATH. Install Swift 6.4.3 or add its bin directory to PATH." >&2
  exit 127
fi

build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

"$swiftc_path" -swift-version 6 \
  "$repo_root/Models/Models.swift" \
  "$repo_root/Models/DeviceProfile.swift" \
  "$repo_root/AppStore/CompatibilityChecker.swift" \
  "$repo_root/Tests/LinuxCoreChecks.swift" \
  -o "$build_dir/LinuxCoreChecks"

"$build_dir/LinuxCoreChecks"

#!/usr/bin/env bash

# GW Toolbox Updater Script
# This script updates GW Toolbox components from GitHub releases.
# Run this from the GW Toolbox root folder (gwtoolboxpp).

set -euo pipefail

get_dll_version() {
    local ini_path=$1

    python3 - "$ini_path" <<'PY'
import re
import sys
from pathlib import Path

ini_path = Path(sys.argv[1])
for line in ini_path.read_text(encoding="utf-8", errors="replace").splitlines():
    match = re.match(r"^dllversion\s*=\s*(.+)", line)
    if match:
        print(match.group(1).strip())
        sys.exit(0)

print(f"dllversion not found in {ini_path}", file=sys.stderr)
sys.exit(1)
PY
}

compare_versions() {
    local v1=$1
    local v2=$2

    python3 - "$v1" "$v2" <<'PY'
import sys

def parts(version):
    return [int(part) for part in version.split(".") if part != ""]

v1 = parts(sys.argv[1])
v2 = parts(sys.argv[2])
length = max(len(v1), len(v2))
v1 += [0] * (length - len(v1))
v2 += [0] * (length - len(v2))

if v1 > v2:
    print(1)
elif v1 < v2:
    print(-1)
else:
    print(0)
PY
}

download_file() {
    local url=$1
    local output_path=$2

    echo "Downloading $url to $output_path"
    curl -fL --retry 3 --output "$output_path" "$url"
}

require_command() {
    local command_name=$1

    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Error: required command '$command_name' was not found." >&2
        exit 1
    fi
}

cleanup() {
    rm -f "${gw_releases_file:-}" "${tas_releases_file:-}" "${tas_release_file:-}" "${plugin_assets_file:-}"
}

main() {
    require_command curl
    require_command python3

    local user_folder=${COMPUTERNAME:-${HOSTNAME:-}}
    if [[ -z "$user_folder" ]]; then
        user_folder=$(hostname)
    fi

    local plugins_path="$user_folder/plugins"
    local ini_path="$user_folder/GWToolbox.ini"

    if [[ ! -f "$ini_path" ]]; then
        echo "Error: GWToolbox.ini not found in $user_folder. Please run this script from the GW Toolbox root folder." >&2
        exit 1
    fi

    local current_version
    current_version=$(get_dll_version "$ini_path")
    echo "Current GW Toolbox version: $current_version"

    gw_releases_file=$(mktemp)
    tas_releases_file=$(mktemp)
    tas_release_file=$(mktemp)
    trap cleanup EXIT

    echo "Checking for more recent GW Toolbox version..."
    curl -fL --retry 3 \
        --header "Accept: application/vnd.github+json" \
        --output "$gw_releases_file" \
        "https://api.github.com/repos/gwdevhub/GWToolboxpp/releases"

    local latest_tag
    latest_tag=$(python3 - "$gw_releases_file" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    releases = json.load(handle)

matches = []
for release in releases:
    tag_name = release.get("tag_name", "")
    match = re.match(r"^(\d+\.\d+)_Release$", tag_name)
    if match and not release.get("prerelease", False):
        matches.append((tuple(int(part) for part in match.group(1).split(".")), match.group(1)))

if matches:
    print(max(matches)[1])
PY
)

    if [[ -n "$latest_tag" ]]; then
        local comparison
        comparison=$(compare_versions "$latest_tag" "$current_version")
        if (( comparison > 0 )); then
            echo "A newer GW Toolbox version is available: $latest_tag (current: $current_version)"
        else
            echo "GW Toolbox is up to date."
        fi
    fi

    local major_version=${current_version%%.*}
    local exe_release_tag="${major_version}.0_Exe"
    echo "Looking for GW Toolbox exe release tag $exe_release_tag"

    local exe_asset_url
    exe_asset_url=$(python3 - "$gw_releases_file" "$exe_release_tag" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    releases = json.load(handle)

target_tag = sys.argv[2]
for release in releases:
    if release.get("tag_name") != target_tag:
        continue

    for asset in release.get("assets", []):
        name = asset.get("name", "")
        if ("GWToolbox" in name and name.endswith(".exe")) or name == "GWToolbox.exe":
            print(asset.get("browser_download_url", ""))
            sys.exit(0)

    print("__NO_EXE_ASSET__")
    sys.exit(0)

print("__NO_EXE_RELEASE__")
PY
)

    case "$exe_asset_url" in
        "__NO_EXE_RELEASE__")
            echo "No GW Toolbox exe release found for tag $exe_release_tag"
            ;;
        "__NO_EXE_ASSET__")
            echo "Found GW Toolbox exe release"
            echo "No exe found in GW Toolbox exe release"
            ;;
        "")
            ;;
        *)
            echo "Found GW Toolbox exe release"
            echo "Updating GWToolbox.exe..."
            download_file "$exe_asset_url" "GWToolbox.exe"
            ;;
    esac

    echo "Checking TAS Toolbox releases..."
    curl -fL --retry 3 \
        --header "Accept: application/vnd.github+json" \
        --output "$tas_releases_file" \
        "https://api.github.com/repos/gwtasdevs/GWToolboxpp/releases"

    python3 - "$tas_releases_file" "$current_version" "$tas_release_file" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    releases = json.load(handle)

current_version = re.escape(sys.argv[2])
pattern = re.compile(rf"^{current_version}_(Release|Beta_[a-f0-9]+)$")
matching = [release for release in releases if pattern.match(release.get("tag_name", ""))]
matching.sort(key=lambda release: release.get("published_at", ""), reverse=True)

if matching:
    with open(sys.argv[3], "w", encoding="utf-8") as handle:
        json.dump(matching[0], handle)
PY

    if [[ ! -s "$tas_release_file" ]]; then
        echo "No TAS Toolbox release found for version $current_version"
        echo "Update complete."
        return
    fi

    local tas_tag
    tas_tag=$(python3 - "$tas_release_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle).get("tag_name", ""))
PY
)
    echo "Found TAS Toolbox release: $tas_tag"

    local dll_asset_url
    dll_asset_url=$(python3 - "$tas_release_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    release = json.load(handle)

for asset in release.get("assets", []):
    if asset.get("name") == "GWToolboxdll.dll":
        print(asset.get("browser_download_url", ""))
        break
PY
)

    if [[ -n "$dll_asset_url" ]]; then
        echo "Updating GWToolboxdll.dll..."
        download_file "$dll_asset_url" "GWToolboxdll.dll"
    fi

    local gwca_asset_url
    gwca_asset_url=$(python3 - "$tas_release_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    release = json.load(handle)

for asset in release.get("assets", []):
    if asset.get("name") == "gwca.dll":
        print(asset.get("browser_download_url", ""))
        break
PY
)

    if [[ -n "$gwca_asset_url" ]]; then
        echo "Updating gwca.dll..."
        download_file "$gwca_asset_url" "$user_folder/gwca.dll"
    fi

    local update_plugins
    read -r -p "Do you want to update plugins? This will delete all current plugins and replace them. (y/n) " update_plugins
    if [[ "$update_plugins" == "y" || "$update_plugins" == "Y" ]]; then
        if [[ -d "$plugins_path" ]]; then
            echo "Clearing plugins folder (preserving .ini files)..."
            find "$plugins_path" -mindepth 1 ! -name "*.ini" -exec rm -rf {} +
        else
            mkdir -p "$plugins_path"
        fi

        plugin_assets_file=$(mktemp)
        python3 - "$tas_release_file" "$plugin_assets_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    release = json.load(handle)

output_path = sys.argv[2]
with open(output_path, "w", encoding="utf-8") as handle:
    for asset in release.get("assets", []):
        name = asset.get("name", "")
        if name.endswith(".dll") and name not in {"GWToolboxdll.dll", "gwca.dll"}:
            handle.write(f"{name}\t{asset.get('browser_download_url', '')}\n")
PY

        local plugin_count=0
        local plugin_name plugin_url
        while IFS=$'\t' read -r plugin_name plugin_url; do
            [[ -z "$plugin_name" || -z "$plugin_url" ]] && continue
            echo "Updating plugin: $plugin_name..."
            download_file "$plugin_url" "$plugins_path/$plugin_name"
            plugin_count=$((plugin_count + 1))
        done < "$plugin_assets_file"
        rm -f "$plugin_assets_file"

        if (( plugin_count > 0 )); then
            echo "Downloaded $plugin_count plugin(s)."
        else
            echo "No plugins found in release."
        fi
    else
        echo "Skipping plugin updates."
    fi

    echo "Update complete."
}

if ! main "$@"; then
    echo "Error: update failed." >&2
    exit 1
fi

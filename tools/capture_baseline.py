#!/usr/bin/env python3
"""Record a static, local inventory using the native inspector.

No game process is launched. Game files are opened by the inspector for reading.
"""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess


MODULES = (
    "game/bin/win64/cs2.exe",
    "game/bin/win64/engine2.dll",
    "game/bin/win64/rendersystemvulkan.dll",
    "game/bin/win64/steam_api64.dll",
    "game/csgo/bin/win64/client.dll",
)

PACKAGES = (
    "game/csgo/pak01_dir.vpk",
    "game/csgo/shaders_vulkan_dir.vpk",
    "game/core/pak01_dir.vpk",
)


def inspect(tool, command, path):
    result = subprocess.run(
        [str(tool), command, str(path)],
        check=True,
        capture_output=True,
        text=True,
        timeout=60,
    )
    return json.loads(result.stdout)


def capture(root, tool):
    manifest = root.parent.parent / "appmanifest_730.acf"
    build_id = None
    if manifest.is_file():
        match = re.search(r'"buildid"\s*"([0-9]+)"', manifest.read_text())
        if match:
            build_id = match.group(1)

    records = []
    for command, paths in (("inspect-pe", MODULES), ("inspect-vpk", PACKAGES)):
        for relative in paths:
            path = root / relative
            record = {"relative_path": relative, "present": path.is_file()}
            if record["present"]:
                record["inspection"] = inspect(tool, command, path)
            records.append(record)
    return {
        "schema_version": 1,
        "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
        "steam_app_id": 730,
        "steam_manifest_build_id": build_id,
        "root": str(root),
        "scope": "selected-bootstrap-modules-and-vpk-directories",
        "game_execution_observed": False,
        "limitations": [
            "The Steam manifest describes the installation; each inspected file has its own identity.",
            "This inventories selected files, not the complete game or every dependency.",
            "VPK directory inspection does not validate all payload chunks or render any resource.",
            "Static file metadata does not demonstrate runtime or Steam service compatibility.",
        ],
        "records": records,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True,
                        help="Local Counter-Strike Global Offensive installation directory")
    parser.add_argument("--tool", type=Path,
                        default=Path(__file__).resolve().parents[1] / ".build/cs2-native-lab",
                        help="Path to the compiled native inspector")
    parser.add_argument("--output", type=Path,
                        help="Save a local JSON report; otherwise print JSON to stdout")
    args = parser.parse_args()
    root = args.root.expanduser().resolve()
    tool = args.tool.expanduser().resolve()
    if not (root / MODULES[0]).is_file():
        parser.error("The selected installation has no game/bin/win64/cs2.exe")
    if not tool.is_file():
        parser.error("Native inspector missing; run make first")
    try:
        report = capture(root, tool)
        encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(encoded)
            print("Saved local inventory to " + str(args.output))
        else:
            print(encoded, end="")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
        parser.exit(1, "Inventory failed: " + detail + "\n")


if __name__ == "__main__":
    main()

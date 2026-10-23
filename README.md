# CS2 native macOS research

An open-source research project toward a native ARM64 macOS implementation
compatible with Counter-Strike 2.

**Current milestone: a working native inspection tool and an evidence-backed
bootstrap investigation. There is no playable macOS CS2 client in this repository.**

## What works today

- An original C++20 command-line tool compiled as Mach-O ARM64 on Apple Silicon.
- Bounded PE32/PE32+ inspection: architecture, SHA-256, sections, and normal DLL imports.
- VPK v1/v2 directory inspection: paths, resource categories, archive references,
  preload metadata, bounded listings, and a header/tree digest.
- A reproducible inventory of selected locally installed game files.
- Ghidra 12.1.4 observations of the real Windows launcher and Source2Main.

The native tool is a first filesystem/inspection component. It does not execute
the Windows binaries, translate their CPU instructions, or implement Source 2.

## Build and test

Requirements: Apple Silicon, macOS with Xcode Command Line Tools, make, and Python
3.9+ for the test runner. No third-party packages are downloaded by the build.

~~~sh
make
make test
file .build/cs2-native-lab
~~~

The tests use synthetic inputs. They cover PE32/PE32+ imports, VPK v1/v2,
truncation, overflowing ranges, invalid strings, directory traversal, empty-entry
sentinels, and non-regular inputs.

## Inspect your local files

Point CS2_GAME_ROOT at a game installation you obtained through Steam:

~~~sh
CS2_GAME_ROOT="/absolute/path/to/Counter-Strike Global Offensive"

.build/cs2-native-lab inspect-pe \
  "$CS2_GAME_ROOT/game/bin/win64/cs2.exe"

.build/cs2-native-lab inspect-vpk \
  "$CS2_GAME_ROOT/game/csgo/pak01_dir.vpk" --filter models --limit 5

python3 tools/capture_baseline.py --root "$CS2_GAME_ROOT" \
  --output .local/baseline.json
~~~

All inspections are static. The VPK command reads the index, not every numbered
archive. Its digest identifies the header/tree only; payload checksums and
signatures are not verified. The PE command does not inventory dynamically loaded
modules or delay imports. JSON output preserves these limits.

## Research result and next milestone

The inspected Windows build is 24957633. Ghidra identified 853 launcher procedures
and 13,171 procedures in engine2.dll. Only selected bootstrap functions were
decompiled. The main CS2 VPK directory contains 135,686 entries.

See [initial findings](docs/initial-findings.md),
[the artifact baseline](docs/artifact-baseline.json), and
[useful external resources](docs/resources.md).

The next useful milestone is bounded reading and verification of one VPK entry,
followed by decoding one real resource and displaying it in a native macOS
renderer. That would establish resource and graphics compatibility, not yet a
playable game.

Subsequent work includes the engine platform layer, CPU/SIMD behavior, rendering,
shaders, resource systems, physics, audio, input, gameplay, networking, and Steam
integration. Each needs its own evidence and acceptance test.

Steamworks supplies a macOS x64/ARM64 library, but this does not establish that a
reconstructed client can use CS2 matchmaking or be published under AppID 730.
The official product's builds and launch configuration require its Steamworks
publisher permissions. See [Valve's API documentation](https://partner.steamgames.com/doc/sdk/api)
and [build publication requirements](https://partner.steamgames.com/doc/sdk/uploading).

## Code and research provenance

Original repository code is [MIT licensed](LICENSE). That license covers our code,
not Valve's binaries, assets, or decompiler output. Researchers obtain game
content through Steam and keep raw evidence and pseudocode in the ignored
.local/ directory.

Public findings link observations to artifact digests and evidence identifiers.
No formal clean-room process or compatibility with the complete game is claimed.
See [contributing](CONTRIBUTING.md) for the contribution boundary.

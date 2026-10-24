# Original-game compatibility workflow

## Goal and execution path

`CS2 en Mac.app → Windows Steam → original CS2 Windows binaries → Wine/DXMT/Rosetta → macOS`

The native Swift/AppKit launcher configures and starts an existing compatibility
stack. It does not translate CPU instructions itself, rebuild the game, inject
into CS2, or bypass Steam authentication. Game launch always goes through Steam:
the GUI opens the client; the optional CLI `play` asks Steam to launch AppID 730.

The first accepted game proof is a completed official Casual match, with working
input, sound, graphics and stable networking, followed by a clean restart. Offline
tests are intermediate checks. The current result is in compatibility-validation.json.

## Command reference

The executable is `.build/CS2 en Mac.app/Contents/MacOS/cs2mac`.

| Command | Behavior |
| --- | --- |
| `doctor [--json]` | Read-only prerequisites and selected-backend diagnosis; exit 1 when required checks fail. JSON excludes account identifiers and absolute home paths. |
| `fetch-runtime` | Download and stage the pinned Wine/DXMT runtime; verify SHA-256 and required Wine exports. Does not execute Windows software or select a different backend. |
| `setup` | Require working Rosetta, prepare the managed prefix and launch Valve's interactive Steam installer. Select the managed backend. |
| `use-crossover --bottle NAME [--app PATH]` | Select an existing CrossOver Steam installation without changing that bottle. |
| `use-managed` | Select the managed environment without installing or launching anything. |
| `import-game PATH` | Clone an existing Windows game directory into the managed prefix using APFS copy-on-write; preserve the local Steam manifest when present. Refuse overwrites and symbolic links. |
| `steam [--dry-run]` | Open Windows Steam; the user presses Play. Dry-run emits the argument vector and Wine environment overrides without creating files or executing it. |
| `play [--dry-run]` | Ask Steam to launch AppID 730; never launch `cs2.exe` directly. Steam must be installed and logged in for the request to succeed. |
| `stop [--dry-run]` | Request Steam's normal shutdown in the selected environment. Does not kill unrelated Wine processes or forcibly stop a stuck game. |

`--data-root /absolute/path` before the command isolates state, cache, runtime,
prefix and logs for another local profile. The default root is
`~/Library/Application Support/CS2Mac`.

## Installation and failure behavior

- Managed Wine/DXMT packages have fixed download URLs, sizes and SHA-256 values
  from upstream release metadata. Cache entries are checked before use. A failed
  download or staging operation is not promoted to the active runtime.
- Extraction uses the system archive tool with path checks, the fixed trusted
  package digest, and no owner restoration. Only the expected package roots are
  accepted. The staged engine must export `_macdrv_functions` for DXMT.
- No `native,builtin` Direct3D overrides are installed for the selected builtin
  DXMT build. Wine's current default registry behavior remains in effect.
- Steam's bootstrap installer comes from Valve over HTTPS. It is mutable upstream;
  this project does not present a made-up fixed checksum or publisher verification
  claim. Steam presents installation/login UI. No terms are silently accepted.
- Rosetta setup opens Apple's updater. The user reviews and accepts Apple's terms.
  The launcher does not run an unattended `--agree-to-license` command.
- Runtime and Steam errors leave a private log with mode 0600. Do not publish raw
  logs: they may contain paths or application identifiers. The doctor JSON is the
  shareable prerequisite summary.
- Windows child processes receive a limited desktop environment, not arbitrary
  API keys/tokens from the developer's shell.
- The managed game library is separate from macOS Steam and the source CrossOver
  library. APFS cloning creates independent file inodes and writes. It requires a
  compatible local filesystem; no slow full-copy fallback runs automatically.
- Retrying setup reuses verified packages and an existing Steam installation.
  A manually modified/incomplete active runtime is reported instead of overwritten.

## Verification stages

1. Build and synthetic launcher/parser tests; architecture and visible UI checks.
2. Package integrity and independent game-copy comparison against the saved build.
3. Rosetta availability, runtime initialization and actual Steam launch/login.
4. Offline rendering, input, sound, map loading and restart.
5. Steam-launched official Casual match and session/restart verification.
6. Repeat in the managed open runtime and on additional Apple Silicon hardware.

Stages 3–6 are not inferred from 1–2. If a session is rejected, preserve the exact
error and investigate the compatibility layer rather than changing Valve's game
or claiming that a successful Steam login establishes online support.

## Distribution and remaining work

`make install-app` installs into `~/Applications`; `INSTALL_DIR` overrides the
destination. `make dist` creates the app-only ZIP. Both retain the original-code
license and external-component notice. The current ad-hoc signature is for local
testing. Developer ID signing, notarization, update delivery and multi-machine
validation remain release work.

Rosetta availability is a real platform dependency: Apple documents general
availability through macOS 27 and limited availability starting with macOS 28.
Do not claim this baseline supports every future macOS release.
[Apple's Rosetta documentation](https://support.apple.com/en-us/102527).

The [DXMT upstream project](https://github.com/3Shain/dxmt) supplies Direct3D-to-Metal
compatibility. [CS2Kit's documentation](https://github.com/piwas-21/cs2-apple-silicon)
was a configuration reference, not a source-code dependency or proof of results
on this project. Runtime versions and package provenance are in THIRD_PARTY.md.

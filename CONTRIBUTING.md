# Contributing

The target is running Valve's original Counter-Strike 2 through a compatibility
environment on Apple Silicon. Our ARM64 launcher starts the Windows Steam client;
Steam owns game installation, authentication, updates and game launch.
We are not rebuilding gameplay or claiming an ARM64 port of Source 2.

## Useful contributions

- Improve bounded PE and VPK parsing, with synthetic malformed-input fixtures.
- Document an observed interface against an exact binary digest and build.
- Improve Wine/DXMT configuration against reproducible failures.
- Improve isolated installation, diagnostics and native launcher behavior.
- Record reproducible comparisons that distinguish static evidence from execution.

## Source provenance

Contributions should identify their public documentation and any reused dependency
and license. Repository code is covered by the MIT license. Third-party material
keeps its own ownership and license.

Game executables, DLLs, assets, authentication material, extracted content, and raw
decompiler output belong in local research storage such as the ignored .local/
directory. Public research notes should describe observed interfaces and behavior,
cite evidence identifiers and artifact hashes, and preserve unknowns.

Leaked Valve source is not a contribution source for this project. A decompiler
session alone also does not establish a formal clean-room development process.

## Verification

Run `make check` on Apple Silicon before submitting launcher/parser changes.
The tests use synthetic fixtures and do not download or execute Windows software,
require Valve files, or use Steam credentials. `make test` checks the inspector;
`make test-app` checks the native launcher. Keep game files and raw runtime logs
out of CI and Git. See THIRD_PARTY.md before adopting external implementation code.

For observations involving an installed game, include the binary SHA-256, provider
version, operation, evidence ID, and the question the observation answers. State
whether the target was executed. Do not infer live behavior from static strings.
Official online compatibility requires an observed official session; a passing
launcher test, a Steam login or an offline match does not establish it.

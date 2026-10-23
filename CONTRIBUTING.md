# Contributing

The target is an original, native macOS/ARM64 implementation. The current
milestone is a static inspection tool, not a playable Counter-Strike 2 client.

## Useful contributions

- Improve bounded PE and VPK parsing, with synthetic malformed-input fixtures.
- Document an observed interface against an exact binary digest and build.
- Implement independent resource decoding from documented formats.
- Add a native rendering experiment with explicit feature and compatibility limits.
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

Run make test before submitting parser changes. The tests use synthetic fixtures;
they do not require Valve files, Steam credentials, or a running game.

For observations involving an installed game, include the binary SHA-256, provider
version, operation, evidence ID, and the question the observation answers. State
whether the target was executed. Do not infer live behavior from static strings.

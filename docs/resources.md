# Resources assessed from awesome-cs2

Starting catalog supplied by the project owner:
[samyycX/awesome-cs2](https://github.com/samyycX/awesome-cs2).
It is useful for discovering resources, not a complete game engine or a license
grant over its linked projects.

| Resource | Useful contribution | Boundary |
| --- | --- | --- |
| [ValveResourceFormat / Source2Viewer](https://github.com/ValveResourceFormat/ValveResourceFormat) | Source 2 resources, models, maps, materials, shaders and export tooling. The CLI has a macOS ARM64 build. | Asset parsing/rendering is not the complete Source 2 runtime. Review component licenses; the project's test-file corpus has a separate provenance boundary. |
| [ValvePak](https://github.com/ValveResourceFormat/ValvePak) | A maintained public VPK implementation and API reference. | This repository's initial reader is original C++ code based on public format documentation. No .NET dependency is bundled. |
| [Source2SchemaDumper](https://github.com/GAMMACASE/Source2SchemaDumper) | Describes classes, fields, enums and sizes, and can generate analysis headers. | Requires the relevant running server/plugin environment; metadata is not method implementation or a portable engine. |
| [DepotDownloader](https://github.com/SteamRE/DepotDownloader) | Reproducible acquisition by accessible depot/manifest and platform. | Its GPL-2.0 code is not bundled here. It downloads a selected version; it does not port it. |
| [AlliedModders HL2SDK cs2 branch](https://github.com/alliedmodders/hl2sdk/blob/cs2/README.md) | Historical community SDK pointer. | Its README states that the branch is no longer maintained and points to alliedmodders/s2sdk. Verify the destination's availability and license before adopting it. |
| Schemas, protobufs, events and command catalogs linked by awesome-cs2 | Candidate interface and data-model documentation. | Match every observation to a build and platform. Interfaces and plugins alone do not provide the game engine or guarantee official service compatibility. |

## Format references used for the first tool

- [Microsoft Portable Executable format](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format).
- [Source 2 Wiki VPK format](https://www.source2.wiki/FileFormats/vpk), including
  root/extension space markers, preload bytes, and the version 2 signature-descriptor
  layout. This is community format documentation, not a Valve compatibility promise.

## Steam and open source

Valve documents [open-source distribution considerations](https://partner.steamgames.com/doc/sdk/uploading/distributing_opensource).
Our permissive license covers original repository code. Any adopted library,
SDK or game content retains its own license and ownership.

## Graphics selection remains open

The Windows build contains a Vulkan rendering module. Its requirements have not
yet been recovered or tested on an Apple GPU. Evaluate a native Metal backend or
a currently maintained Vulkan-on-Metal implementation against measured features.
Do not infer a working game renderer from library availability.

# Initial investigation — 2026-10-23

## Question and current answer

Can obtaining pseudocode with Ghidra directly produce a native Apple Silicon CS2
client that users launch from Steam?

The investigation recovered actual bootstrap pseudocode and established a first
native inspection component. It has not produced an ARM64 game engine, a playable
client, or verified access to CS2 services. Ghidra supplies evidence of compiled
behavior; rebuilding the engine requires additional implementation and validation.

## Artifact scope

The local Steam manifest reports AppID 730, build 24957633, with an installed
Windows copy. The separate macOS Steam library contains an incomplete download;
the complete Windows installation supplied this investigation's files.

| Artifact | Format and CPU | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| game/bin/win64/cs2.exe | PE32+, x86_64 | 2,967,704 | 427777df3271a7e423e7b9accdb7b40bda47d6683b6ac1d75d129f26e5103dbf |
| game/bin/win64/engine2.dll | PE32+, x86_64 | 6,768,280 | eba2f4251cbb6622358db38551130dfddd688622f792dbde1d91907d5478eb7f |
| game/csgo/bin/win64/client.dll | PE32+, x86_64 | 37,560,472 | 84bcae9db379bed5acb3d81228abef86fbd61b6cdb2b3accdc5dd0f32e8f89f9 |

The manifest build identifies the local installation record. The hashes identify
the actual bytes inspected; they do not authenticate Valve's publisher identity.
Client.dll received header/import inspection, not Ghidra decompilation.

## Ghidra observations

Provider: REA 6.7.0 with Ghidra 12.1.4. The game itself was not executed.

| Question | Static observation | REA evidence |
| --- | --- | --- |
| What is the launcher inventory? | Image base 0x140000000; 7 mapped segments; 853 recognized procedures and 433 defined strings. | ev_c4c5e7e38a52d86a4a99836534050479e7fd1ae416c2d3af4e81be695041bbc7 |
| Where does its executable entry start? | The recognized entry is 0x14000ea60. Its pseudocode enters the security-cookie/CRT startup path. | ev_98101ca1738d22466adcf52b57831dc6fd427bb4cc1b87884d575c0eeefb3e02; ev_7c979065feba920259298da64f49716fd006cc2adb2dda28876ee26b827f9b40 |
| How does the launcher reach the engine? | String references lead to function 0x140004650. Its pseudocode includes Windows path/environment APIs, an SSE4.2-related guard, loading engine2, and looking up Source2Main for indirect dispatch. | ev_97027e0b6b00a643af475cd59c346de70155071f94311faf8848bf4d6d101d7d; ev_05ae6b3d5bed92c820661b3bb00cc9ecdf7a1f333c937046bc4aa5751730d3aa; ev_4a64dcaae20ebfdae94b1663ae86a450747d2b1968145a2b959a761f07350d3f |
| Is Source2Main present in the selected engine? | Ghidra resolves Source2Main at 0x18020d9a0 in engine2.dll. | ev_0d81a8f4b4e35a8f0fda10a5c7cfa7d25fe358aabd62217548917809f7e30a93 |
| What does that entry do? | Recovered pseudocode references thread initialization, command-line handling, logging/minidump facilities, allocator state, a delegated startup function, and Steam shutdown. | ev_4438664dfe9c6736a93a4e68c9c2423a5de2b75357473ca654c51bc92d6f94ef |
| Does the delegated function expose platform obligations? | Function 0x18020a8a0 references platform mutex, OS notification/QoS calls, system interfaces and an engine-loop transition. Many calls remain indirect. | ev_2307e8112ae035381e049667e34645090d714528ea2dfb914e383317ddd5786b |
| How large is the inspected engine inventory? | Ghidra recognizes 13,171 procedures and 10,197 defined strings in engine2.dll. This is an inventory, not semantic recovery of every procedure. | ev_65c1b24203df66c405301c19a92455f9fcce7e5e2b0a25235129c6b58000dce2 |

The recovered bootstrap reports a type-propagation warning. Source2Main reports an
unreachable-block warning; the delegated startup reports overlapping global
symbols. Inferred function signatures and virtual-call targets are not reliable
enough to treat this output as rebuildable source.

Complete local records are stored below .local/evidence/. Readable selected
pseudocode is below .local/pseudocode/. Both native analysis sessions were closed
after exporting evidence. Those local records are intentionally outside Git.

## Native component validated

The repository's own inspector is a Mach-O ARM64 executable. It parsed the selected
PE files and these actual VPK directories:

| Directory | Version | Entries | Referenced archive indices | Header/tree bytes read |
| --- | ---: | ---: | ---: | ---: |
| game/csgo/pak01_dir.vpk | 2 | 135,686 | 494 | 6,185,299 |
| game/core/pak01_dir.vpk | 2 | 1,549 | 7 | 63,545 |
| game/csgo/shaders_vulkan_dir.vpk | 2 | 301 | 4 | 14,175 |

These counts describe index metadata. They do not prove that all referenced chunks
are available, checksums match, or resources can be rendered. Empty entries in the
core and shader packages use an offset sentinel of 0xffffffff with zero data
length; that observed value is retained without treating it as a readable range.

## Feasibility boundaries

| Area | Established | Remaining obligation |
| --- | --- | --- |
| CPU and binary format | The selected game modules are Windows x86_64 PE files. Our inspector is macOS ARM64. | Implement and compile native engine/game behavior, with correct types, ABI, concurrency, floating-point and SIMD semantics. |
| Platform layer | Selected startup paths reference Windows APIs and platform-specific engine interfaces. | Implement macOS windowing, lifecycle, paths, synchronization, input and audio obligations. |
| Rendering | A Windows x86_64 rendersystemvulkan.dll exists in this installation. | Establish its required Vulkan features and shaders, then validate a macOS graphics implementation. The module's existence does not establish a compatible renderer. |
| Content | The native tool can parse real VPK directory metadata. | Read and verify payloads, decode resources, and implement the systems consuming them. |
| Steam | Valve documents macOS x64/ARM64 Steamworks binaries. | Independently validate integration, licensing assumptions and any CS2 backend acceptance. |
| Official Steam launch | Steamworks documents permissions for publishing builds and launch configuration. | The AppID 730 publisher must authorize that product's official macOS build. A community repository cannot supply those permissions. |

Valve's current [CS2 product page](https://store.steampowered.com/app/730/CounterStrike_2/)
lists Windows and SteamOS/Linux requirements. The [Steamworks API](https://partner.steamgames.com/doc/sdk/api)
does support a universal macOS library. [Publishing documentation](https://partner.steamgames.com/doc/sdk/uploading)
requires application permissions. [Authentication](https://partner.steamgames.com/doc/features/auth)
and [VAC integration](https://partner.steamgames.com/doc/features/anticheat/vac_integration)
documentation do not establish acceptance of a reconstructed CS2 client.

The official public [Source SDK 2013](https://github.com/ValveSoftware/source-sdk-2013)
is not the complete CS2/Source 2 source. No complete public official CS2 engine
source suitable for rebuilding this game was established in this investigation.

## Next acceptance gate

Implement one bounded VPK entry read, validate its CRC32, and decode a selected
resource from a user-owned installation. Then display that resource using a
native macOS graphics path. Document the exact resource format, GPU requirements,
and output comparison. Passing that gate establishes a resource/renderer
experiment; gameplay and official multiplayer remain separate unresolved gates.

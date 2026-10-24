# External software

The repository's original launcher and inspector are MIT licensed. No code was
copied from CS2Kit. Runtime archives, Steam, game binaries and assets are not
included in this repository or in the launcher ZIP.

The optional managed runtime downloads these exact upstream packages over HTTPS
and checks their full SHA-256 before extraction:

| Component | Upstream release | SHA-256 |
| --- | --- | --- |
| Sikarugir Wine 10.0 | [WS12WineSikarugir10.0_6](https://github.com/Sikarugir-App/Engines/releases/tag/v1.0) | `9da7ee0cbf386522f3a9906943726d9c3c125dbbd9ab120e3cde80e88d6091b2` |
| Wrapper dependencies | [Template 1.0.11](https://github.com/Sikarugir-App/Template/releases/tag/v1.0) | `9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a` |
| DXMT builtin | [DXMT v0.80](https://github.com/3Shain/dxmt/releases/tag/v0.80) | `8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d` |

Wine and its synchronization components retain their LGPL terms; the wrapper
dependencies retain their individual upstream licenses; DXMT v0.80 retains its
upstream license. The MIT license of this repository does not replace them.
Upstream sources and license files are available through the linked projects.
Do not redistribute a runtime bundle without satisfying the licenses of all its
components. This launcher only bundles its original executable and documentation.

Rosetta, CrossOver, Steam and Counter-Strike 2 are third-party products with their
own terms. Rosetta is installed through Apple's own installer, with the user's
license acceptance. CrossOver is an optional existing-installation backend; it is
not downloaded or bundled. Steam is downloaded from Valve's official HTTPS
installer endpoint; its installer and sign-in remain Valve's normal UI.

[CS2Kit](https://github.com/piwas-21/cs2-apple-silicon), licensed GPL-3.0, was a
public documentation reference for choosing a Wine/DXMT baseline. Its reported
results are not verification of this launcher or of official online play here.

This project is not affiliated with or endorsed by Valve, Apple or CodeWeavers.

# Portal: Prelude RTX: RTX Remix 1.6.1 upgrade

One-click upgrade of the **Steam** version of Portal: Prelude RTX from its 2023 RTX Remix runtime (bridge `0.2.1-prelude`, `dxvk-remix 1.9.3`) to **NVIDIA RTX Remix 1.6.1**:

- It fixes the rainbow, pixelated shadows the old runtime draws on RTX 50-series GPUs with current drivers.
- It adds **DLSS 5 (DLSS 3D-Guided Neural Rendering)**, current DLSS Super Resolution, Ray Reconstruction and Frame Generation, and NVIDIA's runtime fixes since 2023.

**Nothing is patched or edited.** The installer downloads NVIDIA's unmodified 1.6.1 release from [NVIDIA's GitHub](https://github.com/NVIDIAGameWorks/rtx-remix/releases/tag/remix-1.6.1), checks its SHA-256 and puts it in place of the old runtime. It keeps the stock files as backups, so `Uninstall.bat` can put the game back exactly as Steam installed it.

## What changes

| | Stock (Steam, 2023) | After the upgrade |
|---|---|---|
| RTX Remix bridge | `remix-0.2.1-prelude` | RTX Remix 1.6.1 (`for-x86-games` release) |
| Remix runtime | `dxvk-remix v1.9.3` (14 MB) | `dxvk-remix` 1.6.1 (270 MB) |
| DLSS Super Resolution / Frame Generation | 3.1.0 / 3.1.13 | 310.9.1 / 310.9.16 |
| DLSS Ray Reconstruction | none | 310.9.1 |
| **DLSS 5 Neural Rendering** | none | 310.9.16, **off by default** ([how to turn it on](docs/DLSS5-NEURAL-RENDERING.md)) |
| Neural Radiance Cache, XeSS | none | included |
| Game files, the Prelude asset mod, `rtx.conf`, `dxvk.conf` | | unchanged |

Only `bin\d3d9.dll`, `bin\NvRemixBridge32.dll` and `bin\.trex\` are involved. That is 196 files installed and 65 stock files kept as backups. The file-by-file account is in [docs/WHAT-CHANGED.md](docs/WHAT-CHANGED.md).

## Requirements

- Portal: Prelude RTX from Steam (app 2410180). This was built against Steam build 11741294, the 2023-07-19 depot, which is the current build as of November 2026.
- An NVIDIA RTX GPU with **driver 616.92 or newer**, NVIDIA's minimum for Remix 1.6.1. The installer checks this.
- 64-bit Windows 10 or 11, with about 2 GB free: 824 MiB for NVIDIA's download plus about 1 GB in the game's drive.

Tested on Windows 11 with a GeForce RTX 5090 and NVIDIA driver 621.24.

## Install

1. Download `PortalPreludeRTX-RemixUpgrade-v1.0.0.zip` from **[Releases](../../releases)** and extract it anywhere.
2. Quit the game, then double-click **`Install.bat`**. Windows may warn that the script is unsigned; choose *More info*, then *Run anyway*. The installer then:
   - finds the game through Steam,
   - downloads NVIDIA's package (`rtx-remix-for-x86-games-release-remix-1.6.1.zip`, 824 MiB) and checks its SHA-256,
   - backs up the stock files, installs, and checks all 196 files.
3. Start the game from Steam as usual.

To skip the download, put NVIDIA's zip next to `Install.bat`, in the folder above it or in your Downloads folder. The installer uses it if the SHA-256 matches.

Options (add them after `Install.bat`):

| Option | What it does |
|---|---|
| `-GameDir "D:\...\Portal Prelude RTX"` | Use this game folder, if it is not found automatically |
| `-PackagePath "D:\...\rtx-remix-...-1.6.1.zip"` | Use a copy of NVIDIA's zip from somewhere else |
| `-DryRun` | Show what would change; change nothing |
| `-EnableNeuralRendering` | Also turn on DLSS 5: `rtx.dlssNeuralRendering.enable = True` in `user.conf` |
| `-Force` | Move files with unexpected content into `_RemixUpgrade_quarantine\` instead of stopping |
| `-NoDownload` | Never download; fail if NVIDIA's zip is not found locally |

## After a Steam update or "Verify integrity of game files"

Either one puts some of the old files back, so the game runs on a mix of runtimes. Run `Install.bat` again. It sees the mix (`Verify.bat` reports **MIXED**) and repairs it. If NVIDIA's zip is still in the folder, nothing is downloaded again.

## Roll back

`Uninstall.bat` restores the 65 stock files from the backups and removes the Remix 1.6.1 files. The game is then exactly as Steam installed it, and tests confirm that byte for byte.

If the backups are gone, it changes nothing and tells you what to do instead: run Steam's **Verify integrity of game files**, then `Uninstall.bat` again to clear the leftovers.

## Check

| Command | What it checks |
|---|---|
| `Verify.bat` | Read-only. Reports PATCHED, STOCK or MIXED and lists any file with unexpected content |
| `Verify.bat -Full` | Hashes every file in the game folder and classifies it against Steam's own stock file list for the build, the patch and the backups. Takes about a minute on an NVMe drive and saves a CSV in `logs\` |
| `Verify.bat -CompareTo logs\full-....csv` | Compares every file with an earlier `-Full` result |

## Safety

- The installer never deletes a file unless the same bytes are kept elsewhere: in a backup, or in NVIDIA's package.
- A file with content it does not recognise stops it before anything changes, unless you pass `-Force`, which moves it into `_RemixUpgrade_quarantine\`.
- Every file is extracted to a temp name, checked against [`manifest/patch-files.csv`](manifest/patch-files.csv), and only then put in place. An interrupted run can simply be run again.
- `rtx.conf`, `dxvk.conf`, `user.conf`, saves and the Prelude asset mod are never touched, except `user.conf` when you pass `-EnableNeuralRendering`.
- Each run writes a log to `logs\` next to the scripts and a short record, `_RemixUpgrade_installed.txt`, in the game folder.

## Troubleshooting

- **"Could not find Portal: Prelude RTX"**: run `Install.bat -GameDir "<your game folder>"`.
- **"Files with unexpected content"**: something other than the stock or 1.6.1 runtime is in `bin\`, for example another manual install. Run Steam's *Verify integrity of game files* and then `Install.bat`, or use `-Force` to set those files aside.
- **Driver warning**: update the NVIDIA driver to 616.92 or newer. DLSS 5 will not load on older drivers.
- **The game is running**: the scripts stop. Quit the game first.

## Repo contents

| Path | What |
|---|---|
| `Install`, `Uninstall`, `Verify` (`.bat` + `.ps1`), `lib/Common.ps1` | The scripts. Windows PowerShell 5.1, no other dependencies |
| `manifest/patch-files.csv` | The 196 files the upgrade owns: target, source, size, SHA-256 |
| `manifest/stock-files.csv` | The 65 stock 0.2.1 files it backs up: size, SHA-256, Steam SHA-1 |
| `manifest/package-remix-1.6.1-x86.csv` | All 386 files in NVIDIA's zip, and where (or why not) each one is installed |
| `manifest/steam-stock-depot2410181-manifest4949530312671311881.csv` | Steam's list of every stock file for the build (13,121 files). `Verify.bat -Full` uses it |
| `docs/` | [What changed](docs/WHAT-CHANGED.md), [DLSS 5](docs/DLSS5-NEURAL-RENDERING.md), [how it was verified](docs/VERIFICATION.md) |
| `tools/` | Maintainer tools: parse Steam's manifest, hash the package and an install, rebuild the manifests, run the tests, build the release |

## Credits and licences

- **Portal: Prelude RTX** is its creators' work, published on Steam. This repo contains none of its game or mod files.
- **RTX Remix** is by NVIDIA. The bridge and runtime are MIT-licensed (`LICENSE.txt` and `ThirdPartyLicenses-*.txt` in NVIDIA's package); DLSS and the other NVIDIA SDK components are under NVIDIA's own licences. This repo does not redistribute any NVIDIA file: the installer downloads it from NVIDIA.
- The scripts and docs in this repo are under the [MIT License](LICENSE).
- Not affiliated with NVIDIA, Valve or the Portal: Prelude RTX team.

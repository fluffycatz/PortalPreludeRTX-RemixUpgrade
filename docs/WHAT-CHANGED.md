# What the upgrade changes, file by file

Everything here was measured, not assumed:
- Steam's own depot manifest for the current build (13,121 stock files, each with its SHA-1),
- NVIDIA's release package, matched against the SHA-256 GitHub publishes for it,
- a known-good hand-made upgrade, all 13,352 files of which were hashed.

The machine-readable versions are in [`manifest/`](../manifest).

**Short version:** no game file, no Prelude asset and no NVIDIA file is patched or edited. The upgrade replaces the RTX Remix runtime in `bin\` with NVIDIA's unmodified 1.6.1 `for-x86-games` release and keeps Prelude's own `bridge.conf`. Everything else stays as Steam installed it.

## At a glance

| | Count |
|---|---|
| Files the upgrade installs | **196**: 195 from NVIDIA's zip plus Prelude's stock `bin\.trex\bridge.conf` |
| Stock 0.2.1 files moved to backups | **65**: `bin\d3d9.dll`, `bin\NvRemixBridge32.dll` and the 63 files of `bin\.trex\` |
| NVIDIA zip files deliberately not installed | **191**: the 189-file ARM64 runtime, `d3d8to9.dll` and its licence |
| All other game files | untouched |

## Why

1. **Shadow artifacts.** Prelude shipped in 2023 with a Prelude-specific Remix build: bridge `remix-0.2.1-prelude` and runtime `dxvk-remix v1.9.3`. On RTX 50-series GPUs with current (62x) drivers it draws rainbow, pixelated shadows. Players on Steam and Reddit fixed it by swapping in NVIDIA's current release. This repo automates that swap and makes it reversible.
2. **New features.** RTX Remix 1.6.1, released 2026-10-23, brings DLSS 3D-Guided Neural Rendering ("DLSS 5"), current DLSS Super Resolution, Ray Reconstruction and Frame Generation (up to 6x on supported hardware, per NVIDIA's notes), and NVIDIA's other runtime fixes since 2023.

## Components, old to new

| Part | Stock (Steam, 2023) | Upgrade (RTX Remix 1.6.1) |
|---|---|---|
| Bridge client, 32-bit, in the game process | `bin\d3d9.dll` + `bin\NvRemixBridge32.dll`, `bridge-remix (remix-0.2.1-prelude)` | `bin\d3d9.dll` alone (the 1.6.1 bridge build). The second DLL no longer exists in this layout |
| Bridge server, 64-bit | `bin\.trex\NvRemixBridge.exe` (1.0 MB) | same path (1.1 MB) |
| Remix runtime | `bin\.trex\d3d9.dll`, `dxvk-remix (v1.9.3)`, 14.2 MB | the 1.6.1 build, 269.8 MB |
| DLSS Super Resolution | `nvngx_dlss.dll` 3.1.0.0 | 310.9.1.0 |
| DLSS Frame Generation | `nvngx_dlssg.dll` 3.1.13.0 | 310.9.16.0 |
| DLSS Ray Reconstruction | none | `nvngx_dlssd.dll` 310.9.1.0 (new) |
| **DLSS 5 Neural Rendering** | none | `nvngx_dlssnr.dll` 310.9.16.0, 254 MB (new). See [DLSS5-NEURAL-RENDERING.md](DLSS5-NEURAL-RENDERING.md) |
| NRD denoisers | `NRD.dll` 4.1.0.0 | 4.13.0 |
| Neural Radiance Cache | none | `NRC_Vulkan.dll` 0.15.0.0 (new) |
| Intel XeSS | none | `libxess.dll` 2.0.2.53 (new) |
| Reflex | `NvLowLatencyVk.dll` | **byte-identical** file |
| RTX IO | `rtxio.dll` (2.3 MB) | newer `rtxio.dll` (2.5 MB) |
| Nsight Aftermath | 2.18.0.0 | 2.27.0.0 |
| Streamline | `sl.common`, `sl.dlss`, `sl.dlss_g`, `sl.interposer`, `sl.reflex` `.dll` | not in the 1.6.1 package; retired to the backup |
| USD | one `usd_ms.dll` + `tbb.dll` | split `usd_*.dll`, `tbb12.dll`, Remix USD plugins (`RemixCategories`, `RemixParticleSystem`) |
| New support files | | `cudart64_13.dll`, `nvrtc64_130_0.dll`, `nvrtc-builtins64_133.dll`, `crashpad_handler.exe` / `crashpad_wer.dll` (crash reporting), `bridge.defaults.conf` |
| Launcher | none | `bin\NvRemixLauncher32.exe` (optional; not used when you start the game from Steam) |
| Licences | none | `bin\LICENSE.txt` (MIT), `bin\ThirdPartyLicenses-bridge.txt`, `bin\ThirdPartyLicenses-dxvk.txt` |

Versions are read from each file's Windows version resource.

## File operations

All paths are relative to the game folder. The exact lists, with sizes and SHA-256, are [`manifest/patch-files.csv`](../manifest/patch-files.csv) and [`manifest/stock-files.csv`](../manifest/stock-files.csv).

**Backed up:**

- `bin\d3d9.dll` becomes `bin\d3d9.dll.prelude-0.2.1.bak`
- `bin\NvRemixBridge32.dll` becomes `bin\NvRemixBridge32.dll.prelude-0.2.1.bak`
- `bin\.trex\` (63 files) goes to `bin\.trex.prelude-0.2.1.bak\`. Any log the old runtime left in `bin\.trex\`, such as `NvRemixBridge.log`, moves with it.

**Installed** from `rtx-remix-for-x86-games-release-remix-1.6.1.zip`. Each zip member `X` goes to `bin\X`:

- `bin\d3d9.dll`, `bin\NvRemixLauncher32.exe`, `bin\LICENSE.txt`, `bin\ThirdPartyLicenses-bridge.txt`, `bin\ThirdPartyLicenses-dxvk.txt`
- `bin\.trex\`: 190 files. 50 of them replace a stock file at the same path with new bytes. 3 are byte-identical to the stock file at the same path (`NvLowLatencyVk.dll`, `usd\plugInfo.json`, `usd\usd\resources\codegenTemplates\plugInfo.json`). 137 are new.
- `bin\.trex\bridge.conf`: Prelude's stock file, kept as is. NVIDIA's package does not contain a `bridge.conf`:

  ```
  # lowest possible latency
  presentSemaphoreMaxFrames = 1
  ```

**Retired.** These stock 0.2.1 files have no counterpart in 1.6.1, so they exist only in the backup afterwards:

`bin\NvRemixBridge32.dll` and, in `bin\.trex\`: `artifacts_readme.txt`, `sl.common.dll`, `sl.dlss.dll`, `sl.dlss_g.dll`, `sl.interposer.dll`, `sl.reflex.dll`, `tbb.dll`, `usd_ms.dll`, `usd\ndr\resources\plugInfo.json`.

**Not installed from the package:**
- `.trex_arm64\` (189 files): the runtime for Windows on ARM.
- `d3d8to9.dll` and `ThirdPartyLicenses-d3d8to9.txt`: only for Direct3D 8 games. Prelude is Direct3D 9.
- The `-for-x64-games` zip is not used. It is the in-process runtime for 64-bit games and has no bridge. Prelude's `hl2.exe` is 32-bit, so it needs the `for-x86-games` bridge package.

**Not touched:** `rtx.conf`, `dxvk.conf`, `user.conf`, `bin\dxvk_d3d9.dll` (Prelude's own file, not part of Remix), `rtx-remix\mods\prelude_remix\` (the Prelude asset mod, about 12 GB) and every other game file.

## Configuration

- **`rtx.conf` and `dxvk.conf`** keep Prelude's tuned settings, and 1.6.1 reads them as they are. The only notice it logs is:
  > `[Deprecated Config] rtx.nonOffsetDecalTextures has been deprecated, we have moved all your textures from this list to rtx.decalTextures, no further action is required from you.`
- **Prelude's stock `rtx.conf`** sets three values worth knowing about:
  - `rtx.dlfg.enable = False`: DLSS frame generation starts **off**. 1.6.1's own default is on. Turn it on in the Alt+X menu if you want it.
  - `rtx.qualityDLSS = 1`
  - `rtx.dlssPreset = 2`: Custom, which keeps that explicit DLSS mode.

  These values were read from the stock runtime's startup log.
- **New layers in 1.6.1.** The in-game menu saves to `user.conf` in the game folder, which overrides `rtx.conf` ([NVIDIA's RemixConfig.md](https://github.com/NVIDIAGameWorks/dxvk-remix/blob/remix-1.6.1/documentation/RemixConfig.md)). 1.6.1 also keeps a small per-user file at `%LOCALAPPDATA%\NVIDIA\RTXRemix\user_settings\<id>.conf`, which holds your answer to its first-launch crash-reporting and usage-data question.
- **DLSS 5** is off by default: `rtx.dlssNeuralRendering.enable = False`. See [DLSS5-NEURAL-RENDERING.md](DLSS5-NEURAL-RENDERING.md).

## What the 1.6.1 log shows

From a 20-minute session on 1.6.1, compared with the stock runtime's log:

- **It started normally.** Crash reporting initialized, the Neural Radiance Cache was supported (Ultra preset) and Reflex initialized.
- **Already in the stock runtime's log, not caused by the upgrade.** 5 + 5 errors about textures under `portal prelude rtx\rtx-remix\gameReadyAssets\SubUSDs`. They come from paths the Prelude mod references.
- **New in 1.6.1, informational only:**
  - `Legacy light attribute detected`: the 2023 mod's USD lights use the old UsdLux attribute names, and 1.6.1 still reads them.
  - `[SecretReplacement] Could not find stage`: six optional companion-cube variants (`SubUSDs/SM_Prop_CompanionCube_*.usd`).
  - Two `ConvertFormat: Unknown format encountered: D3D9Format::SSAA` warnings.

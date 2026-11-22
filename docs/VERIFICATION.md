# How this was verified

## Sources of truth

| Source | What it is | Identity |
|---|---|---|
| Steam's depot manifest | Steam's own list of every stock file, with size and SHA-1 | Depot 2410181, manifest 4949530312671311881, created 2023-07-19, build 11741294. 13,121 files, 26,080,238,534 bytes. Parsed from Steam's `depotcache` by `tools/inventory.py steam` into `manifest/steam-stock-depot2410181-manifest4949530312671311881.csv` |
| NVIDIA's release | `rtx-remix-for-x86-games-release-remix-1.6.1.zip`, tag `remix-1.6.1`, published 2026-10-23 | 863,551,854 bytes, SHA-256 `18237be32a619634051e7f9e971625756557b72aceb38b18659fff7ad726a571`. Equal to the `digest` GitHub publishes for the asset. NVIDIA's own `-crc.txt` for the zip also matches |
| A known-good upgrade | A Steam install upgraded by hand to 1.6.1 that runs well (Windows 11, RTX 5090, driver 621.24) | All 13,352 files hashed (SHA-256 and SHA-1) |

## Findings

- **The upgrade is NVIDIA's unmodified files.** In the known-good upgrade, all 195 package files sit at `bin\<member path>` with the package's exact SHA-256. The 196th file, `bin\.trex\bridge.conf`, matches Steam's SHA-1 for Prelude's stock file.
- **The backups are the genuine stock files.** All 65 files kept as `*.prelude-0.2.1.bak` match Steam's SHA-1 for their original path. The manifests in `manifest/` were generated from these checks, and the generator stops if any file does not match.
- **Everything else is untouched.** Apart from the runtime, every game file matched Steam's manifest. The only exceptions were files changed by play: saves, caches and settings saved from the menu.

## Installer tests

The tests run on a stand-in for a fresh Steam install, built by `tools/test_tree.py make-stock`. It has the game markers plus the whole `bin\` folder rebuilt from the backups, and every `bin\` file is checked against Steam's SHA-1 list. The "reference" in the table is the known-good upgrade.

`tools/run_tests.ps1` runs the whole matrix. It only writes inside its work folder.

| # | Scenario | Expected |
|---|---|---|
| T1 | `Install -DryRun` on stock | exit 0, folder unchanged |
| T2 | `Install` on stock | exit 0; `bin\` byte-identical to the reference (357 files, backups included) |
| T3 | `Install` again, with no package available (`-NoDownload`) | "nothing to do", exit 0 |
| T4 | `Verify` | PATCHED |
| T5 | Steam's "Verify integrity" simulated: every stock file written back over the upgrade, extra files left in place | `Verify` says MIXED. `Install` repairs it, and `bin\` is identical to the reference |
| T6 | `Uninstall`, then again | the whole folder is identical to the stock stand-in. Second run: "nothing to do" |
| T7 | A stock file with unknown content | `Install` refuses (exit 2) with the folder unchanged. `-Force` quarantines that one file and installs |
| T8 | `-EnableNeuralRendering` twice, with an existing `user.conf` | the line is added, other lines are kept, the old file is kept once. The second run changes nothing |
| T9 | An interrupted install: 40 files missing, a stray temp file, one stock file not yet moved | repaired; identical to the reference |
| T10 | `Uninstall` with the backups deleted | refuses (exit 2) with the folder unchanged. After a simulated Steam verify it completes |
| T12 | The release bundle, every file marked as downloaded from the Internet (Zone 3, as a browser does), NVIDIA's zip in the folder above, run through `Install.bat` itself | finds the zip by itself, installs; identical to the reference |
| TD | The release bundle with no zip anywhere | `Install.bat` downloads the 824 MiB package from NVIDIA, verifies it and installs; identical to the reference |

The results of each release's own run are in that release's notes.

## Not covered

- **A real Steam "Verify integrity" on a live install.** T5 and T10 simulate it: they put every stock file back and leave the files Steam does not know about. That matches how Steam's verify behaves, since it re-acquires changed or missing files and leaves other files alone. The real thing has not been run against this installer.
- **DLSS 5 in game.** The option names and defaults come from NVIDIA's documentation; the in-game effect was not reviewed here.

## Running the checks yourself

```powershell
Verify.bat
Verify.bat -Full
```

For maintainers, rebuilding the manifests for a new Steam build or a new Remix release:

```powershell
python -I tools\inventory.py steam --manifest "<Steam>\depotcache\2410181_<manifest>.manifest" --out steam.json
python -I tools\inventory.py package --zip rtx-remix-for-x86-games-release-remix-<version>.zip --out package.json
python -I tools\inventory.py snapshot --game "<upgraded game folder>" --out live.json
python -I tools\build_manifests.py --steam steam.json --package package.json --live live.json --out manifest
python -I tools\test_tree.py make-stock --live "<upgraded game folder>" --out "<template>\Portal Prelude RTX" --steam-json steam.json
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -Reference "<upgraded game folder>" -Template "<template>" -Package "<NVIDIA zip>" -WorkDir "<empty folder>" -BundleZip dist\<bundle>.zip -DownloadTest
```

# Changelog

## v1.0.0 (2026-11-21)

First public release.

- `Install.bat` upgrades a stock Steam install of Portal: Prelude RTX (build 11741294) to NVIDIA RTX Remix 1.6.1 (`for-x86-games` release). The result is byte-identical to a known-good hand-made upgrade: all 357 files in `bin\`, backups included.
- It finds the game through Steam, and downloads NVIDIA's package from NVIDIA's GitHub release, checking it against NVIDIA's published SHA-256.
- It repairs the mixed state left by Steam's "Verify integrity" or a game update, and resumes an interrupted install.
- `Uninstall.bat` restores the 65 stock files from the backups. The result is byte-identical to the stock install.
- `Verify.bat` checks the install read-only. `-Full` classifies every file against Steam's own manifest, and `-CompareTo` compares with an earlier `-Full` result.
- Options: `-EnableNeuralRendering` (DLSS 5), `-DryRun`, `-Force` (quarantine instead of stopping), `-NoDownload`.

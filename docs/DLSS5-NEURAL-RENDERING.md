# DLSS 5 in Portal: Prelude RTX (DLSS 3D-Guided Neural Rendering)

RTX Remix 1.6 added NVIDIA's DLSS 3D-Guided Neural Rendering, which NVIDIA's release notes call "DLSS 5". The upgrade installs it. **It is off until you turn it on.**

## What it is

- A neural post-process. It runs on the final image after tone mapping, in the LDR (low dynamic range) domain, and adjusts detail, shading, materials, tone and colour. NVIDIA describes the controls as "live artistic controls".
- It ships as `bin\.trex\nvngx_dlssnr.dll`, version 310.9.16 and 254 MB. That file is not in the stock game.
- It needs NVIDIA driver **616.92 or newer**, the minimum for RTX Remix 1.6.1. With an older driver the runtime logs `NVIDIA DLSS-NR cannot be loaded due to an outdated driver.` and the feature stays off.

## Turning it on

Pick one of these:

1. **In game.** Press **Alt+X** to open the Remix menu. Find **DLSS 3D-Guided Neural Rendering** in the rendering settings and enable it, then save. Remix 1.6.1 saves menu settings to `user.conf` in the game folder.
2. **With the installer.** Run `Install.bat -EnableNeuralRendering`. It sets `rtx.dlssNeuralRendering.enable = True` in `user.conf` and keeps every other line. The previous file is kept as `user.conf.before-<time>`.
3. **By hand.** Add this line to `user.conf` in the game folder, and create the file if it is not there:

   ```
   rtx.dlssNeuralRendering.enable = True
   ```

To turn it off, set the value to `False` or delete the line.

NVIDIA's [RemixConfig.md for `remix-1.6.1`](https://github.com/NVIDIAGameWorks/dxvk-remix/blob/remix-1.6.1/documentation/RemixConfig.md) describes how the setting files stack:
- `user.conf` is the **User Settings** layer that the in-game menu saves to, and it overrides the mod's `rtx.conf`.
- Only a selected quality preset (anything but "Custom") sits higher, and only for the values that preset controls.

> These keys and their defaults come from NVIDIA's documentation for this exact version. The in-game effect has **not** been reviewed as part of this repo. After enabling it, check with Alt+X that the option shows as on. `rtx.dlssNeuralRendering.showVramUsage = True` shows the VRAM it takes.

## All options (RTX Remix 1.6.1)

Source: `RtxOptions.md` in [NVIDIAGameWorks/dxvk-remix at tag `remix-1.6.1`](https://github.com/NVIDIAGameWorks/dxvk-remix/blob/remix-1.6.1/RtxOptions.md). The description strings also appear word for word inside the installed `bin\.trex\d3d9.dll`.

| Key (`rtx.dlssNeuralRendering.`) | Type | Default | Range | What it does |
|---|---|---|---|---|
| `enable` | bool | False | | Enable DLSS 3D-Guided Neural Rendering. |
| `intensity` | float | 1 | 0-1 | Overall strength of the effect. |
| `structuralStrength` | float | 0.7 | 0-1 | Adjustments to details, shadows and materials. Lower keeps the original structure. |
| `toneStrength` | float | 0.3 | 0-1 | Adjustments to lightness, darkness and colour. Lower keeps the original tone and colour. |
| `model` | int | 0 | 0, 1, 2 | Model A, B or C. NVIDIA says the look depends on the content, so compare them in the scene. |
| `useAutoMask` | bool | True | | Combine the automatic character mask with the material control mask. |
| `skinStructureStrength` | float | 0.5 | 0-1 | Adjustments to characters when Auto Mask is on. |
| `enableHighlightRecovery` | bool | True | | Recover highlights compressed by the LDR-domain processing. |
| `highlightRecoveryThresholds` | float4 | 1, 8, 0.75, 0.99 | | Smoothstep edges for highlight recovery: exposed HDR max-channel min/max, then LDR max-channel min/max. |
| `enableVolumetricControlMask` | bool | True | | Modulate the control mask with fog, volumetrics and alpha-blended transmittance. |
| `showVramUsage` | bool | False | | Show the SDK's VRAM allocation in the settings. Enable it before activating the feature. |

## Related settings

| Key | 1.6.1 default | Prelude's stock `rtx.conf` |
|---|---|---|
| `rtx.dlfg.enable` (DLSS frame generation) | True | `False`: frame generation starts off. Turn it on in the Alt+X menu if you want it |
| `rtx.dlfg.maxInterpolatedFrames` (1-6; up to 6x Multi Frame Generation is new in 1.6) | 2 | not set |
| `rtx.qualityDLSS` (DLSS mode) | 4 | `1` |
| `rtx.dlssPreset` | 1 | `2` (Custom: keeps the explicit DLSS mode instead of resetting it to Auto) |

<#
.SYNOPSIS
    Upgrades Portal: Prelude RTX (Steam) from its 2023 RTX Remix runtime (bridge "0.2.1-prelude")
    to NVIDIA RTX Remix 1.6.1 (for-x86-games release), byte for byte as verified on a working install.

.DESCRIPTION
    - Finds the game through Steam (or use -GameDir).
    - Uses NVIDIA's official package, rtx-remix-for-x86-games-release-remix-1.6.1.zip: next to this script,
      in Downloads, or downloaded from NVIDIA's GitHub release. Its SHA-256 must match before anything is used.
    - Moves the stock 0.2.1 files to *.prelude-0.2.1.bak backups, installs the 196 Remix 1.6.1 files and checks
      every one against manifest\patch-files.csv.
    - Never deletes a file unless the same bytes are kept elsewhere (in a backup or in NVIDIA's package).
      Files with unexpected content stop the install before anything changes.
    - Leaves rtx.conf, dxvk.conf, user.conf (unless -EnableNeuralRendering), bin\dxvk_d3d9.dll and the Prelude
      asset mod alone.
    - Safe to run again, for example after Steam "Verify integrity of game files" or a game update.

.PARAMETER GameDir             The game folder, if it is not found automatically.
.PARAMETER PackagePath         Path to NVIDIA's zip, if it is somewhere else.
.PARAMETER DryRun              Show what would change and change nothing.
.PARAMETER Force               Move files with unexpected content to _RemixUpgrade_quarantine\ and continue.
.PARAMETER EnableNeuralRendering  Also set rtx.dlssNeuralRendering.enable = True in user.conf (DLSS 5, off by default).
.PARAMETER NoDownload          Never download; fail if the package is not found locally.
#>
[CmdletBinding()]
param(
    [string]$GameDir,
    [string]$PackagePath,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$EnableNeuralRendering,
    [switch]$NoDownload
)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
Start-RunLog 'install'

# ------------------------------------------------------------------ plan
function Get-InstallPlan($State, $Man) {
    $plan = New-Object System.Collections.Generic.List[object]
    $conflicts = New-Object System.Collections.Generic.List[object]
    foreach ($s in $Man.Stock.Keys) {
        $st = $State.StockStatus[$s]; $bk = $State.BackupStatus[$s]; $b = Get-BackupRel $s
        $shared = $Man.Patch.Contains($s) -and ($Man.Patch[$s].SHA256 -eq $Man.Stock[$s].SHA256)
        if ($bk -eq 'other') { $conflicts.Add([pscustomobject]@{ Rel = $b; Why = 'backup copy is not the stock 0.2.1 file' }); continue }
        if ($st -eq 'ok') {
            if ($shared) {
                if ($bk -eq 'missing') { $plan.Add([pscustomobject]@{ Op = 'Copy'; Rel = $s; Rel2 = $b; Why = 'stock file that 1.6.1 also uses: copy into the backup' }) }
            } elseif ($bk -eq 'ok') {
                $plan.Add([pscustomobject]@{ Op = 'Delete'; Rel = $s; Rel2 = ''; Why = 'stock file: an identical copy is already in the backup' })
            } else {
                $plan.Add([pscustomobject]@{ Op = 'Move'; Rel = $s; Rel2 = $b; Why = 'stock file: move into the backup' })
            }
        } elseif ($st -eq 'other') {
            $conflicts.Add([pscustomobject]@{ Rel = $s; Why = 'unexpected content (neither stock 0.2.1 nor Remix 1.6.1)' })
        }
    }
    foreach ($t in $State.PatchOnly) {
        if ($State.PatchStatus[$t] -eq 'other') { $conflicts.Add([pscustomobject]@{ Rel = $t; Why = 'unexpected content (not the Remix 1.6.1 file)' }) }
    }
    foreach ($f in $State.Foreign) {
        if ($f.EndsWith($script:TmpSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $plan.Add([pscustomobject]@{ Op = 'Delete'; Rel = $f; Rel2 = ''; Why = 'temp file left by an interrupted run' })
        } elseif (Test-IsJunk $f) {
            $plan.Add([pscustomobject]@{ Op = 'MoveJunk'; Rel = $f; Rel2 = ($script:TrexBakRel + $f.Substring($script:TrexRel.Length)); Why = 'old runtime log: kept with the 0.2.1 backup' })
        } else {
            $conflicts.Add([pscustomobject]@{ Rel = $f; Why = 'unknown file in bin\.trex' })
        }
    }
    foreach ($t in $Man.Patch.Keys) {
        if ($State.PatchStatus[$t] -eq 'ok') { continue }
        $src = $Man.Patch[$t].Source
        if ($src -like 'builtin:*') { $plan.Add([pscustomobject]@{ Op = 'Write'; Rel = $t; Rel2 = ''; Why = "Prelude's stock bridge.conf (carried over)" }) }
        else { $plan.Add([pscustomobject]@{ Op = 'Extract'; Rel = $t; Rel2 = $src.Substring(4); Why = 'RTX Remix 1.6.1' }) }
    }
    return [pscustomobject]@{ Plan = $plan; Conflicts = $conflicts }
}

function Find-Package([string]$Hint, [switch]$NoDownload) {
    $cands = New-Object System.Collections.Generic.List[string]
    if ($Hint) { $cands.Add($Hint.Trim().Trim('"')) }
    $cands.Add((Join-Path $script:Root $script:PackageName))
    $cands.Add((Join-Path (Split-Path -Parent $script:Root) $script:PackageName))
    if ($env:USERPROFILE) { $cands.Add((Join-Path $env:USERPROFILE ('Downloads\' + $script:PackageName))) }
    foreach ($c in $cands) {
        if (-not [System.IO.File]::Exists($c)) { continue }
        $len = (New-Object System.IO.FileInfo($c)).Length
        if ($len -ne $script:PackageSize) { Write-WarnLine "Ignoring $c (size $len, expected $($script:PackageSize))"; continue }
        Write-InfoLine "Checking $c ..."
        if ((Get-Sha256 $c) -eq $script:PackageSha256) { Write-OkLine "NVIDIA package verified (SHA-256 $($script:PackageSha256.Substring(0,16))...)"; return $c }
        Write-WarnLine "Ignoring $c (SHA-256 does not match NVIDIA's release)"
    }
    if ($Hint) { throw "The package given with -PackagePath was not usable: $Hint" }
    if ($NoDownload) { throw "NVIDIA's package was not found. Download $($script:PackageName) from $($script:PackageUrl) and put it next to Install.bat." }

    $dest = Join-Path $script:Root $script:PackageName
    $part = $dest + '.part'
    Write-InfoLine "Downloading $($script:PackageName) (824 MiB) from NVIDIA's GitHub release ..."
    Write-InfoLine $script:PackageUrl
    if ([System.IO.File]::Exists($part)) { [System.IO.File]::Delete($part) }
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if ([System.IO.File]::Exists($curl)) {
        & $curl -L --fail --retry 3 --output $part $script:PackageUrl
        if ($LASTEXITCODE -ne 0) { throw "Download failed (curl exit code $LASTEXITCODE)." }
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        (New-Object System.Net.WebClient).DownloadFile($script:PackageUrl, $part)
    }
    $len = (New-Object System.IO.FileInfo($part)).Length
    if ($len -ne $script:PackageSize) { throw "Downloaded file has the wrong size ($len bytes, expected $($script:PackageSize))." }
    if ((Get-Sha256 $part) -ne $script:PackageSha256) { throw 'Downloaded file does not match the SHA-256 of NVIDIA''s release. Nothing was installed.' }
    [System.IO.File]::Move($part, $dest)
    Write-OkLine "Downloaded and verified: $dest"
    return $dest
}

function Set-ConfText([string]$Text, [string]$Key, [string]$Value) {
    # Returns the text of a Remix .conf file with "key = value" set, every other line kept (CRLF, like Remix writes).
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in ($Text -split "`r?`n")) { $lines.Add($l) }
    while ($lines.Count -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    $line = "$Key = $Value"
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) { $lines[$i] = $line; $found = $true }
    }
    if (-not $found) { $lines.Add($line) }
    return (($lines.ToArray() -join "`r`n") + "`r`n")
}

# ------------------------------------------------------------------ main
Write-StepLine 'Checking this PC'
if (-not [Environment]::Is64BitOperatingSystem) { Write-FailLine 'RTX Remix needs 64-bit Windows.'; exit 1 }
$drv = Get-NvidiaDriverVersion
if (-not $drv) { Write-WarnLine 'No NVIDIA driver found. RTX Remix 1.6.1 needs an NVIDIA RTX GPU with driver 616.92 or newer.' }
elseif ($drv -lt $script:MinDriver) { Write-WarnLine "NVIDIA driver $drv is older than 616.92, the minimum for RTX Remix 1.6.1. Update it before playing." }
else { Write-OkLine "NVIDIA driver $drv (1.6.1 needs 616.92 or newer)" }

$GameDir = Resolve-GameDirOrExit $GameDir
Assert-GameNotRunning $GameDir
$man = Import-UpgradeManifests

Write-StepLine 'Checking the installed files'
$state = Get-UpgradeState $GameDir $man
Write-StateReport $state
$p = Get-InstallPlan $state $man

if ($p.Conflicts.Count) {
    Write-StepLine 'Files with unexpected content'
    foreach ($c in $p.Conflicts) { Write-WarnLine "$($c.Rel)  - $($c.Why)" }
    if (-not $Force) {
        Write-FailLine 'Nothing was changed.'
        Write-InfoLine 'Usual fix: Steam > Portal: Prelude RTX > Properties > Installed Files > Verify integrity of game files,'
        Write-InfoLine 'then run Install.bat again. Or run "Install.bat -Force" to move these files into'
        Write-InfoLine '_RemixUpgrade_quarantine\ (nothing is deleted) and continue.'
        exit 2
    }
    if ($DryRun) {
        Write-InfoLine '-Force would move these into _RemixUpgrade_quarantine\ first.'
    } else {
        $q = Join-Rel $GameDir ('_RemixUpgrade_quarantine\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        foreach ($c in $p.Conflicts) {
            Move-FileSafe (Join-Rel $GameDir $c.Rel) (Join-Path $q $c.Rel)
            Write-OkLine "Quarantined $($c.Rel)"
        }
        $state = Get-UpgradeState $GameDir $man
        $p = Get-InstallPlan $state $man
        if ($p.Conflicts.Count) { Write-FailLine 'Unexpected files remain after quarantine; stopping.'; exit 1 }
    }
}

$plan = $p.Plan
$extracts = @($plan | Where-Object { $_.Op -eq 'Extract' })
Write-StepLine 'Plan'
if ($plan.Count -eq 0) {
    Write-OkLine 'RTX Remix 1.6.1 is already installed and every file matches. Nothing to do.'
} else {
    foreach ($op in 'Move', 'Copy', 'Delete', 'MoveJunk', 'Extract', 'Write') {
        $n = @($plan | Where-Object { $_.Op -eq $op }).Count
        if ($n) { Write-InfoLine ('{0,-8} {1,4} file(s)' -f $op, $n) }
    }
    if ($DryRun) {
        foreach ($a in $plan) { Write-InfoLine ('{0,-8} {1}{2}' -f $a.Op, $a.Rel, $(if ($a.Rel2 -and $a.Op -ne 'Extract') { '  ->  ' + $a.Rel2 } else { '' })) }
    }
}
if ($DryRun) { Write-StepLine 'Dry run: nothing was changed.'; exit 0 }

if ($plan.Count) {
    $zip = $null
    if ($extracts.Count) {
        Write-StepLine "NVIDIA's RTX Remix 1.6.1 package"
        $pkg = Find-Package $PackagePath -NoDownload:$NoDownload
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($pkg)
    }
    try {
        Write-StepLine 'Installing'
        foreach ($a in $plan) {
            $abs = Join-Rel $GameDir $a.Rel
            switch ($a.Op) {
                'Move'     { Move-FileSafe $abs (Join-Rel $GameDir $a.Rel2) }
                'Copy'     { Copy-FileSafe $abs (Join-Rel $GameDir $a.Rel2) }
                'Delete'   { [System.IO.File]::Delete($abs) }
                'MoveJunk' { Move-FileSafe $abs (Get-FreeName (Join-Rel $GameDir $a.Rel2)) }
                'Extract' {
                    $entry = $zip.GetEntry($a.Rel2)
                    if (-not $entry) { throw "NVIDIA's package has no entry '$($a.Rel2)'." }
                    $tmp = $abs + $script:TmpSuffix
                    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($abs))
                    if ([System.IO.File]::Exists($tmp)) { [System.IO.File]::Delete($tmp) }
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $tmp, $true)
                    if ((Get-Sha256 $tmp) -ne $man.Patch[$a.Rel].SHA256) { [System.IO.File]::Delete($tmp); throw "Extracted $($a.Rel) does not match the manifest." }
                    Move-FileSafe $tmp $abs
                }
                'Write' {
                    $tmp = $abs + $script:TmpSuffix
                    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($abs))
                    [System.IO.File]::WriteAllBytes($tmp, [System.Text.Encoding]::ASCII.GetBytes($script:BridgeConfText))
                    if ((Get-Sha256 $tmp) -ne $man.Patch[$a.Rel].SHA256) { [System.IO.File]::Delete($tmp); throw "bridge.conf does not match the manifest." }
                    Move-FileSafe $tmp $abs
                }
            }
        }
        Write-OkLine ("Done: {0} file operations" -f $plan.Count)
    } finally {
        if ($zip) { $zip.Dispose() }
    }
    Remove-EmptyDirs (Join-Rel $GameDir $script:TrexRel)
}

if ($EnableNeuralRendering) {
    # Sets the documented DLSS 5 switch in user.conf (the layer the in-game menu saves to) and keeps every other line.
    # A changed file is kept as user.conf.before-<time>; a re-run changes nothing.
    Write-StepLine 'DLSS 5 (DLSS 3D-Guided Neural Rendering)'
    $uc = Join-Rel $GameDir 'user.conf'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $old = $null
    if ([System.IO.File]::Exists($uc)) { $old = [System.IO.File]::ReadAllBytes($uc) }
    $text = ''
    if ($null -ne $old) { $text = $utf8.GetString($old) }
    $new = $utf8.GetBytes((Set-ConfText $text 'rtx.dlssNeuralRendering.enable' 'True'))
    if (($null -ne $old) -and ([System.Convert]::ToBase64String($old) -eq [System.Convert]::ToBase64String($new))) {
        Write-OkLine 'user.conf already has rtx.dlssNeuralRendering.enable = True'
    } else {
        if ($null -ne $old) {
            $keep = Get-FreeName ($uc + '.before-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
            Move-FileSafe $uc $keep
            Write-InfoLine "previous user.conf kept as $([System.IO.Path]::GetFileName($keep))"
        }
        [System.IO.File]::WriteAllBytes($uc, $new)
        Write-OkLine 'user.conf: rtx.dlssNeuralRendering.enable = True'
    }
}

Write-StepLine 'Verifying'
$state = Get-UpgradeState $GameDir $man
Write-StateReport $state
$bakOk = @($state.BackupStatus.Values | Where-Object { $_ -eq 'ok' }).Count
$leftStock = @($man.Stock.Keys | Where-Object { -not $man.Patch.Contains($_) -and $state.StockStatus[$_] -ne 'missing' })
if (-not $state.IsPatched -or $leftStock.Count) {
    Write-FailLine 'The upgrade is not complete. See the lines above; nothing that was moved has been lost (check the .bak files).'
    exit 1
}
Write-OkLine 'All 196 RTX Remix 1.6.1 files match the manifest.'
if ($bakOk -eq 65) { Write-OkLine 'All 65 stock 0.2.1 files are kept as backups (Uninstall.bat can restore them).' }
else { Write-WarnLine "Only $bakOk of 65 stock files have a backup. To roll back later, use Steam's Verify integrity of game files." }

$rec = @(
    'Portal: Prelude RTX - RTX Remix 1.6.1 upgrade'
    ('Installed by {0} v{1} on {2}' -f $script:UpgradeName, $script:UpgradeVersion, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    ''
    'Runtime:  NVIDIA RTX Remix 1.6.1, for-x86-games release (32-bit bridge in bin\, 64-bit runtime in bin\.trex\)'
    ('Package:  {0}' -f $script:PackageName)
    ('          SHA-256 {0}' -f $script:PackageSha256)
    'Files:    196 verified (195 from the package + Prelude''s stock bin\.trex\bridge.conf)'
    ('Backups:  bin\d3d9.dll{0}, bin\NvRemixBridge32.dll{0}, {1}\  ({2} of 65 stock files)' -f $script:BakSuffix, $script:TrexBakRel, $bakOk)
    'Not changed: rtx.conf, dxvk.conf, user.conf, bin\dxvk_d3d9.dll, rtx-remix\mods (the Prelude asset mod)'
    ''
    'Roll back: run Uninstall.bat from the upgrade package.'
    'After Steam "Verify integrity of game files" or a game update: run Install.bat again.'
    'DLSS 5 (DLSS 3D-Guided Neural Rendering) is off by default: rtx.dlssNeuralRendering.enable = True turns it on.'
)
try { [System.IO.File]::WriteAllLines((Join-Rel $GameDir $script:RecordName), [string[]]$rec) } catch { Write-WarnLine "Could not write $($script:RecordName): $_" }
Write-StepLine 'RTX Remix 1.6.1 is installed. Launch the game from Steam as usual.'
exit 0

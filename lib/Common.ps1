# lib\Common.ps1 - shared code for Install.ps1, Uninstall.ps1 and Verify.ps1
# Portal: Prelude RTX -> RTX Remix 1.6.1 upgrade. Windows PowerShell 5.1 or later.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts in the ANSI code page.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:UpgradeName    = 'PortalPreludeRTX-RemixUpgrade'
$script:UpgradeVersion = '1.0.0'
$script:AppId          = '2410180'
$script:PackageName    = 'rtx-remix-for-x86-games-release-remix-1.6.1.zip'
$script:PackageUrl     = 'https://github.com/NVIDIAGameWorks/rtx-remix/releases/download/remix-1.6.1/rtx-remix-for-x86-games-release-remix-1.6.1.zip'
$script:PackageSize    = [int64]863551854
$script:PackageSha256  = '18237BE32A619634051E7F9E971625756557B72ACEB38B18659FFF7AD726A571'
$script:BakSuffix      = '.prelude-0.2.1.bak'
$script:TrexRel        = 'bin\.trex'
$script:TrexBakRel     = 'bin\.trex.prelude-0.2.1.bak'
$script:MinDriver      = [version]'616.92'
$script:RecordName     = '_RemixUpgrade_installed.txt'
$script:TmpSuffix      = '.remixupgrade-tmp'
$script:RuntimeJunk    = @('*.log', '*.dmp', '*.dxvk-cache')
$script:Root           = Split-Path -Parent $PSScriptRoot
$script:LogFile        = $null
$script:HashBuffer     = New-Object byte[] (4MB)

# bin\.trex\bridge.conf is not part of NVIDIA's package. The upgrade keeps Prelude's own stock file
# (58 bytes, CRLF). It is written from here so the result never depends on what is on disk.
$script:BridgeConfText = "# lowest possible latency`r`npresentSemaphoreMaxFrames = 1`r`n"

# ------------------------------------------------------------------ output
function Write-Line([string]$Text, [string]$Color = 'Gray') {
    Write-Host $Text -ForegroundColor $Color
    if ($script:LogFile) { try { Add-Content -LiteralPath $script:LogFile -Value $Text -Encoding UTF8 } catch { } }
}
function Write-StepLine([string]$Text) { Write-Line ''; Write-Line "== $Text" 'Cyan' }
function Write-OkLine([string]$Text)   { Write-Line "   OK    $Text" 'Green' }
function Write-InfoLine([string]$Text) { Write-Line "         $Text" 'Gray' }
function Write-WarnLine([string]$Text) { Write-Line "   WARN  $Text" 'Yellow' }
function Write-FailLine([string]$Text) { Write-Line "   FAIL  $Text" 'Red' }

function Start-RunLog([string]$Kind) {
    try {
        $dir = Join-Path $script:Root 'logs'
        [void][System.IO.Directory]::CreateDirectory($dir)
        $script:LogFile = Join-Path $dir ('{0}-{1}.log' -f $Kind, (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Write-Line ("{0} v{1} - {2} - {3}" -f $script:UpgradeName, $script:UpgradeVersion, $Kind, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) 'White'
    } catch { $script:LogFile = $null }
}

# ------------------------------------------------------------------ hashing (CNG: hardware SHA, fast)
function Get-FileDigest([string]$Path, [switch]$WithSha1) {
    $h256 = New-Object System.Security.Cryptography.SHA256Cng
    $h1 = $null
    if ($WithSha1) { $h1 = New-Object System.Security.Cryptography.SHA1Cng }
    $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read, 65536)
    try {
        $buf = $script:HashBuffer
        while (($n = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
            [void]$h256.TransformBlock($buf, 0, $n, $null, 0)
            if ($h1) { [void]$h1.TransformBlock($buf, 0, $n, $null, 0) }
        }
        [void]$h256.TransformFinalBlock($buf, 0, 0)
        $sha1 = $null
        if ($h1) { [void]$h1.TransformFinalBlock($buf, 0, 0); $sha1 = [System.BitConverter]::ToString($h1.Hash) -replace '-', '' }
        return [pscustomobject]@{ SHA256 = ([System.BitConverter]::ToString($h256.Hash) -replace '-', ''); SHA1 = $sha1; Size = $fs.Length }
    } finally {
        $fs.Dispose(); $h256.Dispose(); if ($h1) { $h1.Dispose() }
    }
}
function Get-Sha256([string]$Path) { return (Get-FileDigest -Path $Path).SHA256 }

# ------------------------------------------------------------------ paths
function Join-Rel([string]$GameDir, [string]$Rel) { return [System.IO.Path]::Combine($GameDir, $Rel) }

function Get-BackupRel([string]$Rel) {
    $prefix = $script:TrexRel + '\'
    if ($Rel.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $script:TrexBakRel + '\' + $Rel.Substring($prefix.Length)
    }
    return $Rel + $script:BakSuffix
}

function Get-RelFiles([string]$GameDir, [string]$RelDir) {
    # Every file under a folder, as paths relative to the game folder. Empty list if the folder is missing.
    $abs = Join-Rel $GameDir $RelDir
    $out = New-Object System.Collections.Generic.List[string]
    if (-not [System.IO.Directory]::Exists($abs)) { return ,$out }
    foreach ($f in [System.IO.Directory]::GetFiles($abs, '*', [System.IO.SearchOption]::AllDirectories)) {
        $out.Add($RelDir + $f.Substring($abs.Length))
    }
    return ,$out
}

function Test-IsJunk([string]$Rel) {
    $name = [System.IO.Path]::GetFileName($Rel)
    foreach ($p in $script:RuntimeJunk) { if ($name -like $p) { return $true } }
    return $false
}

function Remove-EmptyDirs([string]$AbsDir, [switch]$IncludeRoot) {
    # Deletes empty folders bottom-up. Never touches a folder that still holds a file.
    if (-not [System.IO.Directory]::Exists($AbsDir)) { return }
    $dirs = @([System.IO.Directory]::GetDirectories($AbsDir, '*', [System.IO.SearchOption]::AllDirectories) | Sort-Object -Property Length -Descending)
    foreach ($d in $dirs) {
        if (@([System.IO.Directory]::GetFileSystemEntries($d)).Count -eq 0) { [System.IO.Directory]::Delete($d) }
    }
    if ($IncludeRoot -and @([System.IO.Directory]::GetFileSystemEntries($AbsDir)).Count -eq 0) { [System.IO.Directory]::Delete($AbsDir) }
}

# ------------------------------------------------------------------ finding the game
function Test-PreludeDir([string]$Dir) {
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    foreach ($m in 'hl2.exe', 'bin', 'portal prelude rtx\gameinfo.txt') {
        if (-not (Test-Path -LiteralPath (Join-Path $Dir $m))) { return $false }
    }
    return $true
}

function Get-SteamLibraries {
    $libs = New-Object System.Collections.Generic.List[string]
    $steam = $null
    foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $p = Get-ItemProperty -Path $k -ErrorAction Stop
            foreach ($name in 'SteamPath', 'InstallPath') {
                if ($p.PSObject.Properties[$name] -and $p.$name) { $steam = [string]$p.$name; break }
            }
        } catch { }
        if ($steam) { break }
    }
    if (-not $steam) { return ,$libs }
    $steam = $steam -replace '/', '\'
    $libs.Add($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
            $libs.Add(($m.Groups[1].Value -replace '\\\\', '\'))
        }
    }
    return ,$libs
}

function Find-GameDir([string]$Hint) {
    if ($Hint) {
        $Hint = $Hint.Trim().Trim('"').TrimEnd('\')
        if (Test-PreludeDir $Hint) { return (Resolve-Path -LiteralPath $Hint).ProviderPath }
        throw "'$Hint' does not look like a Portal: Prelude RTX folder (expected hl2.exe, bin\ and 'portal prelude rtx\gameinfo.txt')."
    }
    foreach ($lib in (Get-SteamLibraries)) {
        $acf = Join-Path $lib "steamapps\appmanifest_$($script:AppId).acf"
        if (-not (Test-Path -LiteralPath $acf)) { continue }
        $m = [regex]::Match((Get-Content -LiteralPath $acf -Raw), '"installdir"\s+"([^"]+)"')
        if ($m.Success) {
            $d = Join-Path $lib ('steamapps\common\' + $m.Groups[1].Value)
            if (Test-PreludeDir $d) { return $d }
        }
    }
    $up = Split-Path -Parent $script:Root     # this package extracted inside the game folder
    if (Test-PreludeDir $up) { return $up }
    return $null
}

function Resolve-GameDirOrExit([string]$Hint) {
    $dir = Find-GameDir $Hint
    if (-not $dir) {
        Write-FailLine 'Could not find Portal: Prelude RTX (Steam app 2410180).'
        Write-InfoLine 'Run this again with the game folder, for example:'
        Write-InfoLine '  Install.bat -GameDir "D:\SteamLibrary\steamapps\common\Portal Prelude RTX"'
        exit 1
    }
    Write-OkLine "Game folder: $dir"
    return $dir
}

function Assert-GameNotRunning([string]$GameDir) {
    $hits = @()
    foreach ($p in @(Get-Process -Name 'hl2', 'NvRemixBridge', 'NvRemixLauncher32' -ErrorAction SilentlyContinue)) {
        $path = $null
        try { $path = $p.Path } catch { }
        if (-not $path -or $path.StartsWith($GameDir, [System.StringComparison]::OrdinalIgnoreCase)) { $hits += $p }
    }
    if ($hits.Count) {
        Write-FailLine ('The game or its Remix bridge is running (' + (($hits | ForEach-Object { $_.ProcessName + '.exe' }) -join ', ') + '). Quit it first.')
        exit 1
    }
}

function Get-NvidiaDriverVersion {
    try {
        $vc = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
        if (-not $vc) { return $null }
        $digits = ($vc.DriverVersion -replace '\.', '')
        if ($digits.Length -lt 5) { return $null }
        $last5 = $digits.Substring($digits.Length - 5)
        return [version]('{0}.{1}' -f [int]$last5.Substring(0, 3), $last5.Substring(3, 2))
    } catch { return $null }
}

# ------------------------------------------------------------------ manifests and state
function Import-UpgradeManifests {
    $patch = [ordered]@{}
    foreach ($r in (Import-Csv -LiteralPath (Join-Path $script:Root 'manifest\patch-files.csv'))) { $patch[$r.Target] = $r }
    $stock = [ordered]@{}
    foreach ($r in (Import-Csv -LiteralPath (Join-Path $script:Root 'manifest\stock-files.csv'))) { $stock[$r.Path] = $r }
    if ($patch.Count -ne 196 -or $stock.Count -ne 65) { throw "Manifest files are incomplete (patch $($patch.Count)/196, stock $($stock.Count)/65)." }
    return [pscustomobject]@{ Patch = $patch; Stock = $stock }
}

function Get-UpgradeState([string]$GameDir, $Manifests) {
    # Hashes every file the upgrade owns, replaces or backs up, and classifies it.
    #   PatchStatus[target] : ok | missing | other          (ok = NVIDIA 1.6.1 bytes in place)
    #   StockStatus[path]   : ok | patch | missing | other  (ok = stock 0.2.1 bytes in place)
    #   BackupStatus[path]  : ok | missing | other          (backup copy of the stock file)
    $patch = $Manifests.Patch; $stock = $Manifests.Stock
    $hash = @{}
    $rels = New-Object System.Collections.Generic.List[string]
    foreach ($k in $patch.Keys) { $rels.Add($k) }
    foreach ($k in $stock.Keys) { $rels.Add($k); $rels.Add((Get-BackupRel $k)) }
    $trexFiles = Get-RelFiles $GameDir $script:TrexRel
    $bakFiles = Get-RelFiles $GameDir $script:TrexBakRel
    foreach ($r in $trexFiles) { $rels.Add($r) }
    foreach ($r in $bakFiles) { $rels.Add($r) }
    foreach ($r in $rels) {
        if ($hash.ContainsKey($r)) { continue }
        $abs = Join-Rel $GameDir $r
        if ([System.IO.File]::Exists($abs)) { $hash[$r] = Get-Sha256 $abs } else { $hash[$r] = $null }
    }
    $ps = [ordered]@{}; $ss = [ordered]@{}; $bs = [ordered]@{}
    foreach ($t in $patch.Keys) {
        $h = $hash[$t]
        $ps[$t] = if ($null -eq $h) { 'missing' } elseif ($h -eq $patch[$t].SHA256) { 'ok' } else { 'other' }
    }
    foreach ($s in $stock.Keys) {
        $h = $hash[$s]
        $ss[$s] = if ($null -eq $h) { 'missing' } elseif ($h -eq $stock[$s].SHA256) { 'ok' } elseif ($patch.Contains($s) -and $h -eq $patch[$s].SHA256) { 'patch' } else { 'other' }
        $b = $hash[(Get-BackupRel $s)]
        $bs[$s] = if ($null -eq $b) { 'missing' } elseif ($b -eq $stock[$s].SHA256) { 'ok' } else { 'other' }
    }
    $foreign = New-Object System.Collections.Generic.List[string]    # in bin\.trex, neither stock nor patch
    foreach ($r in $trexFiles) { if (-not $patch.Contains($r) -and -not $stock.Contains($r)) { $foreign.Add($r) } }
    $bakStockRels = @{}
    foreach ($s in $stock.Keys) { $bakStockRels[(Get-BackupRel $s)] = $true }
    $bakExtra = New-Object System.Collections.Generic.List[string]   # in the backup folder, not a stock backup
    foreach ($r in $bakFiles) { if (-not $bakStockRels.ContainsKey($r)) { $bakExtra.Add($r) } }

    $patchOnly = @($patch.Keys | Where-Object { -not $stock.Contains($_) })
    $isPatched = @($ps.Values | Where-Object { $_ -ne 'ok' }).Count -eq 0
    $backupsComplete = @($bs.Values | Where-Object { $_ -ne 'ok' }).Count -eq 0
    $isStock = (@($ss.Values | Where-Object { $_ -ne 'ok' }).Count -eq 0) -and (@($patchOnly | Where-Object { $ps[$_] -ne 'missing' }).Count -eq 0)
    $summary = if ($isPatched) { 'PATCHED' } elseif ($isStock) { 'STOCK' } else { 'MIXED' }
    return [pscustomobject]@{
        GameDir = $GameDir; Hash = $hash; PatchStatus = $ps; StockStatus = $ss; BackupStatus = $bs
        Foreign = $foreign; BackupExtra = $bakExtra; PatchOnly = $patchOnly
        IsPatched = $isPatched; IsStock = $isStock; BackupsComplete = $backupsComplete; Summary = $summary
    }
}

function Get-StatusCounts($Table) {
    $c = [ordered]@{}
    foreach ($v in $Table.Values) { if ($c.Contains($v)) { $c[$v]++ } else { $c[$v] = 1 } }
    return (($c.Keys | ForEach-Object { "$_ $($c[$_])" }) -join ', ')
}

function Write-StateReport($State) {
    Write-InfoLine ("Remix 1.6.1 files (196):    " + (Get-StatusCounts $State.PatchStatus))
    Write-InfoLine ("Stock 0.2.1 files (65):     " + (Get-StatusCounts $State.StockStatus))
    Write-InfoLine ("0.2.1 backup copies (65):   " + (Get-StatusCounts $State.BackupStatus))
    if ($State.Foreign.Count) { Write-InfoLine ("Other files in bin\.trex:    " + $State.Foreign.Count) }
}

# ------------------------------------------------------------------ file operations (absolute paths, no wildcards)
function Move-FileSafe([string]$From, [string]$To) {
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($To))
    [System.IO.File]::Move($From, $To)    # throws if $To exists: nothing is ever overwritten here
}
function Copy-FileSafe([string]$From, [string]$To) {
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($To))
    [System.IO.File]::Copy($From, $To, $false)
}
function Get-FreeName([string]$Abs) {
    if (-not [System.IO.File]::Exists($Abs)) { return $Abs }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $i = 0
    do { $i++; $cand = '{0}.{1}-{2}' -f $Abs, $stamp, $i } while ([System.IO.File]::Exists($cand))
    return $cand
}

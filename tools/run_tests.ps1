<#
.SYNOPSIS
    Maintainer test run for Install/Uninstall/Verify (T1-T12, plus an optional real download).
    Only ever writes inside -WorkDir. -Reference and -Template are read, never changed.

.PARAMETER Reference   A good upgraded install to compare with (read-only), e.g. a game folder after a known-good upgrade.
.PARAMETER Template    The folder that contains a stock stand-in "Portal Prelude RTX" folder, made with:
                       python -I tools\test_tree.py make-stock --live <upgraded install> --out <Template>\Portal Prelude RTX --steam-json steam.json
.PARAMETER Package     NVIDIA's rtx-remix-for-x86-games-release-remix-1.6.1.zip
.PARAMETER WorkDir     An empty folder for the test copies (about 1 GB per test).
.PARAMETER BundleZip   A release bundle zip: also runs T12 (the bundle through Install.bat, files marked as downloaded).
.PARAMETER DownloadTest  With -BundleZip: also install once with no package available, so Install.bat downloads it from NVIDIA (824 MiB).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Reference,
    [Parameter(Mandatory = $true)][string]$Template,
    [Parameter(Mandatory = $true)][string]$Package,
    [Parameter(Mandatory = $true)][string]$WorkDir,
    [string]$BundleZip,
    [switch]$DownloadTest
)

$Repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $Repo 'lib\Common.ps1')
$ErrorActionPreference = 'Stop'
$env:REMIXUPGRADE_NOPAUSE = '1'
$Game = 'Portal Prelude RTX'
$Stock = Join-Path $Template $Game
if (-not (Test-PreludeDir $Stock)) { throw "Not a stock stand-in: $Stock" }
if (-not (Test-PreludeDir $Reference)) { throw "Not a game folder: $Reference" }
[void][System.IO.Directory]::CreateDirectory($WorkDir)
$script:Fails = 0
$script:Results = New-Object System.Collections.Generic.List[string]

function Get-TreeMap([string]$Dir) {
    $m = @{}
    if (-not [System.IO.Directory]::Exists($Dir)) { return $m }
    foreach ($f in [System.IO.Directory]::GetFiles($Dir, '*', [System.IO.SearchOption]::AllDirectories)) {
        $m[$f.Substring($Dir.Length).TrimStart('\').ToLowerInvariant()] = Get-Sha256 $f
    }
    return $m
}
function Compare-Trees([string]$A, [string]$B) {
    $ma = Get-TreeMap $A; $mb = Get-TreeMap $B
    $diff = New-Object System.Collections.Generic.List[string]
    foreach ($k in $ma.Keys) { if (-not $mb.ContainsKey($k)) { $diff.Add("only in reference: $k") } elseif ($ma[$k] -ne $mb[$k]) { $diff.Add("different: $k") } }
    foreach ($k in $mb.Keys) { if (-not $ma.ContainsKey($k)) { $diff.Add("only in test copy: $k") } }
    return [pscustomobject]@{ Count = $ma.Count; Diff = $diff }
}
function Get-TreeHash([string]$Dir) {
    $m = Get-TreeMap $Dir
    $text = ($m.Keys | Sort-Object | ForEach-Object { $_ + '=' + $m[$_] }) -join ';'
    $sha = New-Object System.Security.Cryptography.SHA256Cng
    try { return [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))) } finally { $sha.Dispose() }
}
function New-StockCopy([string]$Name) {
    $dst = Join-Path $WorkDir $Name
    if (Test-Path -LiteralPath $dst) { throw "Test folder exists already: $dst (use an empty -WorkDir)" }
    Copy-Item -LiteralPath $Template -Destination $dst -Recurse
    return (Join-Path $dst $Game)
}
function Invoke-Upgrade([string]$Script, [string[]]$ArgList, [string]$From = $Repo) {
    $ErrorActionPreference = 'Continue'   # Windows PowerShell 5.1 turns native stderr into errors; never let that stop a test
    $out = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $From $Script) @ArgList 2>&1 | Out-String -Width 220
    return [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
}
function Invoke-Bat([string]$Bat, [string[]]$ArgList) {
    $ErrorActionPreference = 'Continue'   # e.g. curl's progress meter goes to stderr during the download test
    $out = & $Bat @ArgList 2>&1 | Out-String -Width 220
    return [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
}
function Write-StockOver([string]$G) {   # what Steam's "Verify integrity" does: stock files back, extra files left
    foreach ($row in (Import-Csv -LiteralPath (Join-Path $Repo 'manifest\stock-files.csv'))) {
        $dst = Join-Path $G $row.Path
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($dst))
        Copy-Item -LiteralPath (Join-Path $Stock $row.Path) -Destination $dst -Force
    }
}
function Test-Result([string]$Id, [bool]$Ok, [string]$Text) {
    $line = ('{0} {1,-4} {2}' -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Id, $Text)
    if (-not $Ok) { $script:Fails++ }
    $script:Results.Add($line)
    Write-Host $line -ForegroundColor $(if ($Ok) { 'Green' } else { 'Red' })
}
function Test-SameAsReference([string]$Id, [string]$G, [string]$What) {
    $c = Compare-Trees (Join-Path $Reference 'bin') (Join-Path $G 'bin')
    Test-Result $Id ($c.Diff.Count -eq 0) ("$What - bin\ vs reference: $($c.Count) files, $($c.Diff.Count) differences " + (($c.Diff | Select-Object -First 3) -join '; '))
}
$Pkg = @('-PackagePath', $Package)

# T1 dry run
$g = New-StockCopy 't01'; $h = Get-TreeHash $g
$r = Invoke-Upgrade 'Install.ps1' (@('-GameDir', $g, '-DryRun') + $Pkg)
Test-Result 'T1' (($r.Code -eq 0) -and ((Get-TreeHash $g) -eq $h)) "dry run on stock: exit $($r.Code), folder unchanged"

# T2 install, T3 re-run, T4 verify, T5 Steam verify simulated + repair, T6 uninstall
$g = New-StockCopy 't02'
$r = Invoke-Upgrade 'Install.ps1' (@('-GameDir', $g) + $Pkg); Test-Result 'T2' ($r.Code -eq 0) "install on stock: exit $($r.Code)"
Test-SameAsReference 'T2' $g 'after install'
$r = Invoke-Upgrade 'Install.ps1' @('-GameDir', $g, '-NoDownload'); Test-Result 'T3' (($r.Code -eq 0) -and ($r.Out -match 'Nothing to do')) "re-run with no package available: exit $($r.Code)"
$r = Invoke-Upgrade 'Verify.ps1' @('-GameDir', $g); Test-Result 'T4' (($r.Code -eq 0) -and ($r.Out -match 'PATCHED')) "verify: exit $($r.Code)"
Write-StockOver $g
$r = Invoke-Upgrade 'Verify.ps1' @('-GameDir', $g); Test-Result 'T5' (($r.Code -eq 1) -and ($r.Out -match 'MIXED')) "after simulated Steam verify, Verify says MIXED: exit $($r.Code)"
$r = Invoke-Upgrade 'Install.ps1' (@('-GameDir', $g) + $Pkg); Test-Result 'T5' ($r.Code -eq 0) "repair install: exit $($r.Code)"
Test-SameAsReference 'T5' $g 'after repair'
$r = Invoke-Upgrade 'Uninstall.ps1' @('-GameDir', $g); Test-Result 'T6' ($r.Code -eq 0) "uninstall: exit $($r.Code)"
$c = Compare-Trees $Stock $g; Test-Result 'T6' ($c.Diff.Count -eq 0) "whole folder vs stock stand-in: $($c.Count) files, $($c.Diff.Count) differences"
$r = Invoke-Upgrade 'Uninstall.ps1' @('-GameDir', $g); Test-Result 'T6' (($r.Code -eq 0) -and ($r.Out -match 'Nothing to do')) "uninstall again: exit $($r.Code)"

# T7 unknown content
$g = New-StockCopy 't07'
[System.IO.File]::AppendAllText((Join-Path $g 'bin\.trex\d3d9.dll'), 'x'); $h = Get-TreeHash $g
$r = Invoke-Upgrade 'Install.ps1' (@('-GameDir', $g) + $Pkg)
Test-Result 'T7' (($r.Code -eq 2) -and ((Get-TreeHash $g) -eq $h)) "modified stock file: install refused (exit $($r.Code)), folder unchanged"
$r = Invoke-Upgrade 'Install.ps1' (@('-GameDir', $g, '-Force') + $Pkg)
$q = @(Get-ChildItem -LiteralPath (Join-Path $g '_RemixUpgrade_quarantine') -Recurse -File -ErrorAction SilentlyContinue)
$c = Compare-Trees (Join-Path $Reference 'bin') (Join-Path $g 'bin')
Test-Result 'T7' (($r.Code -eq 0) -and ($q.Count -eq 1) -and ($c.Diff.Count -eq 1) -and ($c.Diff[0] -like '*.trex.prelude-0.2.1.bak\d3d9.dll')) "-Force: exit $($r.Code), $($q.Count) file quarantined, only that file's backup missing"

# T8 DLSS 5 switch, twice, with an existing user.conf
$g = New-StockCopy 't08'
[System.IO.File]::WriteAllText((Join-Path $g 'user.conf'), "rtx.qualityDLSS = 3`r`n")
$r = Invoke-Upgrade 'Install.ps1' (@('-GameDir', $g, '-EnableNeuralRendering') + $Pkg)
$uc = [System.IO.File]::ReadAllText((Join-Path $g 'user.conf'))
$kept = @(Get-ChildItem -LiteralPath $g -Filter 'user.conf.before-*' -File)
Test-Result 'T8' (($r.Code -eq 0) -and ($uc -eq "rtx.qualityDLSS = 3`r`nrtx.dlssNeuralRendering.enable = True`r`n") -and ($kept.Count -eq 1)) "-EnableNeuralRendering: exit $($r.Code), other line kept, old file kept"
$r = Invoke-Upgrade 'Install.ps1' (@('-GameDir', $g, '-EnableNeuralRendering') + $Pkg)
$kept2 = @(Get-ChildItem -LiteralPath $g -Filter 'user.conf.before-*' -File)
Test-Result 'T8' (($r.Code -eq 0) -and ($r.Out -match 'already has') -and ($kept2.Count -eq 1)) "second run changes nothing: exit $($r.Code)"

# T9 interrupted install
$g = New-StockCopy 't09'
$null = Invoke-Upgrade 'Install.ps1' (@('-GameDir', $g) + $Pkg)
Get-ChildItem -LiteralPath (Join-Path $g 'bin\.trex') -File | Select-Object -First 30 | Remove-Item
Get-ChildItem -LiteralPath (Join-Path $g 'bin\.trex\usd') -Recurse -File | Select-Object -First 10 | Remove-Item
[System.IO.File]::WriteAllText((Join-Path $g 'bin\.trex\nvngx_dlssnr.dll.remixupgrade-tmp'), 'partial')
Move-Item -LiteralPath (Join-Path $g 'bin\.trex.prelude-0.2.1.bak\sl.common.dll') -Destination (Join-Path $g 'bin\.trex\sl.common.dll')
$r = Invoke-Upgrade 'Install.ps1' (@('-GameDir', $g) + $Pkg); Test-Result 'T9' ($r.Code -eq 0) "resume after an interruption: exit $($r.Code)"
Test-SameAsReference 'T9' $g 'after resume'

# T10 uninstall without backups
$g = New-StockCopy 't10'
$null = Invoke-Upgrade 'Install.ps1' (@('-GameDir', $g) + $Pkg)
Remove-Item -LiteralPath (Join-Path $g 'bin\.trex.prelude-0.2.1.bak') -Recurse
Remove-Item -LiteralPath (Join-Path $g 'bin\d3d9.dll.prelude-0.2.1.bak'), (Join-Path $g 'bin\NvRemixBridge32.dll.prelude-0.2.1.bak')
$h = Get-TreeHash $g
$r = Invoke-Upgrade 'Uninstall.ps1' @('-GameDir', $g)
Test-Result 'T10' (($r.Code -eq 2) -and ((Get-TreeHash $g) -eq $h)) "no backups: uninstall refused (exit $($r.Code)), folder unchanged"
Write-StockOver $g
$r = Invoke-Upgrade 'Uninstall.ps1' @('-GameDir', $g)
$c = Compare-Trees $Stock $g
$onlyLog = ($c.Diff.Count -eq 0) -or (($c.Diff.Count -eq 1) -and ($c.Diff[0] -like '*nvremixbridge.log'))
Test-Result 'T10' (($r.Code -eq 0) -and $onlyLog) "after simulated Steam verify: exit $($r.Code), stock except the old runtime log ($($c.Diff.Count) difference)"

# T12 the release bundle through Install.bat, files marked as downloaded from the Internet
if ($BundleZip) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $cases = New-Object System.Collections.Generic.List[object]
    $cases.Add(@{ Id = 'T12'; Dir = 't12-bundle'; WithZip = $true })
    if ($DownloadTest) { $cases.Add(@{ Id = 'TD'; Dir = 'td-bundle'; WithZip = $false }) }
    foreach ($case in $cases) {
        $dl = Join-Path $WorkDir $case.Dir
        [System.IO.Compression.ZipFile]::ExtractToDirectory($BundleZip, $dl)
        $bundleRoot = (Get-ChildItem -LiteralPath $dl -Directory | Select-Object -First 1).FullName
        if ($case.WithZip) { Copy-Item -LiteralPath $Package -Destination (Join-Path $dl $script:PackageName) }
        elseif (Test-Path -LiteralPath (Join-Path $env:USERPROFILE ('Downloads\' + $script:PackageName))) { Test-Result 'TD' $false 'skipped: the package is in Downloads, so it would not download'; continue }
        foreach ($f in Get-ChildItem -LiteralPath $dl -Recurse -File) { Set-Content -LiteralPath $f.FullName -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" }
        $g = New-StockCopy ($case.Id.ToLowerInvariant() + '-game')
        $res = Invoke-Bat (Join-Path $bundleRoot 'Install.bat') @('-GameDir', $g)
        $out = $res.Out; $code = $res.Code
        $how = if ($case.WithZip) { 'zip in the folder above' } else { 'no zip anywhere: download from NVIDIA' }
        Test-Result $case.Id (($code -eq 0) -and ($out -match $(if ($case.WithZip) { 'Checking .*remix-1\.6\.1\.zip' } else { 'Downloaded and verified' }))) "Install.bat from the bundle ($how): exit $code"
        Test-SameAsReference $case.Id $g 'bundle install'
    }
}

Write-Host ''
Write-Host ('{0} checks, {1} failed' -f $script:Results.Count, $script:Fails) -ForegroundColor $(if ($script:Fails) { 'Red' } else { 'Green' })
exit $script:Fails

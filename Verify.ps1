<#
.SYNOPSIS
    Read-only check of a Portal: Prelude RTX install against the upgrade manifests. Changes nothing.

.DESCRIPTION
    Default: hashes the 196 Remix 1.6.1 files, the 65 stock 0.2.1 files and their backups, and reports
    PATCHED, STOCK or MIXED.
    -Full: also hashes every file in the game folder (SHA-256 and SHA-1) and classifies each one against
    Steam's own stock file list for the build (manifest\steam-stock-*.csv), the patch and the backups.
    -CompareTo <csv>: -Full, then compares every file with an earlier -Full result (logs\full-*.csv).

.PARAMETER GameDir    The game folder, if it is not found automatically.
.PARAMETER Full       Hash and classify every file in the game folder.
.PARAMETER CompareTo  An earlier -Full CSV to compare with (implies -Full).
.PARAMETER OutCsv     Where to write the -Full results (default: logs\full-<time>.csv next to this script).
#>
[CmdletBinding()]
param(
    [string]$GameDir,
    [switch]$Full,
    [string]$CompareTo,
    [string]$OutCsv
)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
Start-RunLog 'verify'

$GameDir = Resolve-GameDirOrExit $GameDir
$man = Import-UpgradeManifests

Write-StepLine 'Upgrade files'
$state = Get-UpgradeState $GameDir $man
Write-StateReport $state
$rc = 0
switch ($state.Summary) {
    'PATCHED' {
        Write-OkLine 'PATCHED: RTX Remix 1.6.1 is installed and all 196 files match.'
        $bakOk = @($state.BackupStatus.Values | Where-Object { $_ -eq 'ok' }).Count
        if ($bakOk -eq 65) { Write-OkLine 'All 65 stock 0.2.1 backups are present and match Steam''s files.' }
        else { Write-WarnLine "$bakOk of 65 stock backups present. Roll-back of the rest needs Steam's Verify integrity." }
        $leftStock = @($man.Stock.Keys | Where-Object { -not $man.Patch.Contains($_) -and $state.StockStatus[$_] -ne 'missing' })
        if ($leftStock.Count) { Write-WarnLine "$($leftStock.Count) old 0.2.1 file(s) are back in place (e.g. $($leftStock[0])). Run Install.bat to tidy up."; $rc = 1 }
    }
    'STOCK' { Write-OkLine 'STOCK: the original Steam runtime (0.2.1-prelude) is installed. Run Install.bat to upgrade.' }
    default {
        Write-WarnLine 'MIXED: some files are stock 0.2.1, some are Remix 1.6.1 (typical after Steam''s Verify integrity or a game update).'
        Write-InfoLine 'Run Install.bat to finish the upgrade, or Uninstall.bat to go back to stock.'
        $rc = 1
    }
}
$odd = @($state.PatchStatus.Keys | Where-Object { $state.PatchStatus[$_] -eq 'other' -and -not $man.Stock.Contains($_) }) +
       @($state.StockStatus.Keys | Where-Object { $state.StockStatus[$_] -eq 'other' }) +
       @($state.BackupStatus.Keys | Where-Object { $state.BackupStatus[$_] -eq 'other' } | ForEach-Object { Get-BackupRel $_ }) +
       @($state.Foreign | Where-Object { -not (Test-IsJunk $_) })
foreach ($o in $odd) { Write-WarnLine "Unexpected content: $o" }
if ($odd.Count) { $rc = 1 }

if ($CompareTo) { $Full = $true }
if ($Full) {
    Write-StepLine 'Every file in the game folder'
    $steamCsv = @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'manifest') -Filter 'steam-stock-*.csv')
    if (-not $steamCsv.Count) { Write-FailLine 'manifest\steam-stock-*.csv is missing.'; exit 1 }
    $steam = @{}
    foreach ($r in (Import-Csv -LiteralPath $steamCsv[0].FullName -Encoding UTF8)) { $steam[$r.Path] = $r }
    Write-InfoLine "Steam stock list: $($steamCsv[0].Name) ($($steam.Count) files)"
    $files = [System.IO.Directory]::GetFiles($GameDir, '*', [System.IO.SearchOption]::AllDirectories)
    Write-InfoLine "Hashing $($files.Count) files ..."
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $rows = New-Object System.Collections.Generic.List[object]
    $bakPrefix = $script:TrexBakRel + '\'
    foreach ($f in $files) {
        $rel = $f.Substring($GameDir.Length).TrimStart('\')
        $d = Get-FileDigest -Path $f -WithSha1
        $s = $steam[$rel]
        $cls = $null
        if ($man.Patch.Contains($rel) -and $man.Patch[$rel].SHA256 -eq $d.SHA256) {
            $cls = if ($s -and $s.SHA1 -eq $d.SHA1) { 'patch (same bytes as stock)' } else { 'patch' }
        } elseif ($s -and $s.SHA1 -eq $d.SHA1) {
            $cls = 'stock'
        } elseif ($rel.EndsWith($script:BakSuffix, [System.StringComparison]::OrdinalIgnoreCase) -or $rel.StartsWith($bakPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $orig = if ($rel.StartsWith($bakPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { $script:TrexRel + '\' + $rel.Substring($bakPrefix.Length) } else { $rel.Substring(0, $rel.Length - $script:BakSuffix.Length) }
            $cls = if ($man.Stock.Contains($orig) -and $man.Stock[$orig].SHA256 -eq $d.SHA256) { 'backup of stock' } else { 'backup folder: other file' }
        } elseif ($rel -like '_RemixUpgrade_quarantine\*') { $cls = 'quarantine'
        } elseif ($rel -eq $script:RecordName) { $cls = 'record (installer)'
        } elseif ($s) { $cls = 'stock file changed by the game or user'
        } else { $cls = 'created by the game or user' }
        $rows.Add([pscustomobject]@{
            Path = $rel; Size = $d.Size; SHA256 = $d.SHA256; SHA1 = $d.SHA1
            ModifiedUtc = [System.IO.File]::GetLastWriteTimeUtc($f).ToString('yyyy-MM-dd HH:mm:ss'); Class = $cls })
    }
    $sw.Stop()
    $total = ($rows | Measure-Object -Property Size -Sum).Sum
    Write-OkLine ('{0} files, {1:N1} GB hashed in {2:N0} s' -f $rows.Count, ($total / 1GB), $sw.Elapsed.TotalSeconds)
    if (-not $OutCsv) { $OutCsv = Join-Path $script:Root ('logs\full-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.csv') }
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($OutCsv))
    $rows | Sort-Object -Property Path | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
    Write-InfoLine "Written: $OutCsv"
    foreach ($g in ($rows | Group-Object -Property Class | Sort-Object -Property Name)) { Write-InfoLine ('{0,7}  {1}' -f $g.Count, $g.Name) }
    $onDisk = @{}; foreach ($r in $rows) { $onDisk[$r.Path] = $true }
    $gone = @($steam.Keys | Where-Object { -not $onDisk.ContainsKey($_) })
    $moved = @($gone | Where-Object { $man.Stock.Contains($_) })
    $lost = @($gone | Where-Object { -not $man.Stock.Contains($_) })
    Write-InfoLine ('{0,7}  stock files not on disk because the upgrade moved them to backups' -f $moved.Count)
    if ($lost.Count) { foreach ($l in $lost) { Write-WarnLine "Stock file missing: $l" }; $rc = 1 }
    foreach ($r in ($rows | Where-Object { $_.Class -eq 'stock file changed by the game or user' })) { Write-InfoLine "changed vs Steam: $($r.Path)" }

    if ($CompareTo) {
        Write-StepLine "Compared with $([System.IO.Path]::GetFileName($CompareTo))"
        $cur = @{}; foreach ($r in $rows) { $cur[$r.Path] = $r }
        $snapRows = @(Import-Csv -LiteralPath $CompareTo -Encoding UTF8)
        $snapPaths = @{}
        $report = [ordered]@{}
        $mustMatch = @('patch', 'patch (same bytes as stock)', 'backup of stock', 'stock')
        foreach ($r in $snapRows) {
            $snapPaths[$r.Path] = $true
            if (-not $report.Contains($r.Class)) { $report[$r.Class] = [ordered]@{ same = 0; changed = 0; missing = 0; examples = (New-Object System.Collections.Generic.List[string]) } }
            $c = $cur[$r.Path]
            if (-not $c) { $report[$r.Class].missing++; $kind = 'missing' }
            elseif ($c.SHA256 -eq $r.SHA256) { $report[$r.Class].same++; continue }
            else { $report[$r.Class].changed++; $kind = 'changed' }
            if ($report[$r.Class].examples.Count -lt 5) { $report[$r.Class].examples.Add("$kind  $($r.Path)") }
        }
        foreach ($k in $report.Keys) {
            $v = $report[$k]
            $line = '{0,-48} same {1,6}   changed {2,4}   missing {3,4}' -f $k, $v.same, $v.changed, $v.missing
            if (($v.changed + $v.missing) -eq 0) { Write-OkLine $line }
            elseif ($mustMatch -contains $k) { Write-FailLine $line; $rc = 1 }
            else { Write-InfoLine $line }
            foreach ($e in $v.examples) { Write-InfoLine "    $e" }
        }
        $new = @($rows | Where-Object { -not $snapPaths.ContainsKey($_.Path) })
        if ($new.Count) {
            Write-InfoLine "$($new.Count) file(s) not in the snapshot:"
            foreach ($g in ($new | Group-Object -Property Class)) { Write-InfoLine ('    {0,5}  {1}' -f $g.Count, $g.Name) }
            foreach ($n in ($new | Select-Object -First 8)) { Write-InfoLine "    new  $($n.Path)" }
        }
        if ($rc -eq 0) { Write-OkLine 'Every patch, backup and stock file is byte-identical to the snapshot.' }
    }
}
exit $rc

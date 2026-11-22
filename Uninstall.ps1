<#
.SYNOPSIS
    Rolls Portal: Prelude RTX back from RTX Remix 1.6.1 to the stock Steam runtime (bridge "0.2.1-prelude").

.DESCRIPTION
    - Puts the 65 stock files back from the *.prelude-0.2.1.bak backups the installer (or an earlier
      manual upgrade that used the same names) made, then removes the Remix 1.6.1 files. Remix 1.6.1 files are only deleted when their
      bytes match NVIDIA's package exactly, so nothing unique is lost.
    - If a backup is missing, the rest is still rolled back and you are told to run Steam's
      "Verify integrity of game files", which restores the stock files.
    - rtx.conf, dxvk.conf, user.conf, saves and the Prelude asset mod are not touched.

.PARAMETER GameDir   The game folder, if it is not found automatically.
.PARAMETER DryRun    Show what would change and change nothing.
.PARAMETER Force     Move files with unexpected content to _RemixUpgrade_quarantine\ and continue.
#>
[CmdletBinding()]
param(
    [string]$GameDir,
    [switch]$DryRun,
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
Start-RunLog 'uninstall'

function Get-UninstallPlan($State, $Man) {
    $plan = New-Object System.Collections.Generic.List[object]
    $conflicts = New-Object System.Collections.Generic.List[object]
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($t in $State.PatchOnly) {
        $ps = $State.PatchStatus[$t]
        if ($ps -eq 'ok') { $plan.Add([pscustomobject]@{ Op = 'Delete'; Rel = $t; Rel2 = ''; Why = 'Remix 1.6.1 file (same bytes as NVIDIA''s package)' }) }
        elseif ($ps -eq 'other') { $conflicts.Add([pscustomobject]@{ Rel = $t; Why = 'unexpected content (not the Remix 1.6.1 file)' }) }
    }
    foreach ($s in $Man.Stock.Keys) {
        $st = $State.StockStatus[$s]; $bk = $State.BackupStatus[$s]; $b = Get-BackupRel $s
        if ($st -eq 'ok') {
            if ($bk -eq 'ok') { $plan.Add([pscustomobject]@{ Op = 'Delete'; Rel = $b; Rel2 = ''; Why = 'backup no longer needed: the stock file is in place' }) }
            continue
        }
        if ($st -eq 'other') { $conflicts.Add([pscustomobject]@{ Rel = $s; Why = 'unexpected content (neither stock 0.2.1 nor Remix 1.6.1)' }); continue }
        if ($bk -ne 'ok') { $missing.Add($s); continue }
        if ($st -eq 'patch') { $plan.Add([pscustomobject]@{ Op = 'Delete'; Rel = $s; Rel2 = ''; Why = 'Remix 1.6.1 file (same bytes as NVIDIA''s package)' }) }
        $plan.Add([pscustomobject]@{ Op = 'Restore'; Rel = $b; Rel2 = $s; Why = 'stock 0.2.1 file back from the backup' })
    }
    foreach ($f in $State.Foreign) {
        if ($f.EndsWith($script:TmpSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $plan.Add([pscustomobject]@{ Op = 'Delete'; Rel = $f; Rel2 = ''; Why = 'temp file left by an interrupted run' })
        }
    }
    foreach ($x in $State.BackupExtra) {   # e.g. NvRemixBridge.log that lived in the old bin\.trex
        $plan.Add([pscustomobject]@{ Op = 'RestoreExtra'; Rel = $x; Rel2 = ($script:TrexRel + $x.Substring($script:TrexBakRel.Length)); Why = 'file that was in the old bin\.trex' })
    }
    return [pscustomobject]@{ Plan = $plan; Conflicts = $conflicts; Missing = $missing }
}

$GameDir = Resolve-GameDirOrExit $GameDir
Assert-GameNotRunning $GameDir
$man = Import-UpgradeManifests

Write-StepLine 'Checking the installed files'
$state = Get-UpgradeState $GameDir $man
Write-StateReport $state
$p = Get-UninstallPlan $state $man

if ($p.Conflicts.Count) {
    Write-StepLine 'Files with unexpected content'
    foreach ($c in $p.Conflicts) { Write-WarnLine "$($c.Rel)  - $($c.Why)" }
    if (-not $Force) {
        Write-FailLine 'Nothing was changed. Run "Uninstall.bat -Force" to move these files into _RemixUpgrade_quarantine\ and continue.'
        exit 2
    }
    if ($DryRun) {
        Write-InfoLine '-Force would move these into _RemixUpgrade_quarantine\ first.'
    } else {
        $q = Join-Rel $GameDir ('_RemixUpgrade_quarantine\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        foreach ($c in $p.Conflicts) { Move-FileSafe (Join-Rel $GameDir $c.Rel) (Join-Path $q $c.Rel); Write-OkLine "Quarantined $($c.Rel)" }
        $state = Get-UpgradeState $GameDir $man
        $p = Get-UninstallPlan $state $man
    }
}

$plan = $p.Plan
Write-StepLine 'Plan'
if ($plan.Count -eq 0 -and $p.Missing.Count -eq 0) { Write-OkLine 'The stock 0.2.1 runtime is already in place. Nothing to do.' }
foreach ($op in 'Delete', 'Restore', 'RestoreExtra') {
    $n = @($plan | Where-Object { $_.Op -eq $op }).Count
    if ($n) { Write-InfoLine ('{0,-12} {1,4} file(s)' -f $op, $n) }
}
if ($p.Missing.Count) {
    Write-WarnLine "$($p.Missing.Count) stock file(s) have no backup, e.g. $($p.Missing[0])"
    if (-not $Force -and -not $DryRun) {
        Write-FailLine 'Nothing was changed, so the game still works as it is.'
        Write-InfoLine 'To roll back: Steam > Portal: Prelude RTX > Properties > Installed Files > Verify integrity of game files'
        Write-InfoLine '(this restores every stock file), then run Uninstall.bat again to remove the leftover Remix 1.6.1 files.'
        Write-InfoLine 'Or run "Uninstall.bat -Force" to roll back what can be rolled back now.'
        exit 2
    }
}
if ($DryRun) {
    foreach ($a in $plan) { Write-InfoLine ('{0,-12} {1}{2}' -f $a.Op, $a.Rel, $(if ($a.Rel2) { '  ->  ' + $a.Rel2 } else { '' })) }
    Write-StepLine 'Dry run: nothing was changed.'
    exit 0
}

if ($plan.Count) {
    Write-StepLine 'Rolling back'
    foreach ($a in $plan) {
        $abs = Join-Rel $GameDir $a.Rel
        switch ($a.Op) {
            'Delete'       { [System.IO.File]::Delete($abs) }
            'Restore'      { Move-FileSafe $abs (Join-Rel $GameDir $a.Rel2) }
            'RestoreExtra' { Move-FileSafe $abs (Get-FreeName (Join-Rel $GameDir $a.Rel2)) }
        }
    }
    Write-OkLine ("Done: {0} file operations" -f $plan.Count)
    Remove-EmptyDirs (Join-Rel $GameDir $script:TrexRel)
    Remove-EmptyDirs (Join-Rel $GameDir $script:TrexBakRel) -IncludeRoot
    $rec = Join-Rel $GameDir $script:RecordName
    if ([System.IO.File]::Exists($rec)) { [System.IO.File]::Delete($rec) }
}

Write-StepLine 'Verifying'
$state = Get-UpgradeState $GameDir $man
Write-StateReport $state
$left = @($state.PatchOnly | Where-Object { $state.PatchStatus[$_] -ne 'missing' })
$notStock = @($man.Stock.Keys | Where-Object { $state.StockStatus[$_] -ne 'ok' })
if ($notStock.Count -or $left.Count) {
    if ($notStock.Count) { Write-WarnLine "$($notStock.Count) stock file(s) are not back yet, e.g. $($notStock[0])" }
    if ($left.Count) { Write-WarnLine "$($left.Count) Remix 1.6.1 file(s) are still present, e.g. $($left[0])" }
    Write-FailLine 'Roll-back incomplete. Run Steam > Portal: Prelude RTX > Properties > Installed Files > Verify integrity of game files, then run Uninstall.bat again.'
    exit 1
}
Write-OkLine 'All 65 stock 0.2.1 files are back and no Remix 1.6.1 files are left. The game is back to the Steam version.'
exit 0

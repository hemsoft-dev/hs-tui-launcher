#Requires -Version 7.5
[CmdletBinding()]
param([string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Test-LauncherHandoff.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw 'The handoff harness could not be parsed.' }
foreach ($name in @('ConvertTo-BoundedText', 'Complete-HandoffReport')) {
    $definition = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if ($null -eq $definition) { throw "Missing handoff helper '$name'." }
    . ([scriptblock]::Create($definition.Extent.Text))
}

function New-CleanupFixture {
    param([string]$Parent, [string]$Reports)
    $leaf = "hs-tui-launcher-handoff-$PID-$([guid]::NewGuid().ToString('N'))"
    $directory = [IO.Path]::GetFullPath((Join-Path $Parent $leaf))
    [void] [IO.Directory]::CreateDirectory($directory)
    $file = Join-Path $directory 'locked-marker.txt'
    [IO.File]::WriteAllText($file, 'owned cleanup marker')
    $reportPath = Join-Path $Reports "$leaf.json"
    if (Test-Path -LiteralPath $reportPath) { throw 'Cleanup proof report must be fresh.' }
    return @{ directory = $directory; leaf = $leaf; file = $file; reportPath = $reportPath;
        report = [ordered]@{ status = 'pending-cleanup'; cases = @() } }
}

function Invoke-QualificationFixture {
    param([hashtable]$Fixture, [AllowNull()][Exception]$Cause)
    $primaryError = $null
    try {
        if ($Cause) { throw $Cause }
    }
    catch {
        $primaryError = $_
        $Fixture.report.error = $_.Exception.Message
        throw
    }
    finally {
        Complete-HandoffReport -Report $Fixture.report -ReportPath $Fixture.reportPath `
            -TemporaryDirectory $Fixture.directory -OwnedCleanupTarget $Fixture.directory `
            -OwnedTempLeaf $Fixture.leaf -PrimaryError $primaryError
    }
}

$parentLeaf = "hs-tui-launcher-cleanup-unit-$PID-$([guid]::NewGuid().ToString('N'))"
$parent = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) $parentLeaf))
$reports = if ($OutputDirectory) { Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) 'cleanup-evidence' }
else { Join-Path $parent 'reports' }
$results = [Collections.Generic.List[object]]::new()
try {
    [void] [IO.Directory]::CreateDirectory($reports)
    $resultsPath = Join-Path $reports 'results.json'
    if (Test-Path -LiteralPath $resultsPath -PathType Leaf) {
        Remove-Item -LiteralPath $resultsPath -Force -ErrorAction Stop
    }
    elseif (Test-Path -LiteralPath $resultsPath) { throw 'Cleanup-proof summary must be a file.' }
    $fixture = New-CleanupFixture -Parent $parent -Reports $reports
    Invoke-QualificationFixture -Fixture $fixture
    $persisted = Get-Content -LiteralPath $fixture.reportPath -Raw | ConvertFrom-Json
    if ($persisted.status -cne 'passed' -or -not $persisted.temporaryDirectoryRemoved -or
        (Test-Path -LiteralPath $fixture.directory)) { throw 'Successful cleanup proof failed.' }
    $results.Add(@{ case = 'successful cleanup'; passed = $true })

    $fixture = New-CleanupFixture -Parent $parent -Reports $reports
    $failure = $null
    try {
        Complete-HandoffReport -Report $fixture.report -ReportPath $fixture.reportPath `
            -TemporaryDirectory $fixture.directory -OwnedCleanupTarget $fixture.directory -OwnedTempLeaf 'wrong-leaf'
    }
    catch { $failure = $_ }
    $persisted = Get-Content -LiteralPath $fixture.reportPath -Raw | ConvertFrom-Json
    if (-not $failure -or $persisted.status -cne 'failed' -or $persisted.temporaryDirectoryRemoved -or
        $persisted.cleanupError -notmatch 'Refusing cleanup' -or
        [IO.File]::ReadAllText($fixture.file) -cne 'owned cleanup marker') {
        throw 'Ownership refusal was not retained as failed cleanup.'
    }
    $results.Add(@{ case = 'ownership refusal'; passed = $true })

    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        foreach ($hasPrimary in @($false, $true)) {
            $fixture = New-CleanupFixture -Parent $parent -Reports $reports
            $cause = if ($hasPrimary) { [InvalidOperationException]::new('controlled original qualification failure') } else { $null }
            $lock = [IO.File]::Open($fixture.file, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
            try {
                $failure = $null
                try { Invoke-QualificationFixture -Fixture $fixture -Cause $cause }
                catch { $failure = $_ }
                $persisted = Get-Content -LiteralPath $fixture.reportPath -Raw | ConvertFrom-Json
                if (-not $failure -or $persisted.status -cne 'failed' -or $persisted.temporaryDirectoryRemoved -or
                    [string]::IsNullOrWhiteSpace($persisted.cleanupError) -or
                    -not (Test-Path -LiteralPath $fixture.file)) { throw 'Actual locked-file cleanup failure was not retained.' }
                if ($hasPrimary -and (-not [object]::ReferenceEquals($failure.Exception, $cause) -or
                    $persisted.error -cne $cause.Message)) { throw 'Cleanup replaced the original qualification exception.' }
                $results.Add(@{ case = "Windows locked-file cleanup, primary=$hasPrimary"; passed = $true })
            }
            finally { $lock.Dispose() }
        }
    }

    foreach ($hasPrimary in @($false, $true)) {
        $fixture = New-CleanupFixture -Parent $parent -Reports $reports
        [void] [IO.Directory]::CreateDirectory($fixture.reportPath)
        $cause = if ($hasPrimary) { [InvalidOperationException]::new('controlled original report-write failure') } else { $null }
        $failure = $null
        try { Invoke-QualificationFixture -Fixture $fixture -Cause $cause }
        catch { $failure = $_ }
        if (-not $failure -or $fixture.report.status -cne 'failed' -or (Test-Path -LiteralPath $fixture.directory) -or
            (Test-Path -LiteralPath $fixture.reportPath -PathType Leaf)) { throw 'Required report-write failure was not rejected.' }
        if ($hasPrimary -and -not [object]::ReferenceEquals($failure.Exception, $cause)) {
            throw 'Report writing replaced the original qualification exception.'
        }
        $results.Add(@{ case = "actual report-write failure, primary=$hasPrimary"; passed = $true })
    }

    if ($OutputDirectory) {
        @{ status = 'passed'; windowsLockedFileProof = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT;
            cases = @($results) } | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $resultsPath -Encoding utf8NoBOM
    }
    Write-Host 'Handoff cleanup/report failure proofs passed.'
}
finally {
    $cleanupTarget = [IO.Path]::GetFullPath($parent)
    if ($cleanupTarget -cne $parent -or [IO.Path]::GetFileName($cleanupTarget) -cne $parentLeaf -or
        $parentLeaf -notmatch '^hs-tui-launcher-cleanup-unit-\d+-[a-f0-9]{32}$') { throw 'Invalid owned cleanup-proof directory.' }
    if (Test-Path -LiteralPath $cleanupTarget) { Remove-Item -LiteralPath $cleanupTarget -Recurse -Force -ErrorAction Stop }
}

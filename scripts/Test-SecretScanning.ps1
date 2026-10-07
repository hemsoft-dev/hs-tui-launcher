#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $RepositoryPath = (Split-Path -Parent $PSScriptRoot),
    [string] $GitleaksPath = (Join-Path (Split-Path -Parent $PSScriptRoot) $(if ($IsWindows) { 'bin/security-tools/gitleaks.exe' } else { 'bin/security-tools/gitleaks' })),
    [string] $ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.gitleaks.toml'),
    [string] $OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) "hs-secret-scan-$([guid]::NewGuid().ToString('N'))")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }

$repository = (Resolve-Path -LiteralPath $RepositoryPath).Path
$config = (Resolve-Path -LiteralPath $ConfigPath).Path
$scanner = (Resolve-Path -LiteralPath $GitleaksPath).Path
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$summaryPath = Join-Path $outputRoot 'summary.json'
$summary = [ordered]@{
    schemaVersion = 1
    revision = $null
    workingTreeDirty = $null
    pullRequestHead = $env:SECURITY_PR_HEAD
    historyScope = 'All locally reachable refs and HEAD; merge patches included; unreachable objects excluded.'
    logOptions = '--all -m'
    shallow = $null
    references = @()
    configSha256 = (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash.ToLowerInvariant()
    scans = @()
    policyPassed = $false
}

$primaryError = $null
try {
    $revision = @(& git -C $repository rev-parse HEAD)
    if ($LASTEXITCODE -ne 0 -or $revision.Count -ne 1 -or $revision[0] -notmatch '^[0-9a-f]{40}$') {
        throw 'Secret scanning requires an initialized Git repository with a valid HEAD.'
    }
    $summary.revision = $revision[0]
    if ([string]::IsNullOrEmpty($summary.pullRequestHead)) { $summary.pullRequestHead = $summary.revision }
    if ($summary.pullRequestHead -notmatch '^[0-9a-f]{40}$') { throw 'Secret-scan candidate revision must be a full Git SHA.' }
    $summary.workingTreeDirty = @(& git -C $repository status --porcelain --untracked-files=normal).Count -gt 0
    if ($LASTEXITCODE -ne 0) { throw 'Unable to determine secret-scanning working-tree state.' }
    $shallow = @(& git -C $repository rev-parse --is-shallow-repository)
    if ($LASTEXITCODE -ne 0 -or $shallow.Count -ne 1 -or $shallow[0] -notin @('true', 'false')) {
        throw 'Unable to determine whether secret-scanning history is complete.'
    }
    $summary.shallow = $shallow[0] -eq 'true'
    if ($summary.shallow) { throw 'Secret scanning refuses incomplete shallow history. Fetch full history and refs first.' }
    $summary.references = @(& git -C $repository for-each-ref '--format=%(refname) %(objectname)')
    if ($LASTEXITCODE -ne 0) { throw 'Unable to enumerate secret-scanning history refs.' }

    foreach ($mode in @('dir', 'git')) {
        $reportPath = Join-Path $outputRoot "$mode.json"
        # Remove old evidence so a tool failure cannot reuse a passing report.
        if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath -Force }
        $arguments = @($mode, '--config', $config, '--redact=100', '--no-banner', '--report-format', 'json', '--report-path', $reportPath)
        if ($mode -eq 'git') { $arguments += '--log-opts=--all -m' }
        $arguments += $repository
        Write-Host "Checking secrets: $mode"
        & $scanner @arguments
        $scannerExit = $LASTEXITCODE
        $findingCount = $null
        if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
            $findings = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate
            if ($findings -isnot [array]) { throw "gitleaks $mode report must be a JSON array." }
            $findingCount = $findings.Count
        }
        $summary.scans += [ordered]@{ mode = $mode; exitCode = $scannerExit; findings = $findingCount; report = "$mode.json" }
        if ($scannerExit -notin @(0, 1) -or $null -eq $findingCount -or
            ($scannerExit -eq 0 -and $findingCount -ne 0) -or ($scannerExit -eq 1 -and $findingCount -eq 0)) {
            throw "gitleaks $mode failed or produced inconsistent evidence (exit $scannerExit)."
        }
    }
    if (@($summary.scans | Where-Object { $_.exitCode -ne 0 }).Count -gt 0) {
        throw 'Secret qualification rejected working-tree or reachable-history findings. See redacted reports.'
    }
    $summary.policyPassed = $true
}
catch { $primaryError = $_ }
try {
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8
}
catch {
    if ($null -eq $primaryError) { throw }
    Write-Warning 'Secret-scan metadata could not be written; the original qualification failure is preserved.'
}
if ($null -ne $primaryError) { throw $primaryError }
Write-Host "Working-tree and reachable-history secret qualification passed. Evidence: $summaryPath"

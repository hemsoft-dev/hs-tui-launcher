#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $GitleaksPath = (Join-Path (Split-Path -Parent $PSScriptRoot) $(if ($IsWindows) { 'bin/security-tools/gitleaks.exe' } else { 'bin/security-tools/gitleaks' }))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }
$scanner = (Resolve-Path -LiteralPath $GitleaksPath).Path
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) "hs-secret-history-$([guid]::NewGuid().ToString('N'))"))
$repository = Join-Path $fixtureRoot 'repository'
$config = Join-Path $PSScriptRoot '../.github/security/fixtures/gitleaks.toml'
$secret = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../.github/security/fixtures/secret.txt') -Raw
$qualification = Join-Path $PSScriptRoot 'Test-SecretScanning.ps1'

function Invoke-FixtureGit {
    param([string[]] $Arguments)
    & git -C $repository @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Fixture Git failed: $($Arguments -join ' ')" }
}

function Assert-QualificationFailure {
    param([string] $Path, [string] $Output, [string] $Expected)
    $failure = $null
    try {
        & $qualification -RepositoryPath $Path -GitleaksPath $scanner -ConfigPath $config -OutputDirectory $Output
    }
    catch { $failure = $_ }
    if ($null -eq $failure -or $failure.Exception.Message -notmatch $Expected) {
        throw "Expected qualification failure '$Expected' was not observed."
    }
}

New-Item -ItemType Directory -Path $repository -Force | Out-Null
try {
    Invoke-FixtureGit @('init', '-b', 'main')
    Invoke-FixtureGit @('config', 'user.email', 'fixture@example.invalid')
    Invoke-FixtureGit @('config', 'user.name', 'Secret history fixture')
    Set-Content -LiteralPath (Join-Path $repository 'README.txt') -Value 'Inert fixture repository.'
    Invoke-FixtureGit @('add', '.')
    Invoke-FixtureGit @('commit', '-m', 'Clean baseline')
    $cleanMetadataFailure = Join-Path $fixtureRoot 'clean-metadata-failure'
    New-Item -ItemType Directory -Path (Join-Path $cleanMetadataFailure 'summary.json') -Force | Out-Null
    Assert-QualificationFailure $repository $cleanMetadataFailure 'denied|directory|Unauthorized'
    Set-Content -LiteralPath (Join-Path $repository 'secret.txt') -Value $secret
    Invoke-FixtureGit @('add', '.')
    Invoke-FixtureGit @('commit', '-m', 'Introduce inert fixture')
    Invoke-FixtureGit @('rm', 'secret.txt')
    Invoke-FixtureGit @('commit', '-m', 'Delete inert fixture')
    $evidence = Join-Path $fixtureRoot 'deleted-evidence'
    Assert-QualificationFailure $repository $evidence 'reachable-history findings'
    $summary = Get-Content -LiteralPath (Join-Path $evidence 'summary.json') -Raw | ConvertFrom-Json
    if ($summary.policyPassed -or $summary.scans[0].exitCode -ne 0 -or $summary.scans[0].findings -ne 0 -or
        $summary.scans[1].exitCode -ne 1 -or $summary.scans[1].findings -ne 1) {
        throw 'Deleted-secret fixture must be clean in the tree and have exactly one history finding.'
    }
    $reportText = Get-Content -LiteralPath (Join-Path $evidence 'git.json') -Raw
    if ($reportText.Contains('fixture-not-a-real-secret') -or $reportText -notmatch 'REDACTED') {
        throw 'History fixture evidence was not redacted.'
    }

    # Introduce the sentinel only in a merge commit, not either parent.
    Invoke-FixtureGit @('checkout', '--orphan', 'merge-main')
    Invoke-FixtureGit @('rm', '-rf', '.')
    Set-Content -LiteralPath (Join-Path $repository 'base.txt') -Value 'Clean merge baseline.'
    Invoke-FixtureGit @('add', '.')
    Invoke-FixtureGit @('commit', '-m', 'Clean merge root')
    Invoke-FixtureGit @('checkout', '-b', 'merge-side')
    Set-Content -LiteralPath (Join-Path $repository 'side.txt') -Value 'Side change.'
    Invoke-FixtureGit @('add', '.')
    Invoke-FixtureGit @('commit', '-m', 'Clean side')
    Invoke-FixtureGit @('checkout', 'merge-main')
    Set-Content -LiteralPath (Join-Path $repository 'main.txt') -Value 'Main change.'
    Invoke-FixtureGit @('add', '.')
    Invoke-FixtureGit @('commit', '-m', 'Clean main')
    Invoke-FixtureGit @('merge', '--no-commit', '--no-ff', 'merge-side')
    Set-Content -LiteralPath (Join-Path $repository 'secret.txt') -Value $secret
    Invoke-FixtureGit @('add', '.')
    Invoke-FixtureGit @('commit', '-m', 'Inert merge-only fixture')
    $mergeRevision = (& git -C $repository rev-parse HEAD).Trim()
    Invoke-FixtureGit @('rm', 'secret.txt')
    Invoke-FixtureGit @('commit', '-m', 'Remove merge fixture')
    $mergeEvidence = Join-Path $fixtureRoot 'merge-evidence'
    Assert-QualificationFailure $repository $mergeEvidence 'reachable-history findings'
    $mergeFindings = @(Get-Content -LiteralPath (Join-Path $mergeEvidence 'git.json') -Raw | ConvertFrom-Json)
    # -m may report the same merge finding once per parent diff.
    $mergeFingerprints = @($mergeFindings | Where-Object { $_.Commit -eq $mergeRevision } |
        ForEach-Object { $_.Fingerprint } | Select-Object -Unique)
    if ($mergeFingerprints.Count -ne 1) {
        throw 'Merge-only secret must be found in its actual merge revision.'
    }

    $shallow = Join-Path $fixtureRoot 'shallow'
    & git clone --quiet --depth 1 --branch merge-main ([uri]::new($repository + [IO.Path]::DirectorySeparatorChar).AbsoluteUri) $shallow
    if ($LASTEXITCODE -ne 0) { throw 'Fixture shallow clone failed.' }
    $shallowEvidence = Join-Path $fixtureRoot 'shallow-evidence'
    Assert-QualificationFailure $shallow $shallowEvidence 'incomplete shallow history'
    $shallowSummary = Get-Content -LiteralPath (Join-Path $shallowEvidence 'summary.json') -Raw | ConvertFrom-Json
    if (-not $shallowSummary.shallow -or $shallowSummary.policyPassed -or $shallowSummary.scans.Count -ne 0) {
        throw 'Shallow history must fail before scanning.'
    }

    # Real metadata-write failure must preserve the already-observed finding.
    $unwritableSummary = Join-Path $fixtureRoot 'metadata-failure'
    New-Item -ItemType Directory -Path (Join-Path $unwritableSummary 'summary.json') -Force | Out-Null
    Assert-QualificationFailure $repository $unwritableSummary 'reachable-history findings'
    Write-Host 'Deleted-secret, merge-only, shallow-history, redaction, and primary-failure fixtures passed.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixtureRoot)
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing cleanup outside the fixture temporary root.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

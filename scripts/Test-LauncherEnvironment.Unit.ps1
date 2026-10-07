#requires -Version 7.2
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$wrapperPath = Join-Path $PSScriptRoot '../run.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($wrapperPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'The wrapper could not be parsed.' }
foreach ($name in @('Set-TemporaryEnvironment', 'Restore-Environment')) {
    $definition = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if ($null -eq $definition) { throw "Missing wrapper helper: $name" }
    . ([scriptblock]::Create($definition.Extent.Text))
}

$names = @('HS_ENV_TEST_REPEATED', 'HS_ENV_TEST_EMPTY', 'HS_ENV_TEST_ABSENT', 'hs_env_test_repeated')
$callerComparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
$callerValues = [Collections.Generic.Dictionary[string, object]]::new($callerComparer)
foreach ($name in $names) { $callerValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    Set-Item -LiteralPath Env:HS_ENV_TEST_REPEATED -Value 'original'
    Set-Item -LiteralPath Env:HS_ENV_TEST_EMPTY -Value ''
    Remove-Item -LiteralPath Env:HS_ENV_TEST_ABSENT -ErrorAction SilentlyContinue
    if (-not $IsWindows) { Set-Item -LiteralPath Env:hs_env_test_repeated -Value 'distinct original' }
    $snapshot = Set-TemporaryEnvironment -Entries @(
        'HS_ENV_TEST_REPEATED=first', 'HS_ENV_TEST_REPEATED=second',
        'HS_ENV_TEST_EMPTY=first', 'HS_ENV_TEST_EMPTY=',
        'HS_ENV_TEST_ABSENT=first', 'HS_ENV_TEST_ABSENT=second',
        'hs_env_test_repeated=case override'
    )
    $expectedValue = if ($IsWindows) { 'case override' } else { 'second' }
    if ($env:HS_ENV_TEST_REPEATED -cne $expectedValue -or $env:hs_env_test_repeated -cne 'case override') {
        throw 'Last override did not reach the environment.'
    }
    Restore-Environment -PreviousValues $snapshot
    if ($env:HS_ENV_TEST_REPEATED -cne 'original' -or
        -not (Test-Path Env:HS_ENV_TEST_EMPTY) -or $env:HS_ENV_TEST_EMPTY -cne '' -or
        (Test-Path Env:HS_ENV_TEST_ABSENT)) { throw 'Original environment was not restored.' }
    if (-not $IsWindows -and $env:hs_env_test_repeated -cne 'distinct original') {
        throw 'Case-sensitive environment names were merged.'
    }
}
finally {
    foreach ($name in $names) {
        if ($null -eq $callerValues[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue }
        else { Set-Item -LiteralPath "Env:$name" -Value $callerValues[$name] }
    }
}
Write-Host 'Wrapper environment snapshot checks passed.'

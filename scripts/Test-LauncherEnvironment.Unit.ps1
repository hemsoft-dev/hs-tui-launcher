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
$helperSource = [Collections.Generic.List[string]]::new()
foreach ($name in @('Set-ProcessEnvironmentValue', 'Set-TemporaryEnvironment', 'Restore-Environment')) {
    $definition = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if ($null -eq $definition) { throw "Missing wrapper helper: $name" }
    $helperSource.Add($definition.Extent.Text)
    . ([scriptblock]::Create($definition.Extent.Text))
}

$names = @('HS_ENV_TEST_REPEATED', 'HS_ENV_TEST_EMPTY', 'HS_ENV_TEST_ABSENT', 'hs_env_test_repeated')
$callerComparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
$callerValues = [Collections.Generic.Dictionary[string, object]]::new($callerComparer)
foreach ($name in $names) { $callerValues[$name] = [Environment]::GetEnvironmentVariables('Process')[$name] }
try {
    Set-Item -LiteralPath Env:HS_ENV_TEST_REPEATED -Value 'original'
    Set-ProcessEnvironmentValue -Name 'HS_ENV_TEST_EMPTY' -Value ''
    if (-not (Test-Path Env:HS_ENV_TEST_EMPTY)) { throw 'Empty-value setup did not create a present variable.' }
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
        else { Set-ProcessEnvironmentValue -Name $name -Value $callerValues[$name] }
    }
}
Write-Host 'Wrapper environment snapshot checks passed.'

if ($IsWindows) {
    $legacyPath = Join-Path ([IO.Path]::GetTempPath()) "hs-env-legacy-$([guid]::NewGuid().ToString('N')).ps1"
    $legacyAssertions = @'
$ErrorActionPreference = 'Stop'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
$snapshot = Set-TemporaryEnvironment -Entries @(
    'hs_env_test_input=first', 'HS_ENV_TEST_INPUT=second',
    'HS_ENV_TEST_EMPTY=first', 'HS_ENV_TEST_EMPTY=',
    'HS_ENV_TEST_ABSENT=first', 'HS_ENV_TEST_ABSENT=second'
)
$values = [Environment]::GetEnvironmentVariables('Process')
if ($env:HS_ENV_TEST_INPUT -cne 'second' -or -not $values.Contains('HS_ENV_TEST_EMPTY') -or
    $values['HS_ENV_TEST_EMPTY'] -cne '') { throw 'Legacy override mismatch.' }
Restore-Environment -PreviousValues $snapshot
$values = [Environment]::GetEnvironmentVariables('Process')
if ($env:HS_ENV_TEST_INPUT -cne 'original' -or -not $values.Contains('HS_ENV_TEST_EMPTY') -or
    $values['HS_ENV_TEST_EMPTY'] -cne '' -or $values.Contains('HS_ENV_TEST_ABSENT')) {
    throw 'Legacy original environment restoration failed.'
}
Write-Output 'Legacy empty-presence and Turkish-culture checks passed.'
'@
    try {
        ($helperSource -join "`n") + "`n" + $legacyAssertions |
            Set-Content -LiteralPath $legacyPath -Encoding utf8NoBOM
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
        foreach ($argument in @('-NoProfile', '-File', $legacyPath)) { $startInfo.ArgumentList.Add($argument) }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.Environment['PSModulePath'] = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
        $startInfo.Environment['HS_ENV_TEST_INPUT'] = 'original'
        $startInfo.Environment['HS_ENV_TEST_EMPTY'] = ''
        $startInfo.Environment.Remove('HS_ENV_TEST_ABSENT') | Out-Null
        $process = [Diagnostics.Process]::Start($startInfo)
        try {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            if ($process.ExitCode -ne 0 -or $stdout.Result -notmatch 'Legacy empty-presence and Turkish-culture checks passed') {
                throw "Legacy environment test failed: $($stderr.Result)"
            }
            Write-Host $stdout.Result.Trim()
        }
        finally { $process.Dispose() }
    }
    finally { Remove-Item -LiteralPath $legacyPath -Force }
}

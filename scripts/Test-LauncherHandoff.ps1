<#
.SYNOPSIS
Qualifies run.ps1 or run.sh with deterministic native and go-run launcher fixtures.

.DESCRIPTION
Requires PowerShell 7.5 or newer. Fixture modules and binaries are created below the
system temporary directory. The controlled child records only its arguments, working
directory, stdin, target, and four allowlisted HS_HANDOFF_* variables. No provider CLI
is started, no credential is required, and Go network access is disabled.

.PARAMETER OutputDirectory
Directory for the bounded JSON report. The default is process-specific and outside the
repository. CI supplies an artifact staging directory.

.PARAMETER NegativeCheck
Runs safe synthetic checks proving that argv, environment, working-directory, stdin,
and expected-exit mismatches are rejected by the same assertion function.
#>
#requires -Version 7.5
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "hs-tui-launcher-handoff-$PID"),
    [switch]$NegativeCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
& (Join-Path $PSScriptRoot 'Test-LauncherEnvironment.Unit.ps1')
& (Join-Path $PSScriptRoot 'Test-LauncherNativeArgument.Unit.ps1')
$expectedArguments = @(
    'plain',
    'value with spaces',
    '',
    'semi;pipe|amp&angle<>dollar$backtick`quotes''"',
    'equals=value',
    'backslash\trailing\',
    'unicode-雪'
)
$expectedStdin = "fixture stdin`nsecond line with spaces & | <> `$`n"
$expectedSelected = 'selected value with spaces ; $ & | <>'
$expectedInherited = 'inherited value with spaces'
$reportSchemaVersion = 3
$observationSchemaVersion = 2

function Get-NativeOutputName {
    param([Parameter(Mandatory)][string]$BaseName, [Parameter(Mandatory)][string]$GOOS)
    if ($GOOS -eq 'windows') { return "$BaseName.exe" }
    return $BaseName
}

function Invoke-Go {
    param([Parameter(Mandatory)][string[]]$Arguments, [Parameter(Mandatory)][string]$WorkingDirectory)

    Push-Location -LiteralPath $WorkingDirectory
    try {
        $output = @(& go @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    $output | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0) {
        throw "go $($Arguments -join ' ') failed with exit code $exitCode."
    }
}

function ConvertTo-BoundedText {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value.Length -le 4096) { return $Value }
    return $Value.Substring(0, 4096) + "`n[truncated]"
}

function Assert-ExactHandoff {
    param(
        [Parameter(Mandatory)]$Observed,
        [Parameter(Mandatory)][string]$ExpectedWorkingDirectory,
        [Parameter(Mandatory)][int]$ObservedExitCode,
        [Parameter(Mandatory)][int]$ExpectedExitCode
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $actualArguments = @($Observed.arguments)
    if (($actualArguments | ConvertTo-Json -Compress) -cne ($expectedArguments | ConvertTo-Json -Compress)) {
        $failures.Add('arguments')
    }
    if ([string]$Observed.workingDirectory -cne $ExpectedWorkingDirectory) {
        $failures.Add('workingDirectory')
    }
    if ([int]$Observed.schemaVersion -ne $observationSchemaVersion) {
        $failures.Add('observationSchemaVersion')
    }
    if (-not [bool]$Observed.environment.HS_HANDOFF_SELECTED.present -or
        -not [bool]$Observed.environment.HS_HANDOFF_EMPTY.present -or
        -not [bool]$Observed.environment.HS_HANDOFF_EXIT_CODE.present -or
        -not [bool]$Observed.environment.HS_HANDOFF_INHERITED.present) {
        $failures.Add('environmentPresence')
    }
    if ([string]$Observed.environment.HS_HANDOFF_SELECTED.value -cne $expectedSelected -or
        [string]$Observed.environment.HS_HANDOFF_EMPTY.value -cne '' -or
        [string]$Observed.environment.HS_HANDOFF_EXIT_CODE.value -cne "$ExpectedExitCode" -or
        [string]$Observed.environment.HS_HANDOFF_INHERITED.value -cne $expectedInherited) {
        $failures.Add('environment')
    }
    if ([string]$Observed.stdin -cne $expectedStdin) {
        $failures.Add('stdin')
    }
    if ($ObservedExitCode -ne $ExpectedExitCode) {
        $failures.Add('exitCode')
    }
    if ([string]$Observed.goos -cne $goos -or [string]$Observed.goarch -cne $goarch) {
        $failures.Add('target')
    }
    if ($failures.Count -gt 0) {
        throw "Handoff mismatch: $($failures -join ', ')."
    }
}

function Assert-NegativeCaseRejected {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ExpectedFailure,
        [Parameter(Mandatory)]$Observed,
        [Parameter(Mandatory)][string]$ExpectedWorkingDirectory,
        [Parameter(Mandatory)][int]$ObservedExitCode,
        [Parameter(Mandatory)][int]$ExpectedExitCode
    )

    try {
        Assert-ExactHandoff -Observed $Observed -ExpectedWorkingDirectory $ExpectedWorkingDirectory `
            -ObservedExitCode $ObservedExitCode -ExpectedExitCode $ExpectedExitCode
    }
    catch {
        if ($_.Exception.Message -notmatch [regex]::Escape($ExpectedFailure)) {
            throw "Negative case '$Name' failed for the wrong reason: $($_.Exception.Message)"
        }
        return [ordered]@{ name = $Name; expectedFailure = $ExpectedFailure; rejected = $true }
    }
    throw "Negative case '$Name' was not rejected."
}

function New-ProcessResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This test helper captures a child process result and does not change system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$Stdin,
        [Parameter(Mandatory)][hashtable]$Environment
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FileName
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    foreach ($argument in $Arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    foreach ($entry in $Environment.GetEnumerator()) {
        $startInfo.Environment[$entry.Key] = [string]$entry.Value
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw "Could not start '$FileName'." }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($Stdin)
    $process.StandardInput.Close()
    $process.WaitForExit()
    $stdout.Wait()
    $stderr.Wait()
    $result = [ordered]@{
        exitCode = $process.ExitCode
        stdout = ConvertTo-BoundedText -Value $stdout.Result
        stderr = ConvertTo-BoundedText -Value $stderr.Result
    }
    $process.Dispose()
    return $result
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$commit = (& git -C $repositoryRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or -not $commit) { throw 'Could not determine the checked-out commit.' }
$targetParts = @(& go env GOOS GOARCH GOVERSION)
if ($LASTEXITCODE -ne 0 -or $targetParts.Count -ne 3) { throw 'go env did not return GOOS, GOARCH, and GOVERSION.' }
$goos = "$($targetParts[0])".Trim()
$goarch = "$($targetParts[1])".Trim()
$goVersion = "$($targetParts[2])".Trim()
$targetName = "$goos-$goarch"
if ($goos -eq 'windows') {
    $hosts = @(
        [ordered]@{ name = 'pwsh'; executable = (Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source },
        [ordered]@{ name = 'powershell'; executable = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source }
    )
}
else {
    $hosts = @([ordered]@{ name = 'sh'; executable = (Get-Command sh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source })
}
$reportKind = if ($NegativeCheck) { 'negative' } else { 'results' }
$reportPath = Join-Path $outputRoot "launcher-handoff-$reportKind-$targetName-$commit.json"
$wrapperName = if ($goos -eq 'windows') { 'run.ps1' } else { 'run.sh' }
$wrapperSource = Join-Path $repositoryRoot $wrapperName

$report = [ordered]@{
    schemaVersion = $reportSchemaVersion
    observationSchemaVersion = $observationSchemaVersion
    commit = $commit
    target = [ordered]@{ goos = $goos; goarch = $goarch; goVersion = $goVersion }
    wrapper = [ordered]@{
        path = $wrapperName
        sha256 = (Get-FileHash -LiteralPath $wrapperSource -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    launcherModes = @('native', 'fallback')
    hosts = @($hosts | ForEach-Object { $_.name })
    fixtureSelection = [ordered]@{
        executable = 'temporary controlled child fixture (assigned after build)'
        arguments = @($expectedArguments)
        environment = [ordered]@{
            HS_HANDOFF_SELECTED = $expectedSelected
            HS_HANDOFF_EMPTY = ''
            HS_HANDOFF_EXIT_CODE = '0 or 23 according to the case'
        }
    }
    networkAccess = 'GOPROXY=off and GOSUMDB=off for fixture builds and go run'
    credentials = 'not required or read; only allowlisted HS_HANDOFF_* values are recorded'
    status = 'running'
    cases = @()
}

function Write-Report {
    $report.generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM
}

if ($NegativeCheck) {
    try {
        $baseline = [pscustomobject]@{
            schemaVersion = $observationSchemaVersion
            arguments = @($expectedArguments)
            workingDirectory = '/expected/working directory'
            environment = [pscustomobject]@{
                HS_HANDOFF_SELECTED = [pscustomobject]@{ value = $expectedSelected; present = $true }
                HS_HANDOFF_EMPTY = [pscustomobject]@{ value = ''; present = $true }
                HS_HANDOFF_EXIT_CODE = [pscustomobject]@{ value = '23'; present = $true }
                HS_HANDOFF_INHERITED = [pscustomobject]@{ value = $expectedInherited; present = $true }
            }
            stdin = $expectedStdin
            goos = $goos
            goarch = $goarch
        }
        $negativeCases = [System.Collections.Generic.List[object]]::new()

        $observed = ($baseline | ConvertTo-Json -Depth 5 | ConvertFrom-Json)
        $observed.arguments[0] = 'wrong'
        $negativeCases.Add((Assert-NegativeCaseRejected -Name 'mismatched argv' -ExpectedFailure 'arguments' `
            -Observed $observed -ExpectedWorkingDirectory $baseline.workingDirectory -ObservedExitCode 23 -ExpectedExitCode 23))

        $observed = ($baseline | ConvertTo-Json -Depth 5 | ConvertFrom-Json)
        $observed.environment.HS_HANDOFF_SELECTED.value = 'wrong'
        $negativeCases.Add((Assert-NegativeCaseRejected -Name 'mismatched environment' -ExpectedFailure 'environment' `
            -Observed $observed -ExpectedWorkingDirectory $baseline.workingDirectory -ObservedExitCode 23 -ExpectedExitCode 23))

        $observed = ($baseline | ConvertTo-Json -Depth 5 | ConvertFrom-Json)
        $observed.environment.HS_HANDOFF_EMPTY.present = $false
        $negativeCases.Add((Assert-NegativeCaseRejected -Name 'missing empty environment variable' -ExpectedFailure 'environmentPresence' `
            -Observed $observed -ExpectedWorkingDirectory $baseline.workingDirectory -ObservedExitCode 23 -ExpectedExitCode 23))

        $observed = ($baseline | ConvertTo-Json -Depth 5 | ConvertFrom-Json)
        $observed.workingDirectory = '/wrong'
        $negativeCases.Add((Assert-NegativeCaseRejected -Name 'mismatched working directory' -ExpectedFailure 'workingDirectory' `
            -Observed $observed -ExpectedWorkingDirectory $baseline.workingDirectory -ObservedExitCode 23 -ExpectedExitCode 23))

        $observed = ($baseline | ConvertTo-Json -Depth 5 | ConvertFrom-Json)
        $observed.stdin = 'wrong'
        $negativeCases.Add((Assert-NegativeCaseRejected -Name 'mismatched stdin' -ExpectedFailure 'stdin' `
            -Observed $observed -ExpectedWorkingDirectory $baseline.workingDirectory -ObservedExitCode 23 -ExpectedExitCode 23))

        $observed = ($baseline | ConvertTo-Json -Depth 5 | ConvertFrom-Json)
        $negativeCases.Add((Assert-NegativeCaseRejected -Name 'mismatched nonzero child exit expectation' -ExpectedFailure 'exitCode' `
            -Observed $observed -ExpectedWorkingDirectory $baseline.workingDirectory -ObservedExitCode 22 -ExpectedExitCode 23))

        $report.cases = @($negativeCases)
        $report.status = 'passed'
        Write-Report
        Write-Host "Safe negative handoff checks passed. Report: $reportPath"
        exit 0
    }
    catch {
        $report.status = 'failed'
        $report.error = ConvertTo-BoundedText -Value $_.Exception.Message
        Write-Report
        throw
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "hs-tui-launcher-handoff-$PID-$([guid]::NewGuid().ToString('N'))"
$ownedTempLeaf = [IO.Path]::GetFileName($tempRoot)
$ownedCleanupTarget = [IO.Path]::GetFullPath($tempRoot)
$primaryError = $null
$previousGoToolchain = $env:GOTOOLCHAIN
$previousGoProxy = $env:GOPROXY
$previousGoSumDB = $env:GOSUMDB
$env:GOTOOLCHAIN = 'local'
$env:GOPROXY = 'off'
$env:GOSUMDB = 'off'

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    if ($goos -ne 'windows') {
        # macOS exposes /var through /private/var. Select the physical path so the
        # fixture's selected working directory exactly matches os.Getwd().
        $physicalTempRoot = @(& python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' $tempRoot)
        if ($LASTEXITCODE -ne 0 -or $physicalTempRoot.Count -ne 1) {
            throw 'Python could not resolve the fixture temporary directory.'
        }
        $tempRoot = "$($physicalTempRoot[0])".Trim()
        $ownedCleanupTarget = [IO.Path]::GetFullPath($tempRoot)
    }
    $windowsDriver = Join-Path $tempRoot 'invoke-run-ps1.ps1'
    @'
param(
    [Parameter(Mandatory)][string]$Wrapper,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$WrapperArguments
)
$env:HS_HANDOFF_SELECTED = 'original value'
$hostMetadata = [ordered]@{
    version = $PSVersionTable.PSVersion.ToString()
    edition = $PSVersionTable.PSEdition
    home = $PSHOME
}
[IO.File]::WriteAllText($env:HS_HANDOFF_HOST_METADATA,
    ($hostMetadata | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
$initialEnvironment = [Environment]::GetEnvironmentVariables('Process')
if (-not $initialEnvironment.Contains('HS_HANDOFF_EMPTY') -or
    $initialEnvironment['HS_HANDOFF_EMPTY'] -cne '') { throw 'The fixture host must inherit an empty variable.' }
Remove-Item -LiteralPath Env:HS_HANDOFF_OUTPUT -ErrorAction SilentlyContinue
& $Wrapper @WrapperArguments
$childExitCode = $LASTEXITCODE
if ([Environment]::GetEnvironmentVariable('HS_HANDOFF_SELECTED', 'Process') -cne 'original value') {
    throw 'Repeated override did not restore the original value.'
}
$restoredEnvironment = [Environment]::GetEnvironmentVariables('Process')
if (-not $restoredEnvironment.Contains('HS_HANDOFF_EMPTY') -or $restoredEnvironment['HS_HANDOFF_EMPTY'] -cne '') {
    throw 'Repeated override did not restore an originally empty variable.'
}
if (Test-Path -LiteralPath Env:HS_HANDOFF_OUTPUT) {
    throw 'Repeated override did not restore an originally absent variable.'
}
exit $childExitCode
'@ | Set-Content -LiteralPath $windowsDriver -Encoding utf8NoBOM

    $buildRoot = Join-Path $tempRoot 'fixture-build'
    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
    $goDirective = (Get-Content -LiteralPath (Join-Path $repositoryRoot 'go.mod') | Where-Object { $_ -match '^go\s+' } | Select-Object -First 1) -replace '^go\s+', ''
    if ($goDirective -notmatch '^(?<major>\d+)\.(?<minor>\d+)') { throw 'go.mod does not declare a valid Go version.' }
    # Fixtures use only the module's language version so an older patch toolchain can run
    # local no-network validation. CI separately installs and tests the exact go.mod version.
    $fixtureGoDirective = "$($Matches.major).$($Matches.minor)"
    "module example.invalid/hs-tui-launcher-handoff-fixture`n`ngo $fixtureGoDirective`n" |
        Set-Content -LiteralPath (Join-Path $buildRoot 'go.mod') -Encoding utf8NoBOM

    $childName = Get-NativeOutputName -BaseName 'handoff-child' -GOOS $goos
    $launcherName = Get-NativeOutputName -BaseName 'hs-tui-launcher' -GOOS $goos
    $childBinary = Join-Path $buildRoot $childName
    $launcherBinary = Join-Path $buildRoot $launcherName
    $report.fixtureSelection.executable = $childBinary
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'handoff-fixtures/child.go.txt') -Destination (Join-Path $buildRoot 'main.go')
    Invoke-Go -Arguments @('build', '-trimpath', '-o', $childBinary, '.') -WorkingDirectory $buildRoot
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'handoff-fixtures/launcher.go.txt') -Destination (Join-Path $buildRoot 'main.go') -Force
    Invoke-Go -Arguments @('build', '-trimpath', '-o', $launcherBinary, '.') -WorkingDirectory $buildRoot

    $caseReports = [System.Collections.Generic.List[object]]::new()
    foreach ($mode in @('native', 'fallback')) {
        $sandbox = Join-Path $tempRoot "wrapper-$mode"
        New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
        $wrapperUnderTest = Join-Path $sandbox $wrapperName
        Copy-Item -LiteralPath $wrapperSource -Destination $wrapperUnderTest
        if ($goos -ne 'windows') {
            & chmod +x $wrapperUnderTest
            if ($LASTEXITCODE -ne 0) { throw "chmod failed for '$wrapperUnderTest'." }
        }
        if ($mode -eq 'native') {
            Copy-Item -LiteralPath $launcherBinary -Destination (Join-Path $sandbox $launcherName)
            if ($goos -ne 'windows') {
                & chmod +x (Join-Path $sandbox $launcherName)
                if ($LASTEXITCODE -ne 0) { throw 'chmod failed for the native launcher fixture.' }
            }
        }
        else {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'handoff-fixtures/launcher.go.txt') -Destination (Join-Path $sandbox 'main.go')
            Copy-Item -LiteralPath (Join-Path $buildRoot 'go.mod') -Destination (Join-Path $sandbox 'go.mod')
        }

        foreach ($hostChoice in $hosts) {
        foreach ($expectedExitCode in @(0, 23)) {
            $caseRoot = Join-Path $sandbox "case-$($hostChoice.name)-$expectedExitCode"
            $workingDirectory = Join-Path $caseRoot 'working directory with spaces'
            New-Item -ItemType Directory -Path $workingDirectory -Force | Out-Null
            $observationPath = Join-Path $caseRoot 'observed.json'
            $metadataPath = Join-Path $caseRoot 'launcher.json'
            $launcherArguments = @(
                '--fixture-mode', $mode,
                '--fixture-child', $childBinary,
                '--fixture-working-dir', $workingDirectory,
                '--fixture-output', $observationPath,
                '--fixture-exit-code', "$expectedExitCode",
                '--fixture-metadata', $metadataPath
            )
            $processEnvironment = @{
                HS_HANDOFF_INHERITED = $expectedInherited
                HS_HANDOFF_EMPTY = ''
                GOTOOLCHAIN = 'local'
                GOPROXY = 'off'
                GOSUMDB = 'off'
            }
            if ($goos -eq 'windows') {
                $hostExecutable = $hostChoice.executable
                $hostMetadataPath = Join-Path $caseRoot 'host.json'
                $processEnvironment.HS_HANDOFF_HOST_METADATA = $hostMetadataPath
                if ($hostChoice.name -eq 'powershell') {
                    # Legacy Windows modules must not inherit PowerShell 7's
                    # module search path from the qualifying harness.
                    $processEnvironment.PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
                }
                # run.ps1 intentionally returns to an interactive caller after setting
                # LASTEXITCODE. The temporary host translates that script contract into
                # the dedicated pwsh process exit code without changing the wrapper.
                $hostArguments = @('-NoLogo', '-NoProfile', '-File', $windowsDriver, $wrapperUnderTest) + $launcherArguments
            }
            else {
                $hostExecutable = $hostChoice.executable
                $hostArguments = @($wrapperUnderTest) + $launcherArguments
            }

            $processResult = New-ProcessResult -FileName $hostExecutable -Arguments $hostArguments `
                -WorkingDirectory $caseRoot -Stdin $expectedStdin -Environment $processEnvironment
            if (-not (Test-Path -LiteralPath $observationPath -PathType Leaf)) {
                throw "The $mode/$expectedExitCode child did not write its bounded observation. stderr: $($processResult.stderr)"
            }
            if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
                throw "The $mode/$expectedExitCode launcher did not write invocation metadata."
            }
            $observed = Get-Content -LiteralPath $observationPath -Raw | ConvertFrom-Json
            $launcherObserved = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
            if ([string]$launcherObserved.mode -cne $mode) {
                throw "Launcher mode mismatch: expected '$mode', observed '$($launcherObserved.mode)'."
            }
            $selectionFile = [string]$launcherObserved.selectionFile
            if ([string]::IsNullOrWhiteSpace($selectionFile) -or (Test-Path -LiteralPath $selectionFile)) {
                throw 'The wrapper did not pass and then remove its temporary selection file.'
            }
            Assert-ExactHandoff -Observed $observed -ExpectedWorkingDirectory $workingDirectory `
                -ObservedExitCode $processResult.exitCode -ExpectedExitCode $expectedExitCode
            if ($processResult.stdout.Trim() -cne 'HS_HANDOFF_STDOUT_SENTINEL' -or
                $processResult.stderr.Trim() -cne 'HS_HANDOFF_STDERR_SENTINEL') {
                throw 'The selected native child did not inherit both bounded output streams.'
            }

            $hostObserved = [ordered]@{ name = $hostChoice.name; executable = $hostExecutable }
            if ($goos -eq 'windows') {
                $hostData = Get-Content -LiteralPath $hostMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $actualVersion = [version] $hostData.version
                if (($hostChoice.name -eq 'powershell' -and
                    ($actualVersion.Major -ne 5 -or $actualVersion.Minor -ne 1 -or $hostData.edition -cne 'Desktop')) -or
                    ($hostChoice.name -eq 'pwsh' -and
                    ($actualVersion.Major -lt 7 -or $hostData.edition -cne 'Core'))) {
                    throw 'Fixture executed under an unexpected PowerShell host.'
                }
                $hostObserved.version = $hostData.version
                $hostObserved.edition = $hostData.edition
                $hostObserved.home = $hostData.home
            }

            $caseReports.Add([ordered]@{
                launcherMode = $mode
                host = $hostObserved
                expectedChildExitCode = $expectedExitCode
                wrapperExitCode = $processResult.exitCode
                wrapperPath = $wrapperName
                launcher = [ordered]@{
                    selectionFileReceived = $true
                    selectionFileRemoved = $true
                    arguments = @($launcherObserved.arguments)
                }
                selected = [ordered]@{
                    executable = $childBinary
                    arguments = @($expectedArguments)
                    workingDirectory = $workingDirectory
                    environment = [ordered]@{
                        HS_HANDOFF_SELECTED = $expectedSelected
                        HS_HANDOFF_EMPTY = ''
                        HS_HANDOFF_EXIT_CODE = "$expectedExitCode"
                    }
                }
                observed = $observed
                stdout = $processResult.stdout
                stderr = $processResult.stderr
                status = 'passed'
            })
            Write-Host "Passed $wrapperName host=$($hostChoice.name) mode=$mode childExit=$expectedExitCode target=$goos/$goarch"
        }
        }
    }

    $report.cases = @($caseReports)
    $report.status = 'passed'
    Write-Report
    Write-Host "Launcher handoff qualification passed. Report: $reportPath"
}
catch {
    $primaryError = $_
    $report.cases = if (Get-Variable caseReports -ErrorAction SilentlyContinue) { @($caseReports) } else { @() }
    $report.status = 'failed'
    $report.error = ConvertTo-BoundedText -Value $_.Exception.Message
    try { Write-Report }
    catch { Write-Warning 'Handoff report write failed; preserving the original qualification error.' }
    throw $primaryError
}
finally {
    $env:GOTOOLCHAIN = $previousGoToolchain
    $env:GOPROXY = $previousGoProxy
    $env:GOSUMDB = $previousGoSumDB
    try {
        $cleanupTarget = [IO.Path]::GetFullPath($tempRoot)
        if ($cleanupTarget -cne $ownedCleanupTarget -or
            [IO.Path]::GetFileName($cleanupTarget) -cne $ownedTempLeaf -or
            $ownedTempLeaf -notmatch '^hs-tui-launcher-handoff-\d+-[a-f0-9]{32}$') {
            throw 'Refusing cleanup outside the owned handoff fixture directory.'
        }
        if (Test-Path -LiteralPath $cleanupTarget) {
            Remove-Item -LiteralPath $cleanupTarget -Recurse -Force -ErrorAction Stop
        }
        if (Test-Path -LiteralPath $cleanupTarget) { throw 'Handoff fixture cleanup left its temporary directory.' }
        $report.temporaryDirectoryRemoved = $true
        if (-not $primaryError) { Write-Report }
    }
    catch {
        if (-not $primaryError) { throw }
        Write-Warning 'Handoff cleanup failed; preserving the original qualification error.'
    }
}

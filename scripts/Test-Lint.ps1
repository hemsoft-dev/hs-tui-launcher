[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    'ToolOutputDirectory',
    Justification = 'The parameter is consumed inside a collected setup scriptblock so later independent checks can continue.'
)]
param(
    [string] $ToolOutputDirectory = (Join-Path (Join-Path $PSScriptRoot '..') 'bin/lint-tools')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location -LiteralPath $root
try {
    $failures = [System.Collections.Generic.List[string]]::new()
    function Invoke-LintCheck {
        param(
            [Parameter(Mandatory)][string] $Name,
            [Parameter(Mandatory)][scriptblock] $Check
        )

        Write-Host "`n==> $Name"
        try {
            & $Check
            Write-Host "PASS: $Name"
        }
        catch {
            $failures.Add($Name)
            Write-Error -ErrorRecord $_ -ErrorAction Continue
            Write-Host "FAIL: $Name"
        }
    }

    function Get-PlatformKey {
        $architecture = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
            'X64' { 'x64' }
            'Arm64' { 'arm64' }
            default { throw "Unsupported lint-tool architecture: $($_)." }
        }

        if ($IsWindows -and $architecture -eq 'arm64') {
            throw 'Windows ARM64 is unsupported: ShellCheck 0.11.0 does not publish a Windows ARM64 binary, and this repository does not assume x64 emulation.'
        }
        if ($IsWindows) { return "windows-$architecture" }
        if ($IsLinux) { return "linux-$architecture" }
        if ($IsMacOS) { return "macos-$architecture" }
        throw 'Lint tools are supported only on Windows, Linux, and macOS.'
    }

    $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'lint-tools.psd1')
    $setup = [pscustomobject]@{
        ToolSucceeded = $false
        NpmSucceeded = $false
        ShellCheck = $null
        Actionlint = $null
        PSScriptAnalyzer = $null
    }

    Invoke-LintCheck 'Setup pinned lint tools' {
        & (Join-Path $PSScriptRoot 'Install-LintTools.ps1') -OutputDirectory $ToolOutputDirectory
        $platformKey = Get-PlatformKey
        $toolRoot = [System.IO.Path]::GetFullPath($ToolOutputDirectory)
        $suffix = if ($IsWindows) { '.exe' } else { '' }
        $setup.ShellCheck = Join-Path $toolRoot "ShellCheck/$($manifest.ShellCheck.Version)/$platformKey/shellcheck$suffix"
        $setup.Actionlint = Join-Path $toolRoot "Actionlint/$($manifest.Actionlint.Version)/$platformKey/actionlint$suffix"
        $setup.PSScriptAnalyzer = Join-Path $toolRoot "PSScriptAnalyzer/$($manifest.PSScriptAnalyzer.Version)/PSScriptAnalyzer.psd1"
        $setup.ToolSucceeded = $true
    }

    Invoke-LintCheck 'Restore locked npm dependencies' {
        & npm ci --ignore-scripts
        if ($LASTEXITCODE -ne 0) { throw "npm ci failed (exit $LASTEXITCODE)." }
        $setup.NpmSucceeded = $true
    }

    Invoke-LintCheck 'Go formatting (gofmt)' {
        $files = @(git ls-files -- '*.go')
        $diff = @(& gofmt -d @files)
        if ($LASTEXITCODE -ne 0) { throw "gofmt failed (exit $LASTEXITCODE)." }
        if ($diff.Count -gt 0) {
            $diff | Write-Host
            throw 'gofmt found files that require formatting.'
        }
    }

    Invoke-LintCheck 'POSIX shell (ShellCheck)' {
        if (-not $setup.ToolSucceeded) { throw 'ShellCheck cannot run because pinned lint-tool setup failed.' }
        $files = @(git ls-files -- '*.sh')
        & $setup.ShellCheck @files
        if ($LASTEXITCODE -ne 0) { throw "ShellCheck failed (exit $LASTEXITCODE)." }
    }

    Invoke-LintCheck 'PowerShell (PSScriptAnalyzer)' {
        if (-not $setup.ToolSucceeded) { throw 'PSScriptAnalyzer cannot run because pinned lint-tool setup failed.' }
        Import-Module $setup.PSScriptAnalyzer -Force
        $files = @(git ls-files -- '*.ps1' '*.psm1')
        $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
        $findings = @($files | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Settings $settings })
        if ($findings.Count -gt 0) {
            $findings | Format-Table RuleName, Severity, ScriptName, Line, Message -Wrap | Out-String | Write-Host
            throw "PSScriptAnalyzer found $($findings.Count) enforced diagnostic(s)."
        }
    }

    Invoke-LintCheck 'GitHub Actions (actionlint)' {
        if (-not $setup.ToolSucceeded) { throw 'actionlint cannot run because pinned lint-tool setup failed.' }
        # actionlint 1.7.12 has not implemented GitHub's concurrency.queue field.
        # Bind the exception to the exact signed deployment, not arbitrary YAML.
        $contract = Get-Content -LiteralPath (Join-Path $root '.sfl/lint-contract.json') -Raw | ConvertFrom-Json
        $deployment = Get-Content -LiteralPath (Join-Path $root '.sfl/sfl.json') -Raw | ConvertFrom-Json
        $workflow = Join-Path $root '.github/workflows/sfl-pr-review-auto.yml'
        if ($deployment.source -ne $contract.source -or $deployment.version -ne $contract.version -or
            $deployment.sourceSha -ne $contract.sourceSha -or $deployment.tier -ne 'reviewer' -or
            (Get-FileHash -LiteralPath $workflow -Algorithm SHA256).Hash.ToLowerInvariant() -ne $contract.workflowSha256) {
            throw 'SFL generated deployment differs from its independently verified lint contract.'
        }
        $output = @(& $setup.Actionlint -format '{{json .}}' -config-file (Join-Path $root '.github/actionlint.yaml') -shellcheck $setup.ShellCheck)
        $exitCode = $LASTEXITCODE
        if ($exitCode -notin @(0, 1)) { throw "actionlint could not complete (exit $exitCode)." }
        $diagnostics = @($output -join "`n" | ConvertFrom-Json)
        $queueDiagnostic = 'unexpected key "queue" for "concurrency" section. expected one of "cancel-in-progress", "group"'
        $findings = @($diagnostics | Where-Object {
            -not ($_.filepath.Replace('\', '/') -eq '.github/workflows/sfl-pr-review-auto.yml' -and
                $_.kind -eq 'syntax-check' -and $_.message -eq $queueDiagnostic -and
                $_.line -eq 243 -and $_.column -eq 7)
        })
        if ($findings.Count -gt 0) {
            $findings | ConvertTo-Json -Depth 5 | Write-Host
            throw "actionlint found $($findings.Count) enforced diagnostic(s)."
        }
        if ($exitCode -eq 1 -and $diagnostics.Count -eq 0) { throw 'actionlint failed without diagnostic evidence.' }
    }

    Invoke-LintCheck 'SFL actionlint compatibility negative controls' {
        if (-not $setup.ToolSucceeded) { throw 'Controls cannot run because pinned lint-tool setup failed.' }
        & (Join-Path $PSScriptRoot 'Test-SflActionlintContract.ps1') -Actionlint $setup.Actionlint -ShellCheck $setup.ShellCheck
    }

    Invoke-LintCheck 'Markdown (markdownlint-cli2)' {
        if (-not $setup.NpmSucceeded) { throw 'markdownlint-cli2 cannot run because npm dependency setup failed.' }
        $markdownlintPackage = "markdownlint-cli2@$($manifest.MarkdownlintCli2.Version)"
        & npm exec --yes --package=$markdownlintPackage -- markdownlint-cli2
        if ($LASTEXITCODE -ne 0) { throw "markdownlint-cli2 failed (exit $LASTEXITCODE)." }
    }

    Invoke-LintCheck 'YAML, JSON, TypeScript, and JavaScript formatting (Prettier)' {
        if (-not $setup.NpmSucceeded) { throw 'Prettier cannot run because npm dependency setup failed.' }
        $files = @(git ls-files -- '*.yaml' '*.yml' '*.json' '*.jsonc' '*.ts' '*.mjs' '*.js' '*.cjs' '*.jsx')
        & npm exec --no -- prettier --check @files
        if ($LASTEXITCODE -ne 0) { throw "Prettier failed (exit $LASTEXITCODE)." }
    }

    Invoke-LintCheck 'TypeScript static analysis (tsc)' {
        if (-not $setup.NpmSucceeded) { throw 'TypeScript cannot run because npm dependency setup failed.' }
        & npm run typecheck
        if ($LASTEXITCODE -ne 0) { throw "TypeScript type-check failed (exit $LASTEXITCODE)." }
    }

    if ($failures.Count -gt 0) {
        throw "Lint failed: $($failures -join ', ')."
    }
    Write-Host "`nAll formatting and lint checks passed."
}
finally {
    Pop-Location
}

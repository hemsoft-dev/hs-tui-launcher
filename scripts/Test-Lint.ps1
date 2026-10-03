[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location -LiteralPath $root
try {
    & (Join-Path $PSScriptRoot 'Install-LintTools.ps1')

    $architecture = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
        'X64' { 'x64' }
        'Arm64' { 'arm64' }
        default { throw "Unsupported lint-tool architecture: $($_)." }
    }
    $platform = if ($IsWindows) { 'windows' } elseif ($IsLinux) { 'linux' } elseif ($IsMacOS) { 'macos' } else { throw 'Unsupported platform.' }
    $platformKey = "$platform-$architecture"
    $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'lint-tools.psd1')
    $toolRoot = Join-Path $root 'bin/lint-tools'
    $suffix = if ($IsWindows) { '.exe' } else { '' }
    $shellcheck = Join-Path $toolRoot "ShellCheck/$($manifest.ShellCheck.Version)/$platformKey/shellcheck$suffix"
    $actionlint = Join-Path $toolRoot "Actionlint/$($manifest.Actionlint.Version)/$platformKey/actionlint$suffix"
    $pssa = Join-Path $toolRoot "PSScriptAnalyzer/$($manifest.PSScriptAnalyzer.Version)/PSScriptAnalyzer.psd1"

    & npm ci --ignore-scripts
    if ($LASTEXITCODE -ne 0) { throw "npm ci failed (exit $LASTEXITCODE)." }

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
        $files = @(git ls-files -- '*.sh')
        & $shellcheck @files
        if ($LASTEXITCODE -ne 0) { throw "ShellCheck failed (exit $LASTEXITCODE)." }
    }

    Invoke-LintCheck 'PowerShell (PSScriptAnalyzer)' {
        Import-Module $pssa -Force
        $files = @(git ls-files -- '*.ps1' '*.psm1')
        $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
        $findings = @($files | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Settings $settings })
        if ($findings.Count -gt 0) {
            $findings | Format-Table RuleName, Severity, ScriptName, Line, Message -Wrap | Out-String | Write-Host
            throw "PSScriptAnalyzer found $($findings.Count) enforced diagnostic(s)."
        }
    }

    Invoke-LintCheck 'GitHub Actions (actionlint)' {
        & $actionlint -config-file (Join-Path $root '.github/actionlint.yaml') -shellcheck $shellcheck
        if ($LASTEXITCODE -ne 0) { throw "actionlint failed (exit $LASTEXITCODE)." }
    }

    Invoke-LintCheck 'Markdown (markdownlint-cli2)' {
        $markdownlintPackage = "markdownlint-cli2@$($manifest.MarkdownlintCli2.Version)"
        & npm exec --yes --package=$markdownlintPackage -- markdownlint-cli2
        if ($LASTEXITCODE -ne 0) { throw "markdownlint-cli2 failed (exit $LASTEXITCODE)." }
    }

    Invoke-LintCheck 'YAML, JSON, TypeScript, and JavaScript formatting (Prettier)' {
        $files = @(git ls-files -- '*.yaml' '*.yml' '*.json' '*.jsonc' '*.ts' '*.mjs')
        & npm exec --no -- prettier --check @files
        if ($LASTEXITCODE -ne 0) { throw "Prettier failed (exit $LASTEXITCODE)." }
    }

    Invoke-LintCheck 'TypeScript static analysis (tsc)' {
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

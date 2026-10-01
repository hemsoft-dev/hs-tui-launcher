$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$isWindowsPlatform = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$toolDirectory = Join-Path $repositoryRoot "bin/security-tools"
$pythonEnvironment = Join-Path $toolDirectory "python"
New-Item -ItemType Directory -Force -Path $toolDirectory | Out-Null

$tools = @(
    "golang.org/x/vuln/cmd/govulncheck@v1.8.0",
    "github.com/zricethezav/gitleaks/v8@v8.30.1",
    "github.com/google/osv-scanner/v2/cmd/osv-scanner@v2.4.0"
)

$previousGoBin = $env:GOBIN
try {
    $env:GOBIN = $toolDirectory
    foreach ($tool in $tools) {
        Write-Host "Installing $tool"
        & go install $tool
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install $tool (exit $LASTEXITCODE)."
        }
    }
} finally {
    $env:GOBIN = $previousGoBin
}

Write-Host "Installing semgrep==1.178.0 into an isolated environment"
& python -m venv --clear $pythonEnvironment
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create the Semgrep environment (exit $LASTEXITCODE)."
}

$environmentPython = if ($isWindowsPlatform) {
    Join-Path $pythonEnvironment "Scripts/python.exe"
} else {
    Join-Path $pythonEnvironment "bin/python"
}
& $environmentPython -m pip install --disable-pip-version-check --no-input "semgrep==1.178.0"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install semgrep (exit $LASTEXITCODE)."
}

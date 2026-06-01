[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $AppArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSCommandPath
$goCommand = Get-Command go.exe -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $goCommand) {
    throw 'Go is required to run hs-tui-launcher, but go.exe was not found on PATH.'
}

Push-Location -LiteralPath $repoRoot
try {
    & $goCommand.Source run . @AppArgs
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

$global:LASTEXITCODE = $exitCode
return

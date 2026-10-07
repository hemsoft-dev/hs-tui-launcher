<#
.SYNOPSIS
Installs the checksum-pinned portable PowerShell 7.2 host for Windows handoff tests.
.DESCRIPTION
Uses only the ignored repository bin directory. Does not modify PATH, installed
PowerShell versions, or machine settings. The harness asserts the actual host version.
#>
#requires -Version 7.5
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'The portable handoff host is a Windows-only test prerequisite.' }
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cacheRoot = Join-Path $repositoryRoot 'bin'
$runtimeRoot = Join-Path $cacheRoot 'handoff-pwsh-7.2.24'
$archive = Join-Path $cacheRoot 'PowerShell-7.2.24-win-x64.zip'
$expectedHash = 'a1ccb6d8ad52f917470a136c3752af4465f261bcbe570cf44f52aa69ae6e867e'
$marker = Join-Path $runtimeRoot '.handoff-archive-sha256'
if (Test-Path -LiteralPath $runtimeRoot) {
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or
        (Get-Content -LiteralPath $marker -Raw).Trim() -cne $expectedHash) {
        throw 'Refusing to overwrite an unowned portable PowerShell directory.'
    }
}
[void][IO.Directory]::CreateDirectory($cacheRoot)
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    Invoke-WebRequest -Uri 'https://github.com/PowerShell/PowerShell/releases/download/v7.2.24/PowerShell-7.2.24-win-x64.zip' -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedHash) {
    throw 'Portable PowerShell archive checksum does not match the published 7.2.24 hash.'
}
Expand-Archive -LiteralPath $archive -DestinationPath $runtimeRoot -Force
Set-Content -LiteralPath $marker -Value $expectedHash -Encoding utf8NoBOM
$executable = Join-Path $runtimeRoot 'pwsh.exe'
$version = & $executable -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
if ($LASTEXITCODE -ne 0 -or $version -cne '7.2.24') { throw 'Portable PowerShell did not report version 7.2.24.' }
Write-Host "Verified portable handoff host: $executable"

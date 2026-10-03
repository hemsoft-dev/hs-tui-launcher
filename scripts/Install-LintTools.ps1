[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path $PSScriptRoot '..\bin\lint-tools')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-PlatformKey {
    $architecture = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
        'X64' { 'x64' }
        'Arm64' { 'arm64' }
        default { throw "Unsupported lint-tool architecture: $($_)." }
    }

    if ($IsWindows) { return "windows-$architecture" }
    if ($IsLinux) { return "linux-$architecture" }
    if ($IsMacOS) { return "macos-$architecture" }
    throw 'Lint tools are supported only on Windows, Linux, and macOS.'
}

function Invoke-VerifiedDownload {
    param(
        [Parameter(Mandatory)][string] $Uri,
        [Parameter(Mandatory)][string] $Destination,
        [Parameter(Mandatory)][string] $Sha256
    )

    Invoke-WebRequest -Uri $Uri -OutFile $Destination
    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Sha256) {
        throw "Checksum mismatch for '$Uri': expected $Sha256, got $actual."
    }
}

function Expand-ToolArchive {
    param(
        [Parameter(Mandatory)][string] $Archive,
        [Parameter(Mandatory)][string] $Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    if ($Archive.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase)) {
        Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
        return
    }

    & tar -xzf $Archive -C $Destination
    if ($LASTEXITCODE -ne 0) {
        throw "tar failed to extract '$Archive' (exit $LASTEXITCODE)."
    }
}

$manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'lint-tools.psd1')
$platform = Get-PlatformKey
$root = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $root -Force | Out-Null
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "hs-tui-lint-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temp | Out-Null

try {
    $pssaRoot = Join-Path $root "PSScriptAnalyzer/$($manifest.PSScriptAnalyzer.Version)"
    $pssaManifest = Join-Path $pssaRoot 'PSScriptAnalyzer.psd1'
    if (-not (Test-Path -LiteralPath $pssaManifest -PathType Leaf)) {
        $package = Join-Path $temp 'PSScriptAnalyzer.zip'
        Invoke-VerifiedDownload -Uri $manifest.PSScriptAnalyzer.Uri -Destination $package `
            -Sha256 $manifest.PSScriptAnalyzer.Sha256
        Expand-ToolArchive -Archive $package -Destination $pssaRoot
    }

    foreach ($toolName in @('ShellCheck', 'Actionlint')) {
        $tool = $manifest[$toolName]
        if (-not $tool.Assets.ContainsKey($platform)) {
            throw "$toolName $($tool.Version) has no pinned asset for $platform."
        }
        $asset = $tool.Assets[$platform]
        $executableName = if ($toolName -eq 'ShellCheck') { 'shellcheck' } else { 'actionlint' }
        if ($IsWindows) { $executableName += '.exe' }
        $toolRoot = Join-Path $root "$toolName/$($tool.Version)/$platform"
        $executable = Join-Path $toolRoot $executableName
        if (Test-Path -LiteralPath $executable -PathType Leaf) { continue }

        $archive = Join-Path $temp $asset.Name
        $repository = if ($toolName -eq 'ShellCheck') { 'koalaman/shellcheck' } else { 'rhysd/actionlint' }
        $uri = "https://github.com/$repository/releases/download/v$($tool.Version)/$($asset.Name)"
        Invoke-VerifiedDownload -Uri $uri -Destination $archive -Sha256 $asset.Sha256
        $expanded = Join-Path $temp "$toolName-expanded"
        Expand-ToolArchive -Archive $archive -Destination $expanded
        $source = Get-ChildItem -LiteralPath $expanded -Recurse -File |
            Where-Object Name -eq $executableName |
            Select-Object -First 1
        if (-not $source) { throw "$executableName was not present in '$($asset.Name)'." }
        New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
        Copy-Item -LiteralPath $source.FullName -Destination $executable
        if (-not $IsWindows) {
            & chmod +x $executable
            if ($LASTEXITCODE -ne 0) { throw "chmod failed for '$executable'." }
        }
    }
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Pinned lint tools are available under '$root'."

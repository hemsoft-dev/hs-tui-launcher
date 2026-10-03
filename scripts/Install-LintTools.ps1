[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path (Join-Path $PSScriptRoot '..') 'bin/lint-tools')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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

function Test-ExecutableCache {
    param(
        [Parameter(Mandatory)][string] $Directory,
        [Parameter(Mandatory)][string] $ExecutableName
    )

    $executable = Join-Path $Directory $ExecutableName
    if (-not (Test-Path -LiteralPath (Join-Path $Directory '.complete') -PathType Leaf) -or
        -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        return $false
    }
    try {
        & $executable --version *> $null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Test-PSScriptAnalyzerCache {
    param(
        [Parameter(Mandatory)][string] $Directory,
        [Parameter(Mandatory)][string] $Version
    )

    $moduleManifest = Join-Path $Directory 'PSScriptAnalyzer.psd1'
    if (-not (Test-Path -LiteralPath (Join-Path $Directory '.complete') -PathType Leaf) -or
        -not (Test-Path -LiteralPath $moduleManifest -PathType Leaf)) {
        return $false
    }
    try {
        # Validate in a child process so importing a staged module cannot leave
        # PowerShell's module-analysis cache bound to a directory that is moved.
        $pwsh = [Environment]::ProcessPath
        $quotedManifest = "'$($moduleManifest.Replace("'", "''"))'"
        $quotedVersion = "'$($Version.Replace("'", "''"))'"
        $validationCommand = "`$ErrorActionPreference = 'Stop'; " +
            "`$module = Import-Module $quotedManifest -Force -PassThru -ErrorAction Stop; " +
            "if (`$module.Version.ToString() -ne $quotedVersion) { exit 1 }; " +
            'Get-Command Invoke-ScriptAnalyzer -ErrorAction Stop | Out-Null'
        & $pwsh -NoProfile -NonInteractive -Command $validationCommand *> $null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Publish-ToolDirectory {
    param(
        [Parameter(Mandatory)][string] $StagingDirectory,
        [Parameter(Mandatory)][string] $Destination
    )

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    Move-Item -LiteralPath $StagingDirectory -Destination $Destination
}

function Enter-ToolCacheLock {
    param(
        [Parameter(Mandatory)][string] $Root,
        [int] $TimeoutSeconds = 300
    )

    # Keep the lock file in place: deleting it after releasing the handle can
    # race with the next waiter and create two independently locked files.
    $lockPath = Join-Path $Root '.install.lock'
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ($true) {
        try {
            return [System.IO.File]::Open(
                $lockPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
        }
        catch [System.IO.IOException] {
            if ([DateTime]::UtcNow -ge $deadline) {
                throw "Timed out waiting for the lint-tool cache lock '$lockPath'."
            }
            Start-Sleep -Milliseconds 200
        }
    }
}

$manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'lint-tools.psd1')
$platform = Get-PlatformKey
$root = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $root -Force | Out-Null
$cacheLock = Enter-ToolCacheLock -Root $root
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "hs-tui-lint-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temp | Out-Null

try {
    $pssaRoot = Join-Path $root "PSScriptAnalyzer/$($manifest.PSScriptAnalyzer.Version)"
    if (-not (Test-PSScriptAnalyzerCache -Directory $pssaRoot -Version $manifest.PSScriptAnalyzer.Version)) {
        $package = Join-Path $temp 'PSScriptAnalyzer.zip'
        Invoke-VerifiedDownload -Uri $manifest.PSScriptAnalyzer.Uri -Destination $package `
            -Sha256 $manifest.PSScriptAnalyzer.Sha256
        $stage = Join-Path (Split-Path -Parent $pssaRoot) ".staging-$([guid]::NewGuid().ToString('N'))"
        try {
            Expand-ToolArchive -Archive $package -Destination $stage
            New-Item -ItemType File -Path (Join-Path $stage '.complete') | Out-Null
            if (-not (Test-PSScriptAnalyzerCache -Directory $stage -Version $manifest.PSScriptAnalyzer.Version)) {
                throw 'The staged PSScriptAnalyzer module failed completion validation.'
            }
            Publish-ToolDirectory -StagingDirectory $stage -Destination $pssaRoot
        }
        finally {
            Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        }
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
        if (Test-ExecutableCache -Directory $toolRoot -ExecutableName $executableName) { continue }

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

        $stage = Join-Path (Split-Path -Parent $toolRoot) ".staging-$([guid]::NewGuid().ToString('N'))"
        try {
            New-Item -ItemType Directory -Path $stage -Force | Out-Null
            $stagedExecutable = Join-Path $stage $executableName
            Copy-Item -LiteralPath $source.FullName -Destination $stagedExecutable
            if (-not $IsWindows) {
                & chmod +x $stagedExecutable
                if ($LASTEXITCODE -ne 0) { throw "chmod failed for '$stagedExecutable'." }
            }
            New-Item -ItemType File -Path (Join-Path $stage '.complete') | Out-Null
            if (-not (Test-ExecutableCache -Directory $stage -ExecutableName $executableName)) {
                throw "The staged $toolName executable failed completion validation."
            }
            Publish-ToolDirectory -StagingDirectory $stage -Destination $toolRoot
        }
        finally {
            Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    $cacheLock.Dispose()
}

Write-Host "Pinned lint tools are available under '$root'."

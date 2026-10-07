[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $AppArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSCommandPath
$nativeLauncher = Join-Path $repoRoot 'hs-tui-launcher.exe'
$launcherCommand = $null
$launcherPrefix = @()

if (Test-Path -LiteralPath $nativeLauncher -PathType Leaf) {
    $launcherCommand = $nativeLauncher
}
else {
    $goCommand = @('go.exe', 'go') |
        ForEach-Object { Get-Command $_ -CommandType Application -ErrorAction SilentlyContinue } |
        Select-Object -First 1

    if (-not $goCommand) {
        throw 'hs-tui-launcher.exe is missing and no Go executable was found on PATH.'
    }

    $launcherCommand = $goCommand.Source
    $launcherPrefix = @('run', '.')
}

function Test-NonInteractiveRequest {
    param([string[]] $Arguments)

    foreach ($argument in $Arguments) {
        if ($argument -in @('--print-config', '--help', '-h', 'help')) {
            return $true
        }
    }

    return $false
}

function Set-ProcessEnvironmentValue {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Sets only a process-local value owned by the temporary environment snapshot.'
    )]
    param([string] $Name, [AllowEmptyString()][string] $Value)

    if ($Value -eq '' -and [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        # Windows PowerShell's provider and .NET Framework erase empty values.
        # The native API preserves an empty string separately from an absent name.
        if (-not ('HsTuiLauncherProcessEnvironment' -as [type])) {
            Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class HsTuiLauncherProcessEnvironment {
    [DllImport("kernel32.dll", EntryPoint = "SetEnvironmentVariableW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetValue(string name, string value);
}
'@
        }
        if (-not [HsTuiLauncherProcessEnvironment]::SetValue($Name, $Value)) {
            throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
    }
    else {
        Set-Item -LiteralPath "Env:$Name" -Value $Value
    }
}

function Set-TemporaryEnvironment {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseLiteralInitializerForHashtable',
        '',
        Justification = 'An explicit platform comparer is required to preserve case-sensitive Unix environment names.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This helper changes only process-local variables and always restores them.'
    )]
    param([string[]] $Entries)

    $comparer = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        [StringComparer]::OrdinalIgnoreCase
    }
    else {
        [StringComparer]::Ordinal
    }
    $previousValues = [hashtable]::new($comparer)
    $initialValues = [hashtable]::new($comparer)
    foreach ($pair in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) {
        $initialValues[$pair.Key] = $pair.Value
    }
    foreach ($entry in $Entries) {
        $name, $value = $entry -split '=', 2
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        if (-not $previousValues.ContainsKey($name)) {
            # Enumeration preserves empty strings on .NET Framework, whose
            # single-value getter otherwise returns null for both empty and absent.
            $previousValues[$name] = $initialValues[$name]
        }
        Set-ProcessEnvironmentValue -Name $name -Value $value
    }

    return $previousValues
}

function Restore-Environment {
    param([hashtable] $PreviousValues)

    foreach ($name in $PreviousValues.Keys) {
        $value = $PreviousValues[$name]
        if ($null -eq $value) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            continue
        }

        Set-ProcessEnvironmentValue -Name $name -Value $value
    }
}

function ConvertFrom-SelectionJson {
    param([string] $Json)

    try {
        $selection = $Json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Selection file is not valid JSON: $($_.Exception.Message)"
    }

    if ($null -eq $selection -or $selection -isnot [pscustomobject]) {
        throw 'Selection file has invalid shape: expected a JSON object.'
    }

    return $selection
}

function Assert-SelectionShape {
    param([pscustomobject] $Selection)

    $allowedProperties = @('name', 'executable', 'args', 'working_dir', 'env')
    $propertyNames = @($Selection.PSObject.Properties.Name)

    foreach ($propertyName in $propertyNames) {
        if ($propertyName -notin $allowedProperties) {
            throw "Selection file has invalid shape: unsupported property '$propertyName'."
        }
    }

    if ($propertyNames -notcontains 'name' -or $Selection.name -isnot [string] -or [string]::IsNullOrWhiteSpace($Selection.name)) {
        throw 'Selection file has invalid shape: name is required.'
    }

    if ($propertyNames -notcontains 'executable' -or $Selection.executable -isnot [string] -or [string]::IsNullOrWhiteSpace($Selection.executable)) {
        throw 'Selection file has invalid shape: executable is required.'
    }

    if ($propertyNames -contains 'working_dir' -and $null -ne $Selection.working_dir -and $Selection.working_dir -isnot [string]) {
        throw 'Selection file has invalid shape: working_dir must be a string.'
    }

    if ($propertyNames -contains 'args' -and $null -ne $Selection.args -and $Selection.args -isnot [array] -and $Selection.args -isnot [string]) {
        throw 'Selection file has invalid shape: args must be a JSON array of strings.'
    }

    if ($propertyNames -contains 'args') {
        foreach ($argument in @($Selection.args)) {
            if ($argument -isnot [string]) {
                throw 'Selection file has invalid shape: args must be a JSON array of strings.'
            }
        }
    }

    if ($propertyNames -contains 'env' -and $null -ne $Selection.env -and $Selection.env -isnot [array] -and $Selection.env -isnot [string]) {
        throw 'Selection file has invalid shape: env must be a JSON array of strings.'
    }

    if ($propertyNames -contains 'env') {
        foreach ($entry in @($Selection.env)) {
            if ($entry -isnot [string]) {
                throw 'Selection file has invalid shape: env must be a JSON array of strings.'
            }
        }
    }
}

function ConvertTo-WindowsNativeArgument {
    param([AllowEmptyString()][string] $Argument)

    # Microsoft CRT argv parsing doubles backslashes before quotes and the
    # closing delimiter. Quote every argument so empty strings survive too.
    $quoted = New-Object System.Text.StringBuilder
    [void] $quoted.Append('"')
    $slashes = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') {
            $slashes++
            continue
        }
        if ($character -eq '"') {
            [void] $quoted.Append(('\' * (2 * $slashes + 1)))
        }
        else {
            [void] $quoted.Append(('\' * $slashes))
        }
        [void] $quoted.Append($character)
        $slashes = 0
    }
    [void] $quoted.Append(('\' * (2 * $slashes)))
    [void] $quoted.Append('"')
    return $quoted.ToString()
}

function Invoke-SelectedCommand {
    param([string] $Executable, [AllowEmptyCollection()][string[]] $Arguments)

    if ($PSVersionTable.PSVersion.Major -lt 7 -and
        [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $nativeExecutable = $null
        if ([IO.Path]::IsPathRooted($Executable) -or $Executable.Contains('\') -or $Executable.Contains('/')) {
            $item = Get-Item -LiteralPath $Executable -Force -ErrorAction Stop
            if ($item -is [IO.FileInfo] -and $item.Extension -ieq '.exe') {
                $nativeExecutable = $item.FullName
            }
        }
        else {
            $command = Get-Command ([WildcardPattern]::Escape($Executable)) -ErrorAction Stop | Select-Object -First 1
            if ($command.CommandType -eq 'Application' -and
                [IO.Path]::GetExtension($command.Source) -ieq '.exe') {
                $nativeExecutable = $command.Source
            }
        }
        if ($nativeExecutable) {
            $start = New-Object System.Diagnostics.ProcessStartInfo
            $start.FileName = $nativeExecutable
            $start.UseShellExecute = $false
            $start.WorkingDirectory = (Get-Location).ProviderPath
            $start.Arguments = (@($Arguments | ForEach-Object {
                ConvertTo-WindowsNativeArgument -Argument $_
            }) -join ' ')
            # Inherit the console/stdio handles. Redirecting would change CLI
            # interactivity and stdin ownership after the TUI exits.
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $start
            try {
                if (-not $process.Start()) { throw "Could not start '$Executable'." }
                $process.WaitForExit()
                $script:exitCode = $process.ExitCode
            }
            finally { $process.Dispose() }
            return
        }
    }

    & $Executable @Arguments
    if ($null -ne $LASTEXITCODE) { $script:exitCode = $LASTEXITCODE }
    else { $script:exitCode = 0 }
}

function Invoke-Selection {
    param([pscustomobject] $Selection)

    Assert-SelectionShape -Selection $Selection

    $previousEnvironment = @{}
    $locationPushed = $false
    $propertyNames = @($Selection.PSObject.Properties.Name)

    try {
        if ($propertyNames -contains 'env' -and $Selection.env) {
            $previousEnvironment = Set-TemporaryEnvironment -Entries @($Selection.env)
        }

        if ($propertyNames -contains 'working_dir' -and -not [string]::IsNullOrWhiteSpace($Selection.working_dir)) {
            Push-Location -LiteralPath $Selection.working_dir
            $locationPushed = $true
        }

        $arguments = @()
        if ($propertyNames -contains 'args') {
            $arguments = @($Selection.args)
        }

        Invoke-SelectedCommand -Executable ([string] $Selection.executable) -Arguments $arguments
    }
    finally {
        if ($locationPushed) {
            Pop-Location
        }
        Restore-Environment -PreviousValues $previousEnvironment
    }
}

$exitCode = 0
$selectionFile = $null

Push-Location -LiteralPath $repoRoot
try {
    if (Test-NonInteractiveRequest -Arguments $AppArgs) {
        & $launcherCommand @launcherPrefix @AppArgs
        $exitCode = $LASTEXITCODE
    }
    else {
        # The Go TUI writes the selected command here and exits before PowerShell launches it.
        # Keeping launch ownership in this wrapper avoids child processes inheriting TUI terminal state.
        $selectionFile = New-TemporaryFile
        & $launcherCommand @launcherPrefix --selection-file $selectionFile.FullName @AppArgs
        $exitCode = $LASTEXITCODE
    }
}
finally {
    Pop-Location
}

try {
    if ($exitCode -eq 0 -and $selectionFile -and (Test-Path -LiteralPath $selectionFile.FullName)) {
        $selectionJson = Get-Content -LiteralPath $selectionFile.FullName -Raw -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($selectionJson)) {
            $selection = ConvertFrom-SelectionJson -Json $selectionJson
            Invoke-Selection -Selection $selection
        }
    }
}
finally {
    if ($selectionFile) {
        Remove-Item -LiteralPath $selectionFile.FullName -Force -ErrorAction SilentlyContinue
    }
}

$global:LASTEXITCODE = $exitCode
return

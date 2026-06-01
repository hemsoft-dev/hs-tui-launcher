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

function Test-NonInteractiveRequest {
    param([string[]] $Arguments)

    foreach ($argument in $Arguments) {
        if ($argument -in @('--print-config', '--help', '-h', 'help')) {
            return $true
        }
    }

    return $false
}

function Set-TemporaryEnvironment {
    param([string[]] $Entries)

    $previousValues = @{}
    foreach ($entry in $Entries) {
        $name, $value = $entry -split '=', 2
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $previousValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        Set-Item -LiteralPath "Env:$name" -Value $value
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

        Set-Item -LiteralPath "Env:$name" -Value $value
    }
}

function Invoke-Selection {
    param([pscustomobject] $Selection)

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

        Invoke-Expression -Command ([string] $Selection.command)
        if ($null -ne $LASTEXITCODE) {
            $script:exitCode = $LASTEXITCODE
        }
        else {
            $script:exitCode = 0
        }
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
        & $goCommand.Source run . @AppArgs
        $exitCode = $LASTEXITCODE
    }
    else {
        $selectionFile = New-TemporaryFile
        & $goCommand.Source run . --selection-file $selectionFile.FullName @AppArgs
        $exitCode = $LASTEXITCODE
    }
}
finally {
    Pop-Location
}

if ($exitCode -eq 0 -and $selectionFile -and (Test-Path -LiteralPath $selectionFile.FullName)) {
    $selectionJson = Get-Content -LiteralPath $selectionFile.FullName -Raw
    if (-not [string]::IsNullOrWhiteSpace($selectionJson)) {
        $selection = $selectionJson | ConvertFrom-Json
        Invoke-Selection -Selection $selection
    }
}

if ($selectionFile) {
    Remove-Item -LiteralPath $selectionFile.FullName -Force -ErrorAction SilentlyContinue
}

$global:LASTEXITCODE = $exitCode
return

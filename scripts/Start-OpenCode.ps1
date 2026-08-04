[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Provider,

    [Parameter(Mandatory = $true, Position = 1)]
    [string] $Model,

    [string] $Variant = 'default',

    [string] $StateFile = (Join-Path $HOME '.local\state\opencode\model.json'),

    [switch] $NoLaunch,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $OpenCodeArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Ensure-Property {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Object,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value
    )

    if ($Object.PSObject.Properties.Name -notcontains $Name) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
        return
    }

    if ($null -eq $Object.PSObject.Properties[$Name].Value) {
        $Object.PSObject.Properties[$Name].Value = $Value
    }
}

function Read-ModelState {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            recent   = @()
            favorite = @()
            variant  = [pscustomobject]@{}
        }
    }

    $content = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        return [pscustomobject]@{
            recent   = @()
            favorite = @()
            variant  = [pscustomobject]@{}
        }
    }

    return $content | ConvertFrom-Json
}

$state = Read-ModelState -Path $StateFile
Ensure-Property -Object $state -Name recent -Value @()
Ensure-Property -Object $state -Name favorite -Value @()
Ensure-Property -Object $state -Name variant -Value ([pscustomobject]@{})

$selected = [pscustomobject]@{
    providerID = $Provider
    modelID    = $Model
}

$state.recent = @($selected) + @(
    @($state.recent) | Where-Object {
        $_.providerID -ne $Provider -or $_.modelID -ne $Model
    }
)

$modelKey = "$Provider/$Model"
$state.variant | Add-Member -NotePropertyName $modelKey -NotePropertyValue $Variant -Force

$stateDirectory = Split-Path -Parent $StateFile
if (-not [string]::IsNullOrWhiteSpace($stateDirectory)) {
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
}
$state | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $StateFile -Encoding utf8

$modelArgument = "$Provider/$Model"
$arguments = @('--model', $modelArgument) + @($OpenCodeArgs)
if ($NoLaunch) {
    Write-Output "opencode $($arguments -join ' ')"
    return
}

& opencode @arguments
exit $LASTEXITCODE

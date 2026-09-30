[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$audioPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets/done.mp3'
if (-not (Test-Path -LiteralPath $audioPath -PathType Leaf)) {
    throw 'Completion audio is missing: assets/done.mp3'
}

# Play without opening a media-player window. No network or paid API calls.
if ($IsMacOS) {
    $player = Get-Command afplay -CommandType Application -ErrorAction Stop
    & $player.Path $audioPath
}
else {
    $player = Get-Command ffplay -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $player) { throw 'Completion audio requires ffplay on Windows or Linux.' }
    & $player.Path -nodisp -autoexit -loglevel error $audioPath
}
if ($LASTEXITCODE -ne 0) { throw "Completion audio player failed with exit code $LASTEXITCODE." }

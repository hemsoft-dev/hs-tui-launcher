[CmdletBinding()]
param(
    [string] $Prompt,

    [string] $Resolution,

    [string] $AspectRatio,

    [string] $OutputDirectory,

    [switch] $DryRun,

    [switch] $Force,

    [switch] $NoOpen
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$model = 'bytedance-seed/seedream-5-0-pro'
$endpoint = 'https://openrouter.ai/api/v1/images'
$allowedResolutions = @('1K', '2K')
$allowedAspectRatios = @(
    '1:1', '1:2', '2:1', '2:3', '3:2', '3:4', '4:3', '4:5', '5:4',
    '9:16', '16:9', '9:19.5', '19.5:9', '9:20', '20:9', '9:21', '21:9', 'auto'
)

function Resolve-InteractiveChoice {
    param(
        [string] $Value,
        [Parameter(Mandatory = $true)]
        [string] $Default,
        [Parameter(Mandatory = $true)]
        [string[]] $Allowed,
        [Parameter(Mandatory = $true)]
        [string] $Label
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        $Value = Read-Host "$Label [$Default]"
    }
    if ([string]::IsNullOrWhiteSpace($Value)) {
        $Value = $Default
    }
    $resolvedValue = $Allowed | Where-Object { $_ -ieq $Value } | Select-Object -First 1
    if ($null -eq $resolvedValue) {
        throw "$Label must be one of: $($Allowed -join ', ')"
    }

    return $resolvedValue
}

function Resolve-ImagePrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw 'An image prompt is required.'
    }

    $candidatePath = $Value.Trim()
    if ($candidatePath.Length -ge 2) {
        $firstCharacter = $candidatePath[0]
        $lastCharacter = $candidatePath[$candidatePath.Length - 1]
        if (($firstCharacter -eq '"' -and $lastCharacter -eq '"') -or
            ($firstCharacter -eq "'" -and $lastCharacter -eq "'")) {
            $candidatePath = $candidatePath.Substring(1, $candidatePath.Length - 2)
        }
    }
    $candidatePath = [Environment]::ExpandEnvironmentVariables($candidatePath)

    if (-not (Test-Path -LiteralPath $candidatePath)) {
        return $Value
    }
    if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
        throw "Image prompt path must point to a file: $candidatePath"
    }

    try {
        $filePrompt = Get-Content -Raw -Encoding utf8 -LiteralPath $candidatePath
    }
    catch {
        throw "Could not read image prompt file '$candidatePath': $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace($filePrompt)) {
        throw "Image prompt file is empty: $candidatePath"
    }

    return $filePrompt.Trim()
}

if ([string]::IsNullOrWhiteSpace($Prompt)) {
    $Prompt = Read-Host 'Describe the image or paste a prompt file path'
}
$Prompt = Resolve-ImagePrompt -Value $Prompt

$Resolution = Resolve-InteractiveChoice `
    -Value $Resolution `
    -Default '1K' `
    -Allowed $allowedResolutions `
    -Label 'Resolution'
$AspectRatio = Resolve-InteractiveChoice `
    -Value $AspectRatio `
    -Default '1:1' `
    -Allowed $allowedAspectRatios `
    -Label 'Aspect ratio'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $picturesDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyPictures)
    if ([string]::IsNullOrWhiteSpace($picturesDirectory)) {
        $picturesDirectory = (Get-Location).Path
    }
    $OutputDirectory = Join-Path $picturesDirectory 'OpenRouter\Seedream'
}

$estimatedCost = if ($Resolution -eq '2K') { 0.09 } else { 0.045 }
$requestBody = [ordered]@{
    model        = $model
    prompt       = $Prompt
    resolution   = $Resolution
    aspect_ratio = $AspectRatio
}

if ($DryRun) {
    [pscustomobject]@{
        Endpoint         = $endpoint
        Model            = $model
        Resolution       = $Resolution
        AspectRatio      = $AspectRatio
        EstimatedCostUSD = $estimatedCost
        OutputDirectory  = $OutputDirectory
        PromptLength     = $Prompt.Length
    } | ConvertTo-Json -Compress
    return
}

$apiKey = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY')
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw 'OPENROUTER_API_KEY is not set.'
}

if (-not $Force) {
    Write-Information `
        ('Estimated generation cost: ${0:0.000} ({1})' -f $estimatedCost, $Resolution) `
        -InformationAction Continue
    $confirmation = Read-Host 'Generate this image? [y/N]'
    if ($confirmation -notin @('y', 'yes')) {
        Write-Output 'Image generation cancelled.'
        return
    }
}

$headers = @{
    Authorization = "Bearer $apiKey"
}

try {
    $response = Invoke-RestMethod `
        -Uri $endpoint `
        -Method Post `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body ($requestBody | ConvertTo-Json -Compress)
}
catch {
    $apiMessage = $_.Exception.Message
    $errorDetails = $_.ErrorDetails
    if ($null -ne $errorDetails -and -not [string]::IsNullOrWhiteSpace($errorDetails.Message)) {
        $errorResponse = $errorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -ne $errorResponse -and $errorResponse.PSObject.Properties.Name -contains 'error') {
            if ($null -ne $errorResponse.error -and
                $errorResponse.error.PSObject.Properties.Name -contains 'message' -and
                -not [string]::IsNullOrWhiteSpace($errorResponse.error.message)) {
                $apiMessage = $errorResponse.error.message
            }
        }
    }
    throw "OpenRouter image generation failed: $apiMessage"
}

if ($null -eq $response -or $response.PSObject.Properties.Name -notcontains 'data') {
    throw 'OpenRouter returned no image data.'
}
$image = @($response.data)[0]
if ($null -eq $image -or
    $image.PSObject.Properties.Name -notcontains 'b64_json' -or
    [string]::IsNullOrWhiteSpace($image.b64_json)) {
    throw 'OpenRouter returned no image data.'
}

$mediaType = if ($image.PSObject.Properties.Name -contains 'media_type') {
    $image.media_type
}
else {
    'image/png'
}
$extension = switch ($mediaType) {
    'image/jpeg' { 'jpg' }
    'image/webp' { 'webp' }
    'image/svg+xml' { 'svg' }
    default { 'png' }
}

try {
    $imageBytes = [Convert]::FromBase64String($image.b64_json)
}
catch {
    throw "OpenRouter returned invalid base64 image data: $($_.Exception.Message)"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$outputPath = Join-Path $OutputDirectory "seedream-5-0-pro-$timestamp.$extension"
if (Test-Path -LiteralPath $outputPath) {
    $suffix = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $outputPath = Join-Path $OutputDirectory "seedream-5-0-pro-$timestamp-$suffix.$extension"
}
[IO.File]::WriteAllBytes($outputPath, $imageBytes)

Write-Output "Saved image: $outputPath"
if ($response.PSObject.Properties.Name -contains 'usage' -and
    $null -ne $response.usage -and
    $response.usage.PSObject.Properties.Name -contains 'cost' -and
    $null -ne $response.usage.cost) {
    Write-Output ('OpenRouter reported cost: ${0:0.000000}' -f [decimal]$response.usage.cost)
}

if (-not $NoOpen) {
    Start-Process -FilePath $outputPath
}

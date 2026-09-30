[CmdletBinding()]
param(
    [string] $Prompt,
    [string] $Voice,
    [string] $VoicesFile = (Join-Path $HOME '.config/hs-tui-launcher/seed-audio-voices.json'),
    [string] $SaveVoice,
    [string] $ReferenceAudio,
    [string] $ReferenceText,
    [string] $SpeakerId,
    [string] $OutputDirectory,
    [switch] $Consent,
    [switch] $ListVoices,
    [switch] $PromptOnly,
    [switch] $DryRun,
    [switch] $Force,
    [switch] $NoOpen
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$model = 'bytedance-seed/seed-audio-1-0'
$endpoint = 'https://openrouter.ai/api/v1/audio/speech'

function Read-VoiceRegistry {
    param([string] $RegistryPath)
    $path = if (Test-Path -LiteralPath $RegistryPath -PathType Leaf) {
        $RegistryPath
    }
    else {
        Join-Path $PSScriptRoot 'seed-audio-voices.json'
    }
    $registry = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
    if ($null -eq $registry -or $registry.version -ne 1 -or $registry.voices -isnot [array]) {
        throw 'Voice registry must contain version 1 and a voices array.'
    }
    $names = @{}
    foreach ($voiceProfile in $registry.voices) {
        foreach ($field in @('name', 'description', 'speaker_id', 'reference_audio', 'reference_text', 'consent')) {
            if ($voiceProfile.PSObject.Properties.Name -notcontains $field) {
                throw "Voice profile is missing field: $field"
            }
        }
        if ($voiceProfile.name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$' -or $names.ContainsKey($voiceProfile.name)) {
            throw 'Voice profile names must be unique simple identifiers.'
        }
        foreach ($field in @('name', 'description', 'speaker_id', 'reference_audio', 'reference_text')) {
            if ($voiceProfile.$field -isnot [string]) { throw "Voice profile field must be a string: $field" }
        }
        if ($voiceProfile.consent -isnot [bool]) { throw 'Voice profile consent must be boolean.' }
        if ($voiceProfile.speaker_id -and $voiceProfile.reference_audio) { throw 'Use a speaker ID or a reference clip, not both.' }
        $names[$voiceProfile.name] = $true
    }
    return $registry
}

function Resolve-ReferenceClip {
    param([string] $Path)
    $Path = $Path.Trim().Trim('"').Trim("'")
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Reference audio file does not exist.' }
    $file = Get-Item -LiteralPath $Path
    $format = $file.Extension.TrimStart('.').ToLowerInvariant()
    if ($format -notin @('wav', 'mp3')) { throw 'Reference audio must be a WAV or MP3 file.' }
    if ($file.Length -eq 0 -or $file.Length -gt 15MB) { throw 'Reference audio must be nonempty and at most 15 MiB.' }
    return [pscustomobject]@{ Path = $file.FullName; Format = $format; Bytes = $file.Length }
}

function Save-VoiceProfile {
    param($Registry, [string] $RegistryPath, [string] $Name, [string] $AudioPath, [string] $Transcript, [string] $Id, [bool] $HasConsent)
    if ($Name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$') { throw 'Use a simple voice name such as narrator.' }
    if ([string]::IsNullOrWhiteSpace($AudioPath) -eq [string]::IsNullOrWhiteSpace($Id)) {
        throw 'Supply exactly one of ReferenceAudio or SpeakerId when saving a voice.'
    }
    if ($AudioPath) {
        if (-not $HasConsent) { throw 'Reference voices require Consent confirming you own the voice or have permission to use it.' }
        $AudioPath = (Resolve-ReferenceClip -Path $AudioPath).Path
    }
    elseif ($Transcript) { throw 'ReferenceText requires ReferenceAudio.' }
    $savedProfile = [pscustomobject]@{
        name = $Name
        description = 'Saved voice identity; reuse this profile for related recordings.'
        speaker_id = $Id.Trim()
        reference_audio = $AudioPath
        reference_text = $Transcript
        consent = $HasConsent
    }
    $replaced = $false
    $profiles = @(
        foreach ($existing in $Registry.voices) {
            if ($existing.name -ieq $Name) { $savedProfile; $replaced = $true }
            else { $existing }
        }
    )
    if (-not $replaced) { $profiles += $savedProfile }
    $Registry.voices = $profiles
    $directory = Split-Path -Parent $RegistryPath
    if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $Registry | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $RegistryPath -Encoding utf8
}

function Select-VoiceName {
    param([object[]] $Profiles)
    if ($Profiles.Count -eq 0) { throw 'No voice profiles are available.' }
    $defaultChoice = 1
    Write-Information 'Choose a voice:' -InformationAction Continue
    for ($index = 0; $index -lt $Profiles.Count; $index++) {
        $entry = $Profiles[$index]
        if ($entry.name -ieq 'narrator') { $defaultChoice = $index + 1 }
        $state = if ($entry.speaker_id -or $entry.reference_audio) { '' } else { ' Needs setup.' }
        Write-Information ("{0}. {1}: {2}{3}" -f ($index + 1), $entry.name, $entry.description, $state) -InformationAction Continue
    }
    while ($true) {
        $answer = Read-Host "Voice number [$defaultChoice]"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Profiles[$defaultChoice - 1].name }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Profiles.Count) {
            return $Profiles[$number - 1].name
        }
        Write-Information "Enter a number from 1 to $($Profiles.Count)." -InformationAction Continue
    }
}

function Resolve-OutputFolder {
    param([string] $Value)
    $Value = [Environment]::ExpandEnvironmentVariables($Value.Trim().Trim('"').Trim("'"))
    if ($Value -eq '~') { $Value = $HOME }
    elseif ($Value.StartsWith('~/') -or $Value.StartsWith('~\')) { $Value = Join-Path $HOME $Value.Substring(2) }
    if ([string]::IsNullOrWhiteSpace($Value)) { throw 'An output folder is required.' }
    $resolved = [IO.Path]::GetFullPath($Value, (Get-Location).ProviderPath)
    $ancestor = $resolved
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            if (-not (Test-Path -LiteralPath $ancestor -PathType Container)) { throw 'Output folder or its parent points to a file.' }
            break
        }
        $ancestor = Split-Path -Parent $ancestor
    }
    return $resolved
}

$registry = Read-VoiceRegistry -RegistryPath $VoicesFile
if ($SaveVoice) {
    if ($DryRun -or $PromptOnly -or $ListVoices) { throw 'SaveVoice cannot be combined with DryRun, PromptOnly, or ListVoices.' }
    Save-VoiceProfile -Registry $registry -RegistryPath $VoicesFile -Name $SaveVoice `
        -AudioPath $ReferenceAudio -Transcript $ReferenceText -Id $SpeakerId -HasConsent ([bool]$Consent)
    Write-Output "Saved voice profile: $SaveVoice"
    return
}
if ($ReferenceAudio -or $ReferenceText -or $SpeakerId -or $Consent) { throw 'Use SaveVoice to configure reference audio or a speaker ID.' }
if ($ListVoices) {
    @($registry.voices | ForEach-Object {
        [pscustomobject]@{ Name = $_.name; Configured = [bool]($_.speaker_id -or $_.reference_audio); Description = $_.description }
    }) | ConvertTo-Json
    return
}
if ($PromptOnly -and $Voice) { throw 'PromptOnly cannot be combined with Voice.' }

# Prompt input is literal text, or the complete contents of an existing UTF-8 file.
$interactive = [string]::IsNullOrWhiteSpace($Prompt) -and -not $DryRun
if ($interactive) { $Prompt = Read-Host 'Describe the audio and words to speak, or paste a UTF-8 prompt file path' }
if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'An audio prompt is required.' }
$candidate = $Prompt.Trim().Trim('"').Trim("'")
if (Test-Path -LiteralPath $candidate) {
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw 'Prompt path must point to a file.' }
    $Prompt = (Get-Content -LiteralPath $candidate -Raw -Encoding utf8).Trim()
    if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'Audio prompt file is empty.' }
}

$request = [ordered]@{ model = $model; input = $Prompt; response_format = 'mp3' }
$referenceBytes = 0
$referenceHash = $null
$voiceMode = 'prompt-only'
if (-not $PromptOnly) {
    if ([string]::IsNullOrWhiteSpace($Voice)) {
        if ($interactive) { $Voice = Select-VoiceName -Profiles @($registry.voices) }
        if ([string]::IsNullOrWhiteSpace($Voice)) { $Voice = 'narrator' }
    }
    $voiceProfile = $registry.voices | Where-Object { $_.name -ieq $Voice } | Select-Object -First 1
    if ($null -eq $voiceProfile) { throw 'Unknown voice profile. Use ListVoices to see available names.' }
    if (-not $voiceProfile.speaker_id -and -not $voiceProfile.reference_audio -and $interactive) {
        Write-Information 'Set up this voice once using a short, clean recording with one speaker and no music.' -InformationAction Continue
        $audioPath = Read-Host 'Reference WAV or MP3 file path'
        $transcript = Read-Host 'Exact words spoken in the reference clip, optional'
        $answer = Read-Host 'Do you own this voice or have permission to upload and reuse it? [y/N]'
        if ($answer -notin @('y', 'yes')) { throw 'Voice setup cancelled. Reference audio requires permission.' }
        Save-VoiceProfile -Registry $registry -RegistryPath $VoicesFile -Name $Voice `
            -AudioPath $audioPath -Transcript $transcript -Id '' -HasConsent $true
        $voiceProfile = $registry.voices | Where-Object { $_.name -ieq $Voice } | Select-Object -First 1
    }
    if ($voiceProfile.speaker_id) {
        $request.voice = $voiceProfile.speaker_id
        $voiceMode = 'speaker-id'
    }
    elseif ($voiceProfile.reference_audio) {
        if (-not $voiceProfile.consent) { throw 'This reference profile has no recorded consent. Save it again with Consent.' }
        $clip = Resolve-ReferenceClip -Path $voiceProfile.reference_audio
        $referenceBytes = $clip.Bytes
        $referenceHash = (Get-FileHash -LiteralPath $clip.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        $voiceMode = 'reference-audio'
        # Dry runs validate the file without loading or displaying its audio data.
        if (-not $DryRun) {
            $parts = @(@{ type = 'input_audio'; input_audio = @{ data = [Convert]::ToBase64String([IO.File]::ReadAllBytes($clip.Path)); format = $clip.Format } })
            if ($voiceProfile.reference_text) { $parts += @{ type = 'text'; text = $voiceProfile.reference_text } }
            $request.input_references = $parts
        }
    }
    else { throw 'Voice is not configured. Use SaveVoice with ReferenceAudio and Consent, or a verified SpeakerId. PromptOnly explicitly opts out of voice consistency.' }
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $music = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyMusic)
    if (-not $music) { $music = Join-Path $HOME 'Music' }
    $OutputDirectory = Join-Path $music 'OpenRouter/SeedAudio'
    if ($interactive) {
        $alternate = Read-Host "Output folder [$OutputDirectory]"
        if (-not [string]::IsNullOrWhiteSpace($alternate)) { $OutputDirectory = $alternate }
    }
}
$OutputDirectory = Resolve-OutputFolder -Value $OutputDirectory

if ($DryRun) {
    [pscustomobject]@{
        Endpoint = $endpoint; Model = $model; VoiceProfile = $Voice; VoiceMode = $voiceMode
        ResponseFormat = 'mp3'; PromptLength = $Prompt.Length; ReferenceBytes = $referenceBytes
        PricePerMinuteUSD = 0.15; ProviderMaxSeconds = 120; EstimatedMaxCostUSD = 0.30
        OutputDirectory = $OutputDirectory
    } | ConvertTo-Json -Compress
    return
}
$apiKey = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY')
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'OPENROUTER_API_KEY is not set.' }
if (-not $Force) {
    Write-Information 'Seed Audio costs $0.15 per output minute, up to 120 seconds / $0.30 per request at the published rate. No automatic retries.' -InformationAction Continue
    if ($voiceMode -eq 'reference-audio') { Write-Information 'Your saved reference clip and its transcript will be uploaded to OpenRouter and the Seed provider.' -InformationAction Continue }
    if ((Read-Host 'Generate this audio? [y/N]') -notin @('y', 'yes')) { Write-Output 'Audio generation cancelled.'; return }
}

# Check the chosen folder is writable before sending a paid request.
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$tempFile = Join-Path $OutputDirectory ('.seed-audio-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
try {
    [IO.File]::WriteAllBytes($tempFile, [byte[]]@())
    # Download raw bytes; do not interpret successful speech as JSON.
    try {
        $response = Invoke-WebRequest -Uri $endpoint -Method Post -Headers @{ Authorization = "Bearer $apiKey" } `
            -ContentType 'application/json' -Body ($request | ConvertTo-Json -Depth 8 -Compress) `
            -OutFile $tempFile -PassThru -SkipHttpErrorCheck -TimeoutSec 300
    }
    catch { throw 'OpenRouter audio request failed. Check connectivity and credentials; no automatic retry was made.' }
    if ($null -eq $response -or [int]$response.StatusCode -ne 200) {
        $status = if ($null -eq $response) { 'no response' } else { [string]$response.StatusCode }
        throw "OpenRouter audio generation failed (HTTP $status). Check credentials, credits, and supported voice options; no audio was saved."
    }
    $mediaType = [string]$response.Headers['Content-Type']
    if ($mediaType -notmatch '^audio/(mpeg|mp3)(;|$)') { throw 'OpenRouter did not return MP3 audio; no audio was saved.' }
    $bytes = [IO.File]::ReadAllBytes($tempFile)
    $hasID3 = $bytes.Length -ge 3 -and $bytes[0] -eq 73 -and $bytes[1] -eq 68 -and $bytes[2] -eq 51
    $hasFrame = $bytes.Length -ge 2 -and $bytes[0] -eq 255 -and ($bytes[1] -band 224) -eq 224
    if (-not $hasID3 -and -not $hasFrame) { throw 'OpenRouter returned empty or invalid MP3 audio; no audio was saved.' }
    $filename = 'seed-audio-1-0-{0}-{1}.mp3' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    $outputPath = Join-Path $OutputDirectory $filename
    [IO.File]::WriteAllBytes($outputPath, $bytes)
    Write-Output "Saved audio: $outputPath"
    # Metadata records identity, not the prompt, transcript, audio sample, or API key.
    [ordered]@{
        model = $model; voice_profile = $Voice; voice_mode = $voiceMode; format = 'mp3'
        reference_sha256 = $referenceHash; generation_id = [string]$response.Headers['X-Generation-Id']
    } | ConvertTo-Json | Set-Content -LiteralPath "$outputPath.json" -Encoding utf8
    if (-not $NoOpen) { Start-Process -FilePath $outputPath }
}
finally { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }

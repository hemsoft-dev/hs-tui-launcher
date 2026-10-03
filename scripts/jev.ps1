[CmdletBinding()]
param(
    [string] $State,

    [string] $StateFile,

    [string] $Question,

    [string] $QuestionId = 'decision',

    [ValidateSet('choice', 'noul', 'score')]
    [string] $Type = 'choice',

    [string[]] $Criteria,

    [string] $TrueCriteria,

    [string] $FalseCriteria,

    [string] $QuestionsJson,

    [string] $QuestionsFile,

    [string] $RequestJson,

    [string] $RequestFile,

    [switch] $StdinJson,

    [string] $Model = '~typesafe/jev-latest',

    [string] $SessionId,

    [string] $User,

    [string] $ProviderJson,

    [string] $TraceJson,

    [string] $Endpoint = 'https://openrouter.ai/api/alpha/decisions',

    [ValidateRange(1, 600)]
    [int] $TimeoutSec = 120,

    [switch] $DryRun,

    [switch] $Pretty
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ConvertFrom-JsonText {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,

        [Parameter(Mandatory = $true)]
        [string] $Source
    )

    try {
        $parsed = $Text | ConvertFrom-Json -Depth 100
        return ,$parsed
    }
    catch {
        throw "$Source is not valid JSON: $($_.Exception.Message)"
    }
}

function ConvertTo-StateValue {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Value,

        [Parameter(Mandatory = $true)]
        [string] $Source
    )

    $trimmed = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw "$Source cannot be empty."
    }

    if ($trimmed.StartsWith('{') -or $trimmed.StartsWith('[')) {
        return ,(ConvertFrom-JsonText -Text $Value -Source $Source)
    }

    return $Value
}

function Get-TextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label was not found: $Path"
    }

    try {
        return [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
    }
    catch {
        throw "Could not read $Label '$Path': $($_.Exception.Message)"
    }
}

function Test-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Object,

        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if ($Object -is [System.Collections.IDictionary]) {
        return $Object.Contains($Name)
    }

    return @($Object.PSObject.Properties.Name) -contains $Name
}

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Object,

        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if ($Object -is [System.Collections.IDictionary]) {
        return $Object[$Name]
    }

    return $Object.$Name
}

function Set-ObjectPropertyValue {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This private helper mutates only the in-memory request object supplied by its caller.'
    )]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Object,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [object] $Value
    )

    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return
    }

    if (Test-ObjectProperty -Object $Object -Name $Name) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Assert-QuestionsObject {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Questions
    )

    if ($null -eq $Questions -or $Questions -is [array]) {
        throw 'Questions must be a non-empty JSON object.'
    }

    $propertyCount = if ($Questions -is [System.Collections.IDictionary]) {
        $Questions.Count
    }
    else {
        @($Questions.PSObject.Properties).Count
    }

    if ($propertyCount -eq 0) {
        throw 'Questions must be a non-empty JSON object.'
    }
}

function ConvertTo-CriteriaMap {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Entries
    )

    if ($null -eq $Entries -or $Entries.Count -eq 0) {
        throw 'Choice questions require at least one -Criteria entry in key=value form.'
    }

    $criteria = [ordered]@{}
    foreach ($entry in $Entries) {
        $separator = $entry.IndexOf('=')
        if ($separator -lt 1 -or $separator -eq ($entry.Length - 1)) {
            throw "Invalid -Criteria entry '$entry'. Use key=description."
        }

        $key = $entry.Substring(0, $separator).Trim()
        $description = $entry.Substring($separator + 1).Trim()
        if ([string]::IsNullOrWhiteSpace($key) -or [string]::IsNullOrWhiteSpace($description)) {
            throw "Invalid -Criteria entry '$entry'. Use key=description."
        }

        if ($criteria.Contains($key)) {
            throw "Duplicate choice criterion: $key"
        }
        $criteria[$key] = $description
    }

    return ,$criteria
}

function New-ConvenienceQuestions {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This private constructor returns data and does not change external state.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseSingularNouns',
        '',
        Justification = 'The Decisions API field is named questions and this function builds that collection.'
    )]
    param(
        [string] $Question,
        [string] $QuestionId,
        [string] $Type,
        [string[]] $Criteria,
        [string] $TrueCriteria,
        [string] $FalseCriteria
    )

    if ([string]::IsNullOrWhiteSpace($Question)) {
        throw 'A question is required unless -QuestionsJson, -QuestionsFile, or a request input is supplied.'
    }
    if ([string]::IsNullOrWhiteSpace($QuestionId)) {
        throw '-QuestionId cannot be empty.'
    }

    $questionDefinition = [ordered]@{
        type         = $Type
        instructions = $Question
    }

    switch ($Type) {
        'choice' {
            $questionDefinition.criteria = ConvertTo-CriteriaMap -Entries $Criteria
        }
        'noul' {
            if ([string]::IsNullOrWhiteSpace($TrueCriteria) -or
                [string]::IsNullOrWhiteSpace($FalseCriteria)) {
                throw 'Noul questions require -TrueCriteria and -FalseCriteria.'
            }
            $questionDefinition.criteria = [ordered]@{
                true  = $TrueCriteria
                false = $FalseCriteria
            }
        }
        'score' {
            if ($null -eq $Criteria -or $Criteria.Count -eq 0) {
                throw 'Score questions require one or more -Criteria descriptions.'
            }
            $questionDefinition.criteria = @($Criteria)
        }
    }

    $questions = [ordered]@{}
    $questions[$QuestionId] = $questionDefinition
    return ,$questions
}

function ConvertTo-JsonValue {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,

        [Parameter(Mandatory = $true)]
        [string] $Source
    )

    return ,(ConvertFrom-JsonText -Text $Text -Source $Source)
}

function Write-Json {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Value,

        [switch] $Indented
    )

    if ($Indented) {
        return $Value | ConvertTo-Json -Depth 100
    }

    return $Value | ConvertTo-Json -Depth 100 -Compress
}

$statusCode = $null

try {
    $requestInputs = @(
        @(
            -not [string]::IsNullOrWhiteSpace($RequestJson),
            -not [string]::IsNullOrWhiteSpace($RequestFile),
            [bool] $StdinJson
        ) | Where-Object { $_ }
    )
    if ($requestInputs.Count -gt 1) {
        throw 'Use only one of -RequestJson, -RequestFile, or -StdinJson.'
    }

    $body = $null
    if (-not [string]::IsNullOrWhiteSpace($RequestJson)) {
        $body = ConvertTo-JsonValue -Text $RequestJson -Source '-RequestJson'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($RequestFile)) {
        $requestText = Get-TextFile -Path $RequestFile -Label 'request file'
        $body = ConvertTo-JsonValue -Text $requestText -Source "request file '$RequestFile'"
    }
    elseif ($StdinJson) {
        $stdinText = [Console]::In.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($stdinText)) {
            throw '-StdinJson was supplied, but stdin was empty.'
        }
        $body = ConvertTo-JsonValue -Text $stdinText -Source 'stdin'
    }
    else {
        if (-not [string]::IsNullOrWhiteSpace($State) -and
            -not [string]::IsNullOrWhiteSpace($StateFile)) {
            throw 'Use only one of -State or -StateFile.'
        }

        $stateValue = $null
        if (-not [string]::IsNullOrWhiteSpace($State)) {
            $stateValue = ConvertTo-StateValue -Value $State -Source '-State'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($StateFile)) {
            $stateText = Get-TextFile -Path $StateFile -Label 'state file'
            $stateValue = ConvertTo-StateValue -Value $stateText -Source "state file '$StateFile'"
        }
        else {
            throw 'State is required. Supply -State, -StateFile, a request input, or -StdinJson.'
        }

        if (-not [string]::IsNullOrWhiteSpace($QuestionsJson) -and
            -not [string]::IsNullOrWhiteSpace($QuestionsFile)) {
            throw 'Use only one of -QuestionsJson or -QuestionsFile.'
        }

        if (-not [string]::IsNullOrWhiteSpace($QuestionsJson)) {
            $questions = ConvertTo-JsonValue -Text $QuestionsJson -Source '-QuestionsJson'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($QuestionsFile)) {
            $questionsText = Get-TextFile -Path $QuestionsFile -Label 'questions file'
            $questions = ConvertTo-JsonValue -Text $questionsText -Source "questions file '$QuestionsFile'"
        }
        else {
            $questions = New-ConvenienceQuestions -Question $Question -QuestionId $QuestionId `
                -Type $Type -Criteria $Criteria -TrueCriteria $TrueCriteria -FalseCriteria $FalseCriteria
        }
        Assert-QuestionsObject -Questions $questions

        $body = [ordered]@{
            model     = $Model
            state     = $stateValue
            questions = $questions
        }
    }

    if ($null -eq $body -or $body -is [array]) {
        throw 'The request must be a JSON object.'
    }

    if (-not (Test-ObjectProperty -Object $body -Name 'model') -or
        [string]::IsNullOrWhiteSpace([string] (Get-ObjectPropertyValue -Object $body -Name 'model'))) {
        Set-ObjectPropertyValue -Object $body -Name 'model' -Value $Model
    }
    if (-not (Test-ObjectProperty -Object $body -Name 'state') -or
        $null -eq (Get-ObjectPropertyValue -Object $body -Name 'state')) {
        throw 'The request must contain state.'
    }
    if (-not (Test-ObjectProperty -Object $body -Name 'questions')) {
        throw 'The request must contain questions.'
    }
    Assert-QuestionsObject -Questions (Get-ObjectPropertyValue -Object $body -Name 'questions')

    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        Set-ObjectPropertyValue -Object $body -Name 'session_id' -Value $SessionId
    }
    if (-not [string]::IsNullOrWhiteSpace($User)) {
        Set-ObjectPropertyValue -Object $body -Name 'user' -Value $User
    }
    if (-not [string]::IsNullOrWhiteSpace($ProviderJson)) {
        Set-ObjectPropertyValue -Object $body -Name 'provider' -Value (ConvertTo-JsonValue -Text $ProviderJson -Source '-ProviderJson')
    }
    if (-not [string]::IsNullOrWhiteSpace($TraceJson)) {
        Set-ObjectPropertyValue -Object $body -Name 'trace' -Value (ConvertTo-JsonValue -Text $TraceJson -Source '-TraceJson')
    }

    if ($DryRun) {
        Write-Output (Write-Json -Value $body -Indented:$Pretty)
        exit 0
    }

    $apiKey = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY')
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw 'OPENROUTER_API_KEY is not set.'
    }

    $headers = @{
        Authorization = "Bearer $apiKey"
        Accept        = 'application/json'
    }
    $response = Invoke-WebRequest `
        -Uri $Endpoint `
        -Method Post `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body (Write-Json -Value $body) `
        -TimeoutSec $TimeoutSec `
        -SkipHttpErrorCheck
    $statusCode = [int] $response.StatusCode
    $responseText = [string] $response.Content

    if ($statusCode -lt 200 -or $statusCode -ge 300) {
        $apiMessage = "OpenRouter returned HTTP $statusCode."
        if (-not [string]::IsNullOrWhiteSpace($responseText)) {
            $apiError = $responseText | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($null -ne $apiError -and $apiError.PSObject.Properties.Name -contains 'error') {
                if ($apiError.error -is [string]) {
                    $apiMessage = [string] $apiError.error
                }
                elseif ($null -ne $apiError.error -and
                    $apiError.error.PSObject.Properties.Name -contains 'message' -and
                    -not [string]::IsNullOrWhiteSpace([string] $apiError.error.message)) {
                    $apiMessage = [string] $apiError.error.message
                }
            }
            else {
                $apiMessage = $responseText.Trim()
            }
        }
        throw $apiMessage
    }

    if ([string]::IsNullOrWhiteSpace($responseText)) {
        throw 'OpenRouter returned an empty response.'
    }

    $result = ConvertFrom-JsonText -Text $responseText -Source 'OpenRouter response'
    Write-Output (Write-Json -Value $result -Indented:$Pretty)
    exit 0
}
catch {
    $errorDetails = [ordered]@{
        message = $_.Exception.Message
    }
    if ($null -ne $statusCode) {
        $errorDetails.status = $statusCode
    }

    $errorEnvelope = [ordered]@{
        error = $errorDetails
    }
    Write-Output (Write-Json -Value $errorEnvelope -Indented:$Pretty)
    exit 1
}

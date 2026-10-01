Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-NormalizedSourcePath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ModulePath
    )

    $slashPath = $Path.Replace('\', '/')
    $slashRoot = ([System.IO.Path]::GetFullPath($RepositoryRoot)).Replace('\', '/').TrimEnd('/')
    if ($slashPath.StartsWith("$slashRoot/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $slashPath.Substring($slashRoot.Length + 1)
    }

    $modulePrefix = $ModulePath.TrimEnd('/') + '/'
    if ($slashPath.StartsWith($modulePrefix, [System.StringComparison]::Ordinal)) {
        return $slashPath.Substring($modulePrefix.Length)
    }

    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        return $slashPath.TrimStart('./')
    }

    throw "Source path '$Path' is outside repository '$RepositoryRoot' and module '$ModulePath'."
}

function ConvertFrom-CoverFunctionOutput {
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ModulePath
    )

    $measurements = [System.Collections.Generic.List[object]]::new()
    $repositoryCoveragePercent = $null
    foreach ($line in $Lines) {
        $text = "$line"
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        $totalMatch = [regex]::Match($text, '^total:\s+\(statements\)\s+(?<coverage>\d+(?:\.\d+)?)%$')
        if ($totalMatch.Success) {
            if ($null -ne $repositoryCoveragePercent) {
                throw 'Coverage output contains more than one total line.'
            }
            $repositoryCoveragePercent = [double]::Parse(
                $totalMatch.Groups['coverage'].Value,
                [System.Globalization.CultureInfo]::InvariantCulture
            )
            continue
        }

        $functionMatch = [regex]::Match(
            $text,
            '^(?<file>.+):(?<line>\d+):\s+(?<function>\S+)\s+(?<coverage>\d+(?:\.\d+)?)%$'
        )
        if (-not $functionMatch.Success) {
            throw "Could not parse go tool cover output: '$text'."
        }

        $measurements.Add([pscustomobject]@{
            File = ConvertTo-NormalizedSourcePath `
                -Path $functionMatch.Groups['file'].Value `
                -RepositoryRoot $RepositoryRoot `
                -ModulePath $ModulePath
            Line = [int]$functionMatch.Groups['line'].Value
            Function = $functionMatch.Groups['function'].Value
            CoveragePercent = [double]::Parse(
                $functionMatch.Groups['coverage'].Value,
                [System.Globalization.CultureInfo]::InvariantCulture
            )
        })
    }

    if ($null -eq $repositoryCoveragePercent) {
        throw 'Coverage output does not contain repository total statement coverage.'
    }
    if ($measurements.Count -eq 0) {
        throw 'Coverage output contains zero function measurements.'
    }

    [pscustomobject]@{
        RepositoryCoveragePercent = $repositoryCoveragePercent
        Measurements = @($measurements)
    }
}

function ConvertFrom-GoCycloOutput {
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ModulePath
    )

    $measurements = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $Lines) {
        $text = "$line"
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        $match = [regex]::Match(
            $text,
            '^(?<complexity>\d+)\s+\S+\s+(?<function>\S+)\s+(?<file>.+):(?<line>\d+):\d+$'
        )
        if (-not $match.Success) {
            throw "Could not parse gocyclo output: '$text'."
        }

        $measurements.Add([pscustomobject]@{
            File = ConvertTo-NormalizedSourcePath `
                -Path $match.Groups['file'].Value `
                -RepositoryRoot $RepositoryRoot `
                -ModulePath $ModulePath
            Line = [int]$match.Groups['line'].Value
            Function = $match.Groups['function'].Value
            Complexity = [int]$match.Groups['complexity'].Value
        })
    }

    if ($measurements.Count -eq 0) {
        throw 'gocyclo output contains zero function measurements.'
    }
    return @($measurements)
}

function Get-CrapScore {
    param(
        [Parameter(Mandatory)][int]$Complexity,
        [Parameter(Mandatory)][ValidateRange(0, 100)][double]$CoveragePercent
    )

    $coverage = $CoveragePercent / 100.0
    return ([math]::Pow($Complexity, 2) * [math]::Pow(1.0 - $coverage, 3)) + $Complexity
}

function Merge-CoverageAndComplexity {
    param(
        [Parameter(Mandatory)][object[]]$CoverageMeasurements,
        [Parameter(Mandatory)][object[]]$ComplexityMeasurements
    )

    $coverageByLocation = @{}
    foreach ($coverage in $CoverageMeasurements) {
        $key = "$($coverage.File):$($coverage.Line)"
        if ($coverageByLocation.ContainsKey($key)) {
            throw "Duplicate coverage function location '$key'."
        }
        $coverageByLocation[$key] = $coverage
    }

    $complexityLocations = @{}
    $joined = [System.Collections.Generic.List[object]]::new()
    foreach ($complexity in $ComplexityMeasurements) {
        $key = "$($complexity.File):$($complexity.Line)"
        if ($complexityLocations.ContainsKey($key)) {
            throw "Duplicate complexity function location '$key'."
        }
        $complexityLocations[$key] = $true
        if (-not $coverageByLocation.ContainsKey($key)) {
            throw "No coverage measurement matches gocyclo function '$($complexity.Function)' at '$key'."
        }

        $coverage = $coverageByLocation[$key]
        $rawCrap = Get-CrapScore `
            -Complexity $complexity.Complexity `
            -CoveragePercent $coverage.CoveragePercent
        $joined.Add([pscustomobject]@{
            File = $complexity.File
            Line = $complexity.Line
            Function = $complexity.Function
            Complexity = $complexity.Complexity
            CoveragePercent = $coverage.CoveragePercent
            Crap = [math]::Round($rawCrap, 2, [System.MidpointRounding]::AwayFromZero)
            RawCrap = $rawCrap
        })
    }

    foreach ($coverage in $CoverageMeasurements) {
        $key = "$($coverage.File):$($coverage.Line)"
        if (-not $complexityLocations.ContainsKey($key)) {
            throw "No gocyclo measurement matches covered function '$($coverage.Function)' at '$key'."
        }
    }

    if ($joined.Count -eq 0) {
        throw 'Coverage and complexity join produced zero measurements.'
    }

    return @($joined | Sort-Object `
        @{ Expression = 'RawCrap'; Descending = $true },
        @{ Expression = 'File'; Descending = $false },
        @{ Expression = 'Line'; Descending = $false })
}

function Test-CrapGates {
    param(
        [Parameter(Mandatory)][object[]]$Measurements,
        [Parameter(Mandatory)][double]$RepositoryCoveragePercent,
        [Parameter(Mandatory)][double]$RepositoryCoverageFloorPercent,
        [Parameter(Mandatory)][double]$ActionableCrap,
        [Parameter(Mandatory)][double]$MaximumCrapBaseline
    )

    $violations = [System.Collections.Generic.List[string]]::new()
    if ($Measurements.Count -eq 0) {
        $violations.Add('No function measurements were produced.')
        return @($violations)
    }

    if ($RepositoryCoveragePercent -lt $RepositoryCoverageFloorPercent) {
        $violations.Add(
            ('Repository statement coverage {0:N1}% is below the {1:N1}% floor.' -f
                $RepositoryCoveragePercent, $RepositoryCoverageFloorPercent)
        )
    }

    $actionable = @($Measurements | Where-Object { $_.RawCrap -gt $ActionableCrap })
    foreach ($measurement in $actionable) {
        $violations.Add(
            ('CRAP {0:N2} exceeds {1:N2}: {2}:{3} {4}.' -f
                $measurement.Crap,
                $ActionableCrap,
                $measurement.File,
                $measurement.Line,
                $measurement.Function)
        )
    }

    $maximum = $Measurements | Sort-Object RawCrap -Descending | Select-Object -First 1
    if ($maximum.RawCrap -gt $MaximumCrapBaseline) {
        $violations.Add(
            ('Maximum CRAP {0:N2} exceeds the {1:N2} baseline: {2}:{3} {4}.' -f
                $maximum.Crap,
                $MaximumCrapBaseline,
                $maximum.File,
                $maximum.Line,
                $maximum.Function)
        )
    }

    return @($violations)
}

Export-ModuleMember -Function @(
    'ConvertTo-NormalizedSourcePath',
    'ConvertFrom-CoverFunctionOutput',
    'ConvertFrom-GoCycloOutput',
    'Get-CrapScore',
    'Merge-CoverageAndComplexity',
    'Test-CrapGates'
)

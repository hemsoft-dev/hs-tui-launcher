Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ExpectedBenchmarkName {
    foreach ($mode in @('menu', 'choices')) {
        foreach ($size in @(8, 32, 128)) {
            foreach ($width in @(40, 120)) {
                foreach ($text in @('ascii', 'unicode')) { "BenchmarkLauncherView/$mode/size_$size/width_$width/$text" }
            }
        }
    }
    foreach ($name in @('plain', 'quoted', 'unicode', 'repo_root', 'long')) { "BenchmarkSelectionInvocation/$name" }
}

function ConvertFrom-BenchmarkOutput {
    param([Parameter(Mandatory)][string[]] $Lines, [int] $ExpectedSamples = 5)

    $samples = @{}
    foreach ($line in $Lines) {
        if ($line -notmatch '^Benchmark') { continue }
        if ($line -notmatch '^(Benchmark\S+?)(?:-1)?\s+(\d+)\s+([\d.eE+-]+) ns/op\s+(\d+) B/op\s+(\d+) allocs/op\s*$') {
            throw 'Malformed benchmark result; qualification cannot continue.'
        }
        $name = $Matches[1]
        $iterations = [long]$Matches[2]
        $nanoseconds = [double]::Parse($Matches[3], [Globalization.CultureInfo]::InvariantCulture)
        if ($iterations -le 0 -or $nanoseconds -le 0 -or [double]::IsInfinity($nanoseconds) -or [double]::IsNaN($nanoseconds)) {
            throw 'Benchmark iterations and duration must be finite and positive.'
        }
        if (-not $samples.ContainsKey($name)) { $samples[$name] = @() }
        $samples[$name] += [pscustomobject]@{ nanoseconds = $nanoseconds; bytes = [long]$Matches[4]; allocations = [long]$Matches[5] }
    }
    $expected = @(Get-ExpectedBenchmarkName)
    $unknown = @($samples.Keys | Where-Object { $_ -notin $expected })
    if ($unknown.Count -gt 0) { throw "Unexpected benchmark names: $($unknown -join ', ')." }
    $results = [ordered]@{}
    foreach ($name in $expected) {
        if (-not $samples.ContainsKey($name) -or $samples[$name].Count -ne $ExpectedSamples) {
            throw "$name must report exactly $ExpectedSamples samples."
        }
        $values = @($samples[$name].nanoseconds | Sort-Object)
        $middle = [int][Math]::Floor($values.Count / 2)
        $median = if ($values.Count % 2 -eq 0) { ($values[$middle - 1] + $values[$middle]) / 2 } else { $values[$middle] }
        $deviations = @($values | ForEach-Object { [Math]::Abs($_ - $median) } | Sort-Object)
        $results[$name] = [ordered]@{
            samples = $samples[$name]
            medianNanoseconds = $median
            minimumNanoseconds = $values[0]
            maximumNanoseconds = $values[-1]
            medianAbsoluteDeviation = $deviations[$middle]
            maximumBytes = ($samples[$name].bytes | Measure-Object -Maximum).Maximum
            maximumAllocations = ($samples[$name].allocations | Measure-Object -Maximum).Maximum
        }
    }
    return $results
}

function Test-PerformanceBudget {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Results,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Budget)

    $failures = [Collections.Generic.List[string]]::new()
    $expected = @(Get-ExpectedBenchmarkName)
    if ($Results.Count -ne $expected.Count -or $Budget.Count -ne $expected.Count) {
        throw 'Performance results and budget must contain the complete maintained workload set.'
    }
    foreach ($name in $expected) {
        if (-not $Results.Contains($name) -or -not $Budget.Contains($name)) { throw "Missing performance workload: $name." }
        $result = $Results[$name]
        $limit = $Budget[$name]
        foreach ($field in @('maximumMedianNanoseconds', 'maximumBytes', 'maximumAllocations')) {
            if (-not $limit.Contains($field) -or [double]$limit[$field] -lt 0 -or
                [double]::IsInfinity([double]$limit[$field]) -or [double]::IsNaN([double]$limit[$field])) {
                throw "Invalid performance budget field: $name/$field."
            }
        }
        if ($result.medianNanoseconds -gt $limit.maximumMedianNanoseconds) { $failures.Add("$name latency") }
        if ($result.maximumBytes -gt $limit.maximumBytes) { $failures.Add("$name bytes") }
        if ($result.maximumAllocations -gt $limit.maximumAllocations) { $failures.Add("$name allocations") }
    }
    return $failures.ToArray()
}

Export-ModuleMember -Function Get-ExpectedBenchmarkName, ConvertFrom-BenchmarkOutput, Test-PerformanceBudget

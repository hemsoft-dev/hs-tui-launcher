# Launcher performance qualification

Run these commands with PowerShell 7.5 or newer and Go 1.26.4. The fixture needs
7.5 to preserve originally empty environment values during cleanup:

```powershell
./scripts/Test-Performance.ps1 -OutputDirectory ./performance-artifacts/baseline
./scripts/Test-PerformancePolicy.Unit.ps1
./scripts/Test-PerformanceFixtures.ps1 -OutputDirectory ./performance-artifacts/controlled-regression
```

The wrapper runs this command five times, giving each workload one sample per
independent full-workload pass:

```shell
go test -run '^$' -bench 'Benchmark(LauncherView|SelectionInvocation)' -benchmem -benchtime=500ms -count=1 -cpu=1 ./...
```

The 29 workloads exercise actual `Model.View` menu and choice rendering with
8, 32, and 128 entries, widths of 40 and 120, and ASCII and Unicode text.
Invocation parsing covers plain, quoted, Unicode, repository-root, and long
commands. Fixture construction occurs before the measured loop. Rendering uses
`NO_COLOR=1` and `TERM=dumb`. Measurements cover launcher-owned work, with no
terminal interaction, child command execution, or provider calls.

## Baseline and comparison

[The first maintained native baseline run](https://github.com/HemSoft/hs-tui-launcher/actions/runs/37564542735)
and [the independent repeat](https://github.com/HemSoft/hs-tui-launcher/actions/runs/37564948499)
each measured two clean captures on every GitHub-hosted platform. Their source
revisions are recorded in the budget file. Each of the four captures per platform
contains five samples per workload. The
annotated [measurement tag](https://github.com/HemSoft/hs-tui-launcher/tree/performance-baseline-2026-10-06)
preserves the calibration source after branch cleanup. The
maintained [budget file](../scripts/performance-budgets.json) records platform,
processor descriptions, source revision, observed metrics, and limits. Initial
platforms are Windows/amd64, Linux/amd64, and macOS/arm64.

Earlier 200ms exploratory windows proved too noisy in hosted qualification.
The 500ms windows reduced within-job median variation to 5% on Windows and 6%
on Linux in the first maintained run; macOS varied by 27%. Across both independent
jobs, the largest ratio between capture medians was 1.255 on Windows, 1.398 on
macOS, and 1.979 on Linux. Linux jobs used different EPYC processor models.
Qualification uses the envelope of all four capture medians to account for that
observed worker variation, then compares a candidate's five-sample median.
Raw samples, minima, maxima, and median absolute deviation remain available.

The original baseline used five consecutive samples for each workload in one
process. Candidate qualification spreads those same five 500ms samples across
five independent full-workload passes. An unchanged-source Windows candidate
showed localized timing swings of 145-256us and 173-457us in two 32-item choice
workloads, with unchanged bytes and allocations. Interleaving separates a
workload's samples in time and resets process state between passes. The numeric
limits remain those derived from the original captures; this ordering change
does not raise a limit. Both sampling orders are recorded in the budget, and CI
requires two independent normal captures plus the real controlled rejection.

Each latency limit is 1.5 times the largest maintained capture median, rounded up
to a nanosecond. This initial policy catches substantial slowdowns while allowing
the observed hosted-runner variation. It does not certify small latency changes.
Allocated-byte and allocation-count limits use the largest observed value plus
5%, with minimum margins of 64 bytes and one allocation. These margins accommodate
small runtime and pooling differences while catching material allocation growth.
Every maintained workload must report exactly five valid samples; unknown,
missing, malformed, or differently labelled results fail closed.

A toolchain or platform without a reviewed budget fails qualification. Runner
hardware changes can cause a real gate failure. Inspect the raw evidence and
repeat the native captures before proposing a budget update; do not raise a
limit solely to make a failing candidate pass. To collect measurements without
claiming qualification, use `-RecordBaseline`. Its report always sets
`policyPassed` to false. Baseline collection never rewrites the budget file.

## Evidence and controlled failures

`benchmarks.txt` retains raw Go output. `summary.json` records the checkout and
PR candidate revisions, dirty source state, Go version, platform, CPU, command,
all samples, sampling order, command repetition count, compared metrics, and
failures. A nonzero benchmark process,
invalid evidence, missing policy, regression, or required evidence-write failure
fails the command. A secondary evidence-write error preserves an earlier failure.

The controlled fixture sets a test-only environment variable that makes the
benchmarks allocate an additional escaping 4096-byte slice and sleep for 100
microseconds in each measured iteration. The production launcher never reads
this variable. The gate receives measured results and must reject both latency
and allocated-byte regressions. The fixture restores the caller's environment
in `finally`; its report is expected to have `policyPassed=false` even when the
fixture command passes. Parser fixtures separately verify missing samples, units,
unknown workloads, invalid budgets, and each comparison metric.

CI runs native qualification on all three platforms and requires the aggregate
through `verify`. It retains normal and controlled-failure artifacts for 14 days.
Existing correctness, coverage, lint, security, and mutation gates remain required.
Local results describe the local machine; hosted budgets do not promise identical
timing on arbitrary hardware. Performance output is disposable evidence and may
be removed after inspection. The commands create no external services or processes
that require cleanup.

# Contributing

## Change workflow

Create a branch and open a pull request targeting `main`. The repository's
branch protection rule blocks direct changes to `main` and requires the
`verify` and `mutation` status checks before merge. Do not bypass a pending,
missing, or failed check.

The `verify` job is defined in `.github/workflows/ci.yml`. It depends on the
`lint`, `typescript`, and `security` jobs and the aggregate results of the Windows,
macOS, and Linux `coverage`, `platform`, `performance`, `pi-resources`, and
`typescript-metrics` matrices. Its explicit failure gate
makes a failed, cancelled, or skipped prerequisite fail the already-required
`verify` check. None of these jobs has a path filter. After all prerequisites
pass, `verify` runs these checks:

```powershell
go build ./...
go vet ./...
go test ./...
.\scripts\Test-Complexity.ps1
staticcheck ./...
deadcode ./...
```

Run the same checks locally before opening a pull request. Install the pinned
analysis tools first so local checks use the same versions as CI:

```powershell
go install honnef.co/go/tools/cmd/staticcheck@v0.8.1
go install golang.org/x/tools/cmd/deadcode@v0.49.0
```

## Pi retained resources

Use the pinned Node.js version and PowerShell 7.2+ to measure the offline Jev
and done-sound workloads:

```powershell
./scripts/Test-PiResources.ps1 -OutputDirectory pi-resource-artifacts/qualified
./scripts/Test-PiResources.ps1 -NegativeCheck -OutputDirectory pi-resource-artifacts/controlled
./scripts/Test-PiResourceEvidence.ps1 -PriorEvidenceDirectory pi-resource-artifacts/controlled -OutputDirectory pi-resource-artifacts/stale-rejection
```

The native Windows, macOS and Linux matrix requires two normal captures and
actual retained timer, abort-listener and heap regressions. Its aggregate is a
prerequisite of `verify`. Artifacts retain candidate revisions and complete
cleanup evidence for 14 days. See [the resource measurement policy](docs/pi-resources.md)
for sampling, measured heap budgets, noise margins and coverage limits.

## Formatting and lint

Run the complete non-writing quality policy from the repository root with:

```powershell
pwsh -NoProfile -File ./scripts/Test-Lint.ps1
```

The command restores the locked npm dependencies and installs checksum-pinned
ShellCheck 0.11.0, PSScriptAnalyzer 1.24.0, and actionlint 1.7.7 under the ignored
`bin/lint-tools` cache. Cache entries are staged, validated, and marked complete
before publication; a missing marker or unusable tool is repaired automatically.
It then runs every check even when an earlier check fails, including setup
failures: `gofmt` diff mode, ShellCheck through style severity,
PSScriptAnalyzer warnings/errors, actionlint, markdownlint-cli2 0.23.3, Prettier
3.9.9 for maintained YAML, JSON, TypeScript, and JavaScript extensions, and the
TypeScript compiler. A setup-dependent check reports a clear failure while
independent checks continue. The command never formats files or updates
`package-lock.json`.

Configuration lives in `.shellcheckrc`, `PSScriptAnalyzerSettings.psd1`,
`.github/actionlint.yaml`, `.markdownlint-cli2.jsonc`, `.prettierrc.json`, and
`tsconfig.json`. Markdown line-length is not enforced because commands, research
citations, and prose contain meaningful long lines. Prettier excludes only npm's
generated lockfile and three deliberately vulnerable TypeScript security
fixtures whose exact source is test data. Markdown ignores only dependency and
lint-tool caches. PowerShell warning suppressions are attached to the exact
private functions and explain why their names do not imply external state
changes. `.gitattributes` keeps POSIX shell and maintained text LF-terminated,
PowerShell scripts CRLF-terminated, and MP3 assets binary.

The pinned tools support x64 Windows and x64/ARM64 Linux and macOS. Windows
ARM64 is rejected with a precise message because ShellCheck 0.11.0 does not
publish a native binary and the repository does not assume x64 emulation.

CI runs this same command in `lint`; the required `verify` aggregate rejects a
failed, cancelled, or skipped lint job.

## TypeScript validation

Node.js 24.12.0 is the supported version for repository validation, and
PowerShell 7.2 or newer is required by `npm test`. The exact Node.js version is
pinned in `.node-version`; use a version manager that reads that file or install
that version directly. From the repository root, restore the pinned development
dependencies, type-check without emitting files, and run both test suites with:

```powershell
npm ci --ignore-scripts
npm run typecheck
npm test
```

`npm ci` uses the committed `package-lock.json`, removes an existing
`node_modules` directory before installation, and does not update the lockfile.
The type-check covers maintained TypeScript under `.pi/extensions` and `pi`,
plus TypeScript and MJS test files matching `*.test.*` under `.pi/tests`.
`tsconfig.json` sets `noEmit`, so the command writes no compiled JavaScript into
the checkout. These source-specific patterns include newly added maintained Pi
files without pulling generated JavaScript or unrelated repository content into
the check.

`npm test` runs these required commands:

```powershell
node --experimental-strip-types --test pi/jev-decide/*.test.ts
node --test .pi/tests/*.test.mjs
```

The repository test guard requires exactly five Jev tests and six `.pi/tests`
tests. The wildcard discovers every maintained MJS test file in that directory;
the expected count must be deliberately updated when tests are added. The guard
fails on a nonzero process exit, a missing summary, a changed count, or any
failed, cancelled, skipped, or todo test. CI runs installation,
type-checking, and this guard in the `typescript` job. The required `verify`
aggregate fails through `always()` unless that job succeeds, including when it
is failed, cancelled, or skipped.

## Supported-platform handoff qualification

The `platform` CI matrix builds, vets, and tests the production Go launcher on
native Windows, macOS, and Ubuntu using the version in `go.mod`. It then exercises
both wrapper modes: a controlled executable at the bundled native-launcher path
and the documented `go run .` fallback. The fixture writes the same structured
selection file as the picker and hands off to a controlled child; it never starts
an AI CLI or makes a paid or network request. `platform-gate` aggregates all three
matrix legs, and the existing required `verify` job fails through `always()` if
that aggregate is failed, cancelled, or skipped.

The test orchestrator requires PowerShell 7.5 or newer on every platform. This is
a CI/test-harness requirement, not a change to `run.ps1`, which remains supported
on Windows PowerShell 5.1 as well as PowerShell 7. On macOS and Linux, `run.sh`
also requires Python 3. The fallback mode requires Go; use the version in
`go.mod` for the production-equivalent check.

From Windows, run:

```powershell
pwsh -NoProfile -File ./scripts/Test-LauncherHandoff.ps1
pwsh -NoProfile -File ./scripts/Test-LauncherHandoff.ps1 -NegativeCheck
```

The handoff qualification harness requires PowerShell 7.5 or newer so the
portable environment-provider assertions can distinguish empty and absent
variables. On Windows it also starts a real Windows PowerShell 5.1 process to
check inherited empty values and culture-independent name matching. This test
prerequisite does not change the shipped Windows wrapper's 5.1 support.

From macOS or Linux, run the same local equivalent in PowerShell 7.5 or newer:

```sh
pwsh -NoProfile -File ./scripts/Test-LauncherHandoff.ps1
pwsh -NoProfile -File ./scripts/Test-LauncherHandoff.ps1 -NegativeCheck
```

The first command tests native and fallback mode with successful and nonzero
children. It proves exact arguments (including an empty argument and non-shell
special data), working directory, selected and inherited environment values,
stdin, temporary selection-file cleanup, and exit-code propagation. The second
is a safe synthetic negative route proving that mismatched argv, environment,
empty-variable presence, working directory, stdin, and nonzero exit expectations
all fail the harness.

By default, reports and generated fixture binaries are written under the system
temporary directory, not the checkout. Pass `-OutputDirectory <path>` to retain
reports. CI uploads `launcher-handoff-<target>-<architecture>-<commit>` with
overwrite semantics. Each bounded JSON report uses `schemaVersion: 2` and records
the exact commit, native GOOS/GOARCH and Go version, wrapper path and hash,
launcher mode, selected executable/arguments/working directory/allowlisted
fixture environment, observed handoff fields, bounded stdout/stderr, and status.
Observed allowlisted environment entries record both `value` and `present`, so an
absent variable cannot be mistaken for a present variable with an empty value.
The report never dumps the full environment. No credentials are read or needed;
only the controlled `HS_HANDOFF_*` variables are recorded. Fixture builds set
`GOPROXY=off`, `GOSUMDB=off`, and `GOTOOLCHAIN=local`.

## Security checks

Pull requests and pushes to `main` run the required `security` job before
`verify`. It uses read-only repository permissions and runs four scanner families:

- `govulncheck ./...` reports reachable vulnerabilities in Go call paths.
- Gitleaks scans the working tree and all locally reachable Git refs plus HEAD
  for credentials and other secrets, including merge patches.
- Semgrep applies the repository's `.semgrep.yml` rules to Go and TypeScript.
- OSV-Scanner checks all recognized dependency manifests in the repository, so
  a pull request that changes a manifest is reviewed against the OSV database.

Install the same pinned scanner versions used by CI, then run the scans and the
controlled failure fixtures:

```powershell
.\scripts\Install-SecurityTools.ps1
.\scripts\Test-Security.ps1 -OutputDirectory ./security-artifacts
.\scripts\Test-SecurityFixtures.ps1
```

`Install-SecurityTools.ps1` installs `govulncheck` v1.8.0, Gitleaks v8.30.1,
OSV-Scanner v2.4.0, and Semgrep 1.178.0 under the ignored
`bin/security-tools` directory; it does not alter a system Python environment.
The last command confirms that the secret, static-analysis, and dependency
scanners reject inert examples. The
secret fixture is a repository-specific sentinel, not a usable credential. The
dependency fixture is lockfile metadata only; it never downloads or publishes
the package.

Secret qualification runs `gitleaks dir` and `gitleaks git --log-opts='--all -m'`
with the maintained configuration and full redaction. It refuses shallow or
uninitialized repositories and invalid or inconsistent scanner evidence. CI
fetches complete branch and tag history with `fetch-depth: 0`. Local clones must
fetch the refs they intend to qualify and remove any shallow boundary first.
Unreachable objects and remote refs that were never fetched are outside the
stated local scan scope.

The controlled fixtures add then delete the inert sentinel, introduce it only
in a merge commit, and test shallow-history refusal. They prove a clean final
tree can still fail history qualification. A fixture-only rule recognizes the
sentinel in disposable repositories; production uses the existing default rules
and narrow configuration exceptions without weakening them.

`security-artifacts` retains fully redacted tree/history findings and a summary
with the checkout and PR candidate revisions, dirty state, refs, scan scope,
configuration SHA-256, scanner exits, and finding counts. The CI artifact is
retained for 14 days, including failures. Required metadata failures fail the
command; a secondary metadata-write error preserves an earlier scan failure.

Run these commands from the repository root. Never paste a real API key into
a fixture or command line, and clear credential environment variables if you
add scanner debugging. Gitleaks redacts findings, but scanner output should
still be treated as sensitive and must not be pasted into public logs. The
scans query public vulnerability data only and make no paid-provider calls.

## Coverage and CRAP gates

Run the repository coverage and CRAP gate from the repository root:

```powershell
.\scripts\Test-CoverageCrap.ps1
```

This one command runs `go test ./...` with a single count-mode coverage profile,
uses `go list ./...` to prove that the profile contains every production Go file
selected for the native `GOOS`/`GOARCH` target, and runs the same pinned gocyclo
version as the complexity gate. It joins statement coverage and complexity by
normalized file and function start line, then calculates each function's CRAP
score as `complexity^2 * (1 - coverage)^3 + complexity`. CI runs the command
natively on Windows, macOS, and Linux, so the aggregate gate includes production
files selected by any supported operating system. No selected production
package, file, or function is excluded.

The command prints and writes a worst-first report containing the native
`GOOS`/`GOARCH` target and each function's exact file, line, name, complexity,
statement coverage, and CRAP score. By default, `coverage.out`,
`coverage-crap.json`, and `coverage-crap.txt` are written to a process-specific
temporary directory, so generated reports do not dirty the checkout. To retain
them elsewhere, use `-OutputDirectory <path>`.

`scripts/coverage-crap-baseline.json` maintains three non-regression gates:

- repository statement coverage must remain at least 83.0%;
- every function must have CRAP at most 30.00;
- the repository maximum CRAP must not increase above 20.00.

The combined tree was reproduced twice on Windows/AMD64 at 83.8% coverage;
hosted macOS/ARM64 and Linux/AMD64 each measured 83.6%. Every target measured
the same 20.00 maximum across 45 functions. Coverage is consumed at the
one-decimal precision emitted by `go tool cover`; the floor preserves the
audited 83.0% basis and retains 0.6 percentage points below the lower platform
result. Reported CRAP is rounded to two decimal places, midpoint away from zero,
but gates compare the unrounded value.
The maximum baseline has no upward headroom, so any increase fails. Raise the
coverage floor or lower the maximum when durable improvements provide a new
repeatable baseline; never move either gate merely to pass a change.

Before collecting production metrics, every coverage matrix leg runs
`Test-CoverageCrap.Unit.ps1` to protect parser, formula, join, and threshold
behavior. CI retains each target's profile and both reports for 14 days in an
artifact named `coverage-crap-<target>-<runner architecture>-<commit SHA>`.
Uploads use overwrite semantics so a same-run retry is safe. The JSON and text
reports identify both the checked-out commit and native Go target. The required
`verify` status fails unless all three coverage targets succeed.

## Mutation testing

The required `mutation` status aggregates `mutation-go` and
`mutation-typescript`. A failed, cancelled, or skipped target fails that status.
Both jobs run once in each PR workflow. Feature-branch pushes do not trigger a
second workflow; pushes to `main` qualify the actual merged revision separately.

Run the language targets from the repository root with PowerShell 7.2 or newer:

```powershell
pwsh -NoProfile -File ./scripts/Test-MutationPolicy.Unit.ps1
pwsh -NoProfile -File ./scripts/Test-Mutations.ps1
pwsh -NoProfile -File ./scripts/Test-TypeScriptMutations.ps1
```

Go uses [Gremlins v0.6.0](https://github.com/go-gremlins/gremlins) against every
production Go file selected on the native platform. `.gremlins.yaml` has no file
exclusions and uses all-package coverage. TypeScript uses
[StrykerJS 10.0.0](https://stryker-mutator.io/docs/stryker-js/configuration/), with
its matching TypeScript checker and TypeScript 5.9.3. The separate manifest and
lockfile under `scripts/mutation-tools` pin the full tool dependency tree without
replacing the repository's TypeScript compiler. Installation uses `npm ci
--ignore-scripts` for both locked dependency trees. Node.js remains pinned by
`.node-version`.

`stryker.config.json` mutates only `pi/jev-decide/jev-core.ts` and runs all five
existing Jev tests with Node's type stripping and command runner. The extension
entry point is outside this target because it binds Pi's external runtime;
there are no excluded lines or operators within the decision core. The tests
inject fake authentication and fetch responses. An unmutated preload rejects
real fetch, HTTP, TCP, TLS, UDP, and DNS connections, and a negative fixture proves
those rejections before the run. Package installation can access the registry;
the test processes cannot call a paid provider. Command-runner coverage analysis
is unavailable, so every viable mutant runs the full suite. Stryker copies
sandbox dependencies instead of symlinking them to a live npm installation;
concurrent lint/setup work must not replace the mutation tool's own dependencies.
Its `uncovered`
count is zero by construction, not proof of per-line coverage.

`scripts/mutation-thresholds.json` defines the maintained break thresholds and
higher improvement targets. `scripts/mutation-survivors.json` records the exact
allowed survivor identities. A new survivor fails even when another survivor
was killed and the total lived count did not increase. Go identities include
file, line, column, and operator; TypeScript also includes the end location and
replacement. Source movement therefore requires a reviewed baseline update,
not silent acceptance of new survivors.

| Target | Reproduced baseline | Break thresholds | Improvement target |
| --- | --- | --- | --- |
| Go on Ubuntu | 193 generated, 146 killed, 23 lived, 24 uncovered, 0 timed-out, 0 non-viable | At least 193 generated, 86.39% efficacy, 87.56% mutant coverage; at most 23 lived, 24 uncovered, 0 timed-out/non-viable; no new survivors | 90% efficacy, 90% coverage, 0 lived |
| TypeScript | 828 generated, 127 killed, 383 lived, 0 uncovered, 6 timed-out, 312 non-viable | At least 828 generated and 25.77% score; at most 383 lived, 0 uncovered, 6 timed-out, 312 non-viable; no new survivors | 30% score, at most 300 lived |

The Go baseline comes from main CI run `37147395390` at commit
`7dfd1f05244f9c8db3a45ca34bd5d7763955774f`. The TypeScript baseline uses the same
source on Windows x64 with Node.js 24.12.0 and was reproduced without any changed
outcomes on Ubuntu x64 in [PR CI run 37167504905](https://github.com/HemSoft/hs-tui-launcher/actions/runs/37167504905). Stryker reports compile errors as
non-viable and computes score as killed plus timed-out divided by killed plus
lived plus timed-out plus uncovered. The TypeScript baseline is 25.775% before
rounding; its 25.77% floor truncates to two decimals rather than adding upward
headroom. Go efficacy is killed divided by killed plus lived. The 87.56%
coverage floor preserves both the audited 10.88% result and the newer Ubuntu
baseline. Gremlins' native Windows coverage discovery produced only 10.36% on
this tree and is not a passing qualification; use Ubuntu CI for the maintained
Go mutation gate. Native platform build, unit, handoff, and CRAP gates still
cover Windows and macOS without exclusions.

Both scripts require nonzero generated and executed counts and reject tool
errors or incomplete reports. They retain raw per-mutant JSON, tool output, and
a summary with every outcome count, scores, tool version, native target,
checked-out commit, PR head when supplied by CI, dirty-tree status, thresholds,
and improvement-target status. Policy parsing fails closed on missing, mistyped, or out-of-bounds thresholds.
Summary reports remain available when policy qualification fails. Reports default to a unique temporary directory; pass
`-OutputDirectory <path>` to retain them in a known location. CI uploads
`mutation-go-<PR head or main commit>` and
`mutation-typescript-<PR head or main commit>` for 14 days, including on failure.
The checked-out commit can be GitHub's synthetic PR merge revision; the
separate PR-head field identifies the reviewed source commit.

The policy unit command proves every break threshold rejects a regression and
that swapping in a new survivor fails with an unchanged lived count. To prove
the real command path fails, temporarily set the TypeScript break score to
99% and its improvement target to 100% in an isolated test branch, run its mutation command, verify the nonzero
exit and retained reports, then restore the policy before committing. Never
lower a floor or add an exclusion merely to pass CI. Kill retained survivors
with focused tests, remove their identities, and raise floors when repeated
runs establish an improved baseline.

## Launcher performance

The required `verify` result includes native performance qualification on Windows
x64, macOS ARM64 and Linux x64. Run with PowerShell 7.5+ and pinned Go 1.26.4:

```powershell
./scripts/Test-PerformancePolicy.Unit.ps1
./scripts/Test-Performance.ps1 -OutputDirectory performance-artifacts/qualified
./scripts/Test-PerformanceFixtures.ps1 -OutputDirectory performance-artifacts/controlled
```

The 29 workloads measure actual rendering and invocation parsing with five
500ms samples, allocation counts and bytes. They call no provider and run no
selected command. CI retains raw measurements and candidate-bound summaries
for 14 days. Every native target and the real extra-work rejection must pass.
Read [the sampling method and measured budgets](docs/performance.md) before
changing limits. Hosted worker variation is part of the reviewed baseline;
`-RecordBaseline` collects evidence without qualifying or changing a budget.
Performance artifacts are ignored disposable output. Existing correctness,
coverage, security and mutation thresholds remain required.

## TypeScript branch coverage and function risk

Use the pinned Node.js version and PowerShell 7.2+ to collect complete production
coverage and per-function complexity/CRAP:

```powershell
./scripts/Test-TypeScriptMetrics.ps1 -OutputDirectory typescript-metric-artifacts/qualified
node scripts/Test-TypeScriptMetricFixtures.mjs --output typescript-metric-artifacts/controlled
```

The native matrix requires two normal captures and actual uncovered-source,
startup-failure and evidence-write regressions. Its aggregate feeds `verify`.
Artifacts retain raw V8/Istanbul reports, source/candidate identities, worst
functions and reviewed policy results for 14 days. See [the TypeScript metric
policy](docs/typescript-metrics.md) for measurement semantics, complete unloaded
source coverage, measured baselines and limits.

## Cyclomatic complexity

The required `verify` job measures every production Go function with
[gocyclo](https://github.com/fzipp/gocyclo):

```powershell
.\scripts\Test-Complexity.ps1
```

The script pins gocyclo to
`v0.6.1-0.20251227213109-7b6c7c5e29f1` and enforces a per-function cyclomatic
complexity limit of 15. It scans the repository root recursively, including
`main.go`, `internal/config`, and `internal/tui`. It excludes only `_test.go`
files because the limit applies to production code, not test harnesses. No
production package or file is excluded.

On failure, gocyclo prints each function's measured complexity, package,
function name, and `file:line:column`. The initial maximum after adopting the
limit is 13 in `tokenizeSelectionCommand`. Change `$complexityLimit` in
`scripts/Test-Complexity.ps1` only after reviewing the affected functions;
prefer splitting control flow over raising the limit.

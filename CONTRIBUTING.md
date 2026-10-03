# Contributing

## Change workflow

Create a branch and open a pull request targeting `main`. The repository's
branch protection rule blocks direct changes to `main` and requires the
`verify` and `mutation` status checks before merge. Do not bypass a pending,
missing, or failed check.

The `verify` job is defined in `.github/workflows/ci.yml`. It depends on the
`typescript` and `security` jobs and the aggregate results of the Windows,
macOS, and Linux `coverage` and `platform` matrices. Its explicit failure gate
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

## TypeScript validation

Node.js 24.12.0 is the supported version for repository validation. The exact
version is pinned in `.node-version`; use a version manager that reads that file
or install that version directly. From the repository root, restore the pinned
development dependencies, type-check without emitting files, and run both test
suites with:

```powershell
npm ci --ignore-scripts
npm run typecheck
npm test
```

`npm ci` uses the committed `package-lock.json`, removes an existing
`node_modules` directory before installation, and does not update the lockfile.
The type-check covers `.pi/extensions/done-sound.ts`, both files under
`pi/jev-decide`, and both test files. `tsconfig.json` sets `noEmit`, so the
command writes no compiled JavaScript into the checkout.

`npm test` runs these required commands:

```powershell
node --experimental-strip-types --test pi/jev-decide/*.test.ts
node --test .pi/tests/done-sound.test.mjs
```

The repository test guard requires exactly five Jev tests and six done-sound
tests. It fails on a nonzero process exit, a missing summary, a changed count,
or any failed, cancelled, skipped, or todo test. CI runs installation,
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

The test orchestrator requires PowerShell 7.2 or newer on every platform. This is
a CI/test-harness requirement, not a change to `run.ps1`, which remains supported
on Windows PowerShell 5.1 as well as PowerShell 7. On macOS and Linux, `run.sh`
also requires Python 3. The fallback mode requires Go; use the version in
`go.mod` for the production-equivalent check.

From Windows, run:

```powershell
pwsh -NoProfile -File ./scripts/Test-LauncherHandoff.ps1
pwsh -NoProfile -File ./scripts/Test-LauncherHandoff.ps1 -NegativeCheck
```

From macOS or Linux, run the same local equivalent in PowerShell 7:

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
`verify`. It uses read-only repository permissions and performs four checks:

- `govulncheck ./...` reports reachable vulnerabilities in Go call paths.
- Gitleaks scans the working tree for credentials and other secrets.
- Semgrep applies the repository's `.semgrep.yml` rules to Go and TypeScript.
- OSV-Scanner checks all recognized dependency manifests in the repository, so
  a pull request that changes a manifest is reviewed against the OSV database.

Install the same pinned scanner versions used by CI, then run the scans and the
controlled failure fixtures:

```powershell
.\scripts\Install-SecurityTools.ps1
.\scripts\Test-Security.ps1
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

The `mutation` job runs [Gremlins](https://github.com/go-gremlins/gremlins)
against all production Go code in the repository:

```powershell
.\scripts\Test-Mutations.ps1
```

The script pins Gremlins to v0.6.0, prints the generated, killed, lived,
uncovered, and non-viable mutation counts, and fails if the tool reports an
error or generates no mutations. `.gremlins.yaml` enforces two maintained
floors: 75% test efficacy (killed mutations divided by killed plus lived
mutations) and 10% mutant coverage. The initial Ubuntu CI baseline is 78.95%
efficacy and 84.18% mutant coverage; Gremlins' initial Windows baseline is 100%
efficacy and 10.76% mutant coverage.

The scan has no file exclusions. Keep that scope unless a documented technical
reason requires a narrow exclusion. Raise either threshold when better tests
provide durable headroom; do not lower one merely to make CI pass.

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

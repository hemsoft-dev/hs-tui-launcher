# Contributing

## Change workflow

Create a branch and open a pull request targeting `main`. The repository's
branch protection rule blocks direct changes to `main` and requires the
`verify` and `mutation` status checks before merge. Do not bypass a pending,
missing, or failed check.

The `verify` job is defined in `.github/workflows/ci.yml`. It depends on the
`security` job and has an explicit failure gate, so anything other than a
successful security result fails the already-required `verify` check. Neither
job has a path filter. After security passes, `verify` runs these checks:

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

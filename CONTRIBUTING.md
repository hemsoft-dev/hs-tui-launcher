# Contributing

## Change workflow

Create a branch and open a pull request targeting `main`. The repository's
branch protection rule blocks direct changes to `main` and requires the
`verify` and `mutation` status checks before merge. Do not bypass a pending,
missing, or failed check.

The `verify` job is defined in `.github/workflows/ci.yml`. It runs these checks:

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

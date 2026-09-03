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
staticcheck ./...
deadcode ./...
```

Run the same checks locally before opening a pull request. Install the analysis
tools first when they are not already on `PATH`:

```powershell
go install honnef.co/go/tools/cmd/staticcheck@latest
go install golang.org/x/tools/cmd/deadcode@latest
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

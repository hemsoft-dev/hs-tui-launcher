# Contributing

## Change workflow

Create a branch and open a pull request targeting `main`. The repository's
branch protection rule blocks direct changes to `main` and requires the
`verify` status check before merge. Do not bypass a pending, missing, or failed
check.

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

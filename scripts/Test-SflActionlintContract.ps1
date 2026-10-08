[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Actionlint,
    [Parameter(Mandatory)][string] $ShellCheck
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Test-Lint.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Cannot parse the production lint policy.' }
$commands = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.CommandAst] -and
    $node.GetCommandName() -eq 'Invoke-LintCheck' -and
    $node.CommandElements[1].Value -eq 'GitHub Actions (actionlint)'
}, $true))
if ($commands.Count -ne 1) { throw 'Expected exactly one production actionlint policy.' }
$productionCheck = $commands[0].CommandElements[2].ScriptBlock.GetScriptBlock()
$setup = [pscustomobject]@{ ToolSucceeded = $true; Actionlint = $Actionlint; ShellCheck = $ShellCheck }
Get-Command -Name $setup.Actionlint, $setup.ShellCheck -CommandType Application -ErrorAction Stop | Out-Null
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) ('sfl-actionlint-' + [guid]::NewGuid())
$passed = $false
$previous = Get-Location
try {
    $root = $temporary
    New-Item -ItemType Directory -Path (Join-Path $root '.github/workflows'), (Join-Path $root '.sfl'), (Join-Path $root '.git') -Force | Out-Null
    Copy-Item (Join-Path $repositoryRoot '.github/actionlint.yaml') (Join-Path $root '.github/actionlint.yaml')
    Copy-Item (Join-Path $repositoryRoot '.github/workflows/*.yml') (Join-Path $root '.github/workflows')
    Copy-Item (Join-Path $repositoryRoot '.sfl/sfl.json'), (Join-Path $repositoryRoot '.sfl/lint-contract.json') (Join-Path $root '.sfl')
    Set-Location -LiteralPath $root
    & $productionCheck
    $workflow = Join-Path $root '.github/workflows/sfl-pr-review-auto.yml'
    $original = [System.IO.File]::ReadAllText($workflow)
    [System.IO.File]::WriteAllText($workflow, $original.Replace('queue: max', 'queue: invalid'))
    $rejected = $false
    try { & $productionCheck }
    catch {
        if ($_.Exception.Message -notmatch 'differs from its independently verified lint contract') { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw 'Modified generated workflow was accepted.' }
    [System.IO.File]::WriteAllText($workflow, $original)
    $invalid = "name: Negative control`non: push`njobs:`n  bad:`n    runs-on: ubuntu-latest`n    steps:`n      - uses: not-a-valid-action`n"
    [System.IO.File]::WriteAllText((Join-Path $root '.github/workflows/negative-control.yml'), $invalid)
    $rejected = $false
    try { & $productionCheck }
    catch {
        if ($_.Exception.Message -notmatch 'enforced diagnostic') { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw 'Unrelated workflow diagnostic was suppressed.' }
    $passed = $true
    Write-Host 'Canonical deployment passes; altered deployment and unrelated errors are rejected.'
}
finally {
    Set-Location -LiteralPath $previous
    if ($passed) { Remove-Item -LiteralPath $temporary -Recurse -Force }
    else { Write-Host "Failed control evidence retained at $temporary" }
}

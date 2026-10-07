#Requires -Version 7.2
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '../run.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw 'The wrapper could not be parsed.' }
$definition = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'ConvertTo-WindowsNativeArgument'
}, $true)
if ($null -eq $definition) { throw 'Missing native argument encoder.' }
. ([scriptblock]::Create($definition.Extent.Text))
# Literal expected encodings independently pin CRT delimiter rules, including
# backslashes adjacent to quotes and the closing delimiter.
$cases = @(
    @{ argument = ''; expected = '""' },
    @{ argument = 'plain'; expected = '"plain"' },
    @{ argument = 'value with spaces'; expected = '"value with spaces"' },
    @{ argument = 'a"b'; expected = '"a\"b"' },
    @{ argument = '\"'; expected = '"\\\""' },
    @{ argument = '\\'; expected = '"\\\\"' },
    @{ argument = 'backslash\trailing\'; expected = '"backslash\trailing\\"' },
    @{ argument = 'unicode-雪'; expected = '"unicode-雪"' },
    @{ argument = 'semi;pipe|amp&angle<>dollar$'; expected = '"semi;pipe|amp&angle<>dollar$"' }
)
foreach ($case in $cases) {
    if ((ConvertTo-WindowsNativeArgument -Argument $case.argument) -cne $case.expected) {
        throw 'Native argument encoder differs from the independently specified CRT encoding.'
    }
}
Write-Host 'Nine native argument encoding cases passed.'

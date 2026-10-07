# TypeScript coverage and function risk

Use PowerShell 7.2+ and the pinned Node.js 24.12.0 from the repository root:

```powershell
npm ci --ignore-scripts
./scripts/Test-TypeScriptMetrics.ps1 -OutputDirectory typescript-metric-artifacts/qualified
node scripts/Test-TypeScriptMetricFixtures.mjs --output typescript-metric-artifacts/controlled
```

The wrapper installs the isolated locked report tools, checks seven guarded
policy/parser tests, and runs the existing eleven guarded integration tests under
coverage. It pins c8 12.0.0 and the TypeScript 5.9.3 AST parser in
`scripts/coverage-tools`. The repository's TypeScript 7 compiler, Go coverage,
complexity and mutation policies remain unchanged. The test processes inherit
the existing network-denying preload; auth/fetch/player fixtures stay offline.
Dependency installation can access the registry.

## Complete source coverage

The collector uses Git's tracked and untracked non-ignored TypeScript files as
the source inventory. It excludes test filenames, erased `.d.ts` declarations,
and the inert `.github/security/fixtures` scanner examples. It explicitly gives
every remaining source to c8 `--all`, including sources no test loads. Missing
or unexpected coverage files reject the capture. Production coverage-ignore
comments are rejected.

The current inventory is `jev-core.ts`, `index.ts` and `done-sound.ts`. No
maintained runtime file has an external-runtime exclusion. `index.ts` is
currently unloaded and remains visible at zero coverage; the Pi host and SDK
integration are not exercised by these tests. That is a measured coverage gap,
not a passing host-integration claim.

Raw V8 data, Istanbul JSON/summary, text output and source hashes remain in the
artifact. c8's file branch measure uses V8-derived ranges. Those ranges include
function-entry and block execution and are not an exhaustive count of semantic
true/false paths. Native Node's coverage percentages use a different aggregation;
the reports must not be presented as interchangeable.

For comparison, run the native commands with the same offline preload:

```powershell
node --import ./scripts/mutation-tools/offline.mjs --experimental-strip-types --experimental-test-coverage --test pi/jev-decide/*.test.ts
node --import ./scripts/mutation-tools/offline.mjs --test --experimental-test-coverage .pi/tests/*.test.mjs
```

## Per-function measurement

The AST enumerates every source function with a body, including declarations,
expressions, anonymous callbacks, arrows, constructors, methods and accessors.
Erased type signatures and runtime-generated initialization functions are not
source functions. c8 omits unnamed callbacks from its function map, so the
collector uses raw V8 invocation ranges to cover the full AST inventory.
Module execution cannot give a function invocation credit. Unloaded or uncalled
functions receive zero coverage.

Cyclomatic complexity starts at one. It adds one for each `if`, loop, non-default
switch case, catch, ternary, logical/nullish operator or assignment, optional
evaluation, and parameter default. Nested function bodies have their own count.
Type syntax is excluded. Stable identities combine file, lexical parent, name
and sibling ordinal; line numbers remain diagnostic. Source or syntax changes
that alter identities require a reviewed baseline update.

Each converted branch range belongs to the innermost function containing its
span. Module-wide ranges are excluded from function ownership. When a function
has owned ranges, its coverage fraction is covered ranges divided by all owned
ranges, provided raw invocation evidence exists. Otherwise its explicit basis
is function invocation, zero or one. Reports retain the exact basis and counts;
they never call an invocation-only result branch coverage. Converter newline
columns of -1/-2 retain their actual newline offsets, while invalid spans and
incomplete counters fail parsing.

CRAP uses that per-function fraction:

```text
CRAP = complexity^2 * (1 - coverage)^3 + complexity
```

For the reproduced `assertJsonValue` result, complexity 20 and coverage 0.5 give
`400 * 0.125 + 20 = 70`. The independent arithmetic test also verifies full and
zero coverage. The worst-function list includes source identity, line, complexity,
invocation and branch evidence, coverage basis, and CRAP.

## Reproduced baseline and policy

The [native baseline run](https://github.com/HemSoft/hs-tui-launcher/actions/runs/37569204877)
collects two clean captures per platform at
`66f309b1e27883dcef52d95400ab267a5c16e11f`. The annotated
[measurement tag](https://github.com/HemSoft/hs-tui-launcher/tree/typescript-metrics-baseline-2026-10-07)
preserves its source and tool manifest. Windows x64, macOS ARM64 and Linux x64
produced identical maintained metrics in both captures:

| Source | Source functions | File branch coverage | Loaded |
| --- | ---: | ---: | --- |
| `done-sound.ts` | 3 | 100% | yes |
| `jev-core.ts` | 41 | 98/167, or 58.68% | yes |
| `index.ts` | 8 | 0% | no |

The maximum source complexity is 22. The largest CRAP is 70, followed by
`parseAnswer` at 53.125 and the unloaded auth callback at 42. These existing gaps
remain visible and are grandfathered at their reproduced per-function values.
Qualification is a non-regression policy, not a claim of complete test coverage.

The versioned budget sets each file's exact branch floor and each function's
coverage floor, complexity ceiling, CRAP ceiling and coverage basis. Comparisons
allow only `1e-12` for floating-point arithmetic. A new function must be invoked
with full measured coverage and complexity no greater than the observed maximum,
22. A new source must have full file branch coverage. Removing a baseline source
or function, or changing its measurement basis, also requires a reviewed budget
update. No baseline is silently removed or automatically extended.

`-RecordBaseline` collects metrics and a proposal without qualifying a candidate
or writing the budget. Reproduce repeated native captures and inspect changes
before updating limits. An unsupported Node/tool version or native platform
rejects qualification. All original quality gates remain required.

## Negative fixtures and evidence

The controlled command appends an actual uncalled production function, captures
its rejection, then restores and compares the original bytes. It separately
creates an actual untracked, unloaded production file and requires that file and
its function to appear and fail qualification. The fixture removes only its
owned file. Policy tests independently reject branch, function-coverage,
complexity and CRAP regressions, malformed budgets and incomplete metrics.

Actual blocked summary paths prove that evidence-write failure preserves an
earlier candidate-validation error and rejects an otherwise successful capture.
Fixtures restore source and remove temporary files in `finally`; required
cleanup failure fails the fixture, and an earlier failure remains primary.

Reports record checkout and candidate revisions, dirty state, platform, CPU,
tool versions, commands, source inventory/hashes, budget SHA-256, worst functions
and policy results. CI supplies `TYPESCRIPT_METRICS_PR_HEAD` and retains artifacts
for 14 days. Native matrix qualification and controlled failures feed the
required `verify` result. Raw coverage files are disposable measurement evidence;
they contain source paths and runtime function names and should be inspected
before sharing outside the repository.

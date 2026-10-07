# Pi retained-resource qualification

Run from the repository root with PowerShell 7.2 or newer and the Node.js
24.12.0 version pinned in `.node-version`:

```powershell
./scripts/Test-PiResources.ps1 -OutputDirectory pi-resource-artifacts/qualified
./scripts/Test-PiResources.ps1 -NegativeCheck -OutputDirectory pi-resource-artifacts/controlled
./scripts/Test-PiResourceEvidence.ps1 -PriorEvidenceDirectory pi-resource-artifacts/controlled -OutputDirectory pi-resource-artifacts/stale-rejection
```

The wrapper checks five policy tests, then starts a fresh Node process with
`--expose-gc`, native TypeScript stripping, and the existing offline preload.
No installed Pi host, credentials, paid provider, or audio player is required.
Unknown Node versions or platform budgets fail qualification.

## Workload and scope

The sampler calls the actual `executeJevDecision` implementation and the actual
`doneSound` settled-event handler. Auth, fetch, the Pi event registry, and player
execution are injected fakes. The offline preload blocks accidental network
access. The Pi SDK, provider transport, `index.ts` adapter, and real audio process
resources are outside this measurement.

Ten warm-up waves precede the collected baseline. Five measured waves each run
25 iterations. Each iteration exercises successful, failed-auth, failed-network,
invalid-response, and cancelled Jev requests. Each wave also waits for an actual
1000 ms timeout against a pending auth dependency. Measured totals are 125 calls
for each of the five fast paths and five timeouts, or 630 requests.

Each iteration also delivers five settled events. These cover successful playback,
alternating thrown, nonzero-exit and killed-player failures, two overlapping events,
and successful playback after the overlap. The measured workload requires 625
settled events, 500 player calls, 125 warnings, one extension-lifetime callback,
and at most one player in flight.

Each request gets a fresh caller-owned `AbortController`. Pending fake dependencies
actually settle before their resource observations. The report records peak fake
work in flight separately from work retained after settlement. This does not
qualify long-lived caller cancellation contexts or SDK-owned resources.

## Measurements and policy

The baseline and every sample follow three forced collections, each separated by
an event-loop turn. Reports keep `heapUsed`, `heapTotal`, RSS, external memory,
array buffers, and native active-resource names separately. RSS is diagnostic;
allocator behavior can retain pages after managed objects are collected.

The gate requires zero settled timers, visible child and caller abort listeners,
pending fake work, and players. One registered event callback is expected for the
extension lifetime. Teardown must leave zero callbacks, timers, parent listeners,
players, pending work, and native `Timeout` resources. Listener inspection covers
the supplied signals through Node's `getEventListeners`; it does not enumerate
runtime-private references.

Heap growth is the largest positive difference between any measured `heapUsed`
sample and the collected baseline. The budget derives from three independent
captures per platform in the
[native baseline run](https://github.com/HemSoft/hs-tui-launcher/actions/runs/37567112340)
at revision `dc0e89294925f21d502cf2f5453eca9b79648b56`. The annotated
[measurement tag](https://github.com/HemSoft/hs-tui-launcher/tree/pi-resource-baseline-2026-10-06)
preserves that source.

All nine captures had zero positive growth after warm-up. The adopted allowance
adds eight times the largest within-capture sample span. Eight is an engineering
noise margin, not a statistical confidence claim. The resulting limits are:

| Platform | Largest sample span | Maximum positive heap growth |
| --- | ---: | ---: |
| Windows x64 | 12,800 bytes | 102,400 bytes |
| macOS ARM64 | 13,408 bytes | 107,264 bytes |
| Linux x64 | 12,736 bytes | 101,888 bytes |

The versioned budget records the source, run, processor descriptions, capture
count, and policy inputs. To recalibrate, use `-RecordBaseline` for repeated native
captures and review the raw data, workload, warm-up and Node version before
editing the budget. Baseline collection always reports `policyPassed: false`;
it cannot qualify a candidate or automatically rewrite thresholds.

## Controlled rejection and evidence

`-NegativeCheck` runs three fresh sampler processes. They create a real ten-minute
timer, a real abort listener, and a strongly referenced two-million-element array.
The ordinary policy rejects their measured resources; it never uses the fixture
name as a failure condition. Each case must complete teardown with zero retained
resources, including native timeouts. A timer case that merely unreferenced its
timer would fail that requirement.

Every run writes `summary.json` and `tool.log`. Metadata includes checkout and
candidate revisions, dirty state, Node version, platform, processor, command,
budget SHA-256, all samples, workload counts, policy failures and teardown. CI
candidate provenance uses `RESOURCE_PR_HEAD`; local runs default to HEAD.
CI retains reports for 14 days. A required evidence-write failure rejects an
otherwise successful capture. If qualification already failed, a later write
failure preserves the original error.

Sampler cleanup runs in `finally`: pending players settle, tracked native timers
are cleared, controlled listeners and heap data are released, fake registrations
are removed, global timer functions are restored, and the original sound setting
is restored. These checks exercise the sampler's lifecycle and injected workload;
they do not claim disposal of a real Pi host's event registry.

# Research: Using TypeSafe Jev through OpenRouter Decisions API

> **Evidence note (2026-09-18).** Local wrapper claims are based on the repository's checked-in `README.md` and `scripts/jev.ps1`. Web claims are based on the linked first-party OpenRouter and TypeSafe documentation fetched during this research. Community implementations are labeled as implementation references. Claims marked *inference* are design guidance, not statements verified from those pages.

## Summary

TypeSafe Jev is exposed in this project as OpenRouter's Decisions API model `~typesafe/jev-latest`, rather than a normal chat-completions model. A request supplies a `state` and a non-empty object of named `questions`; each question has a type (`choice`, `noul`, or `score`), instructions, and type-specific criteria. The resulting JSON contains answers, resolved model information, and usage, making it suitable as a bounded decision tool that a chat model or coding agent calls before acting.

The strongest use is a narrow, consequential fork: provide the current facts and explicit alternatives, ask Jev for a machine-readable decision, then let the agent validate and execute it. Do not use it as an unrestricted autonomous planner or as a substitute for tests, security review, or human approval.

## Web-verified findings

The current first-party TypeSafe documentation sharpens the design beyond the local wrapper:

- [System One](https://docs.typesafe.ai/concepts/system-one.md) says Jev returns typed decisions and probabilities, not prose or reasoning, and accepts strings, JSON objects, and arrays of text. It explicitly positions Jev as a fast judgment inside a larger workflow, with deterministic code combining the answers and handling action or review.
- [State](https://docs.typesafe.ai/concepts/state.md) recommends a named JSON object for related context. Questions are evaluated independently against the same state.
- [Primitives](https://docs.typesafe.ai/primitives.md) says Choice is for a defined set, Score is for an ordered spectrum, and Noul is for a yes/no judgment. The docs recommend one narrow judgment per question and including an `other` or `none` option when the candidate list may not cover the input.
- [Speculative fan-out](https://docs.typesafe.ai/patterns/fan-out.md) recommends asking independent questions together. The questions run in parallel, so code can ignore branch-specific answers after the response arrives.
- [Confidence-gated routing](https://docs.typesafe.ai/patterns/confidence-routing.md) and [Confidence](https://docs.typesafe.ai/confidence.md) recommend using confidence as a second axis: the answer says what to do, while confidence says whether the system should act, verify, escalate, or fall back. Thresholds must follow the risk of the action and be tuned on local outcomes.
- [Intent routing](https://docs.typesafe.ai/patterns/intent-routing.md) and [Composite scoring](https://docs.typesafe.ai/patterns/composite-scoring.md) cover the two most useful agent patterns: route a request to a handler, and score independent dimensions before combining them in code.
- TypeSafe's [use-case map](https://docs.typesafe.ai/concepts/use-case-map.md) lists model routing, semantic code linting, universal verification, guardrails, retrieval reranking, feature extraction, and human escalation. These are candidates for experiments, not reasons to put Jev in every loop.
- The [official TypeSafe agent skill](https://raw.githubusercontent.com/typesafe-ai/skills/main/skills/typesafe-ai/SKILL.md) recommends keeping questions and thresholds in one reviewable place, treating typed output as an interface rather than proof, and keeping code in charge of workflow and permissions.
- The OpenRouter [Jev Latest page](https://openrouter.ai/~typesafe/jev-latest) currently describes Jev as a structured decision model for routing, classification, and other decision points. It lists a 32K context and `$0.042/M` input with `$0` output pricing. The moving `~typesafe/jev-latest` alias resolves to a concrete model in the response, so integrations should record that resolved model.
- A useful community design appears in [opencode-jev-router](https://github.com/viniciosrab/opencode-jev-router): shadow mode first, confidence-gated Top-1/Top-3 routing later, bounded and redacted state, metrics, and fail-open behavior. A separate [Pi extension PR](https://github.com/narumiruna/pi-extensions/pull/1328) uses a typed `jev_decide` tool rather than asking the chat model to hand-write shell JSON. Both are implementation references, not TypeSafe guarantees.

## Recommended approach

Use a small `consult-jev` skill as the policy and trigger layer. Keep `jev.ps1` as the portable execution adapter. Later, add a native Pi `jev_decide` tool so the model receives a typed tool schema and validated output instead of constructing shell arguments. Do not make Jev an automatic preflight on every prompt.

The skill should trigger only when all of these are true: the agent has a semantic judgment to make, the answer space can be stated explicitly, the judgment will affect routing/ranking/review or a bounded next step, and an independent fast opinion is useful. Its description should contain the words `choose`, `classify`, `route`, `rank`, `score`, `verify`, `triage`, `safe`, `confidence`, `escalate`, and `human review`, while explicitly excluding deterministic work, open-ended generation, and permission authority.

Start with three shadow-mode use cases and measure outcomes before allowing automation:

1. **Model, tool, or skill routing.** Give Jev the task summary and a small curated ballot. Compare its suggested route with the parent agent's actual route; do not filter tools or override required skills yet.
2. **Review-depth and risk triage.** Ask for a Choice or Score over `routine`, `review`, and `high-risk`, plus independent Noul checks for secrets, destructive edits, production impact, and missing evidence. Let deterministic policy decide the resulting checks or approval.
3. **Semantic verification.** Ask whether a proposed change satisfies a stated requirement, whether evidence supports a claim, or whether an output contains a policy violation. Treat failures and low confidence as reasons to inspect or escalate, never as permission to bypass tests or access controls.

Use a stable state shape such as `task`, `facts`, `constraints`, `options`, `unknowns`, and `evidence_version`. Ask independent questions in one request. Include `none`, `other`, or `needs_human` when forcing one of the listed options would be unsafe. Validate answer keys and probability ranges, log latency/cost/resolved model and the eventual outcome, and fail open to the parent model for low-stakes advice or fail closed for destructive/high-stakes actions.

## Findings

1. **Claim:** The project calls `POST https://openrouter.ai/api/alpha/decisions` with model `~typesafe/jev-latest`, not the normal chat-completions endpoint. **Sources:** [project README](../README.md); [OpenRouter Decisions API request documentation](https://openrouter.ai/docs/api/api-reference/alphadecisions/submit-a-decisions-questions-and-answers-request); [Decisions endpoint](https://openrouter.ai/api/alpha/decisions). **Support:** direct evidence from the repository and the fetched first-party endpoint documentation. **Confidence:** high.

2. **Claim:** The minimal request shape is `{model, state, questions}`. `state` may be text or structured JSON; `questions` must be a non-empty JSON object keyed by question ID. The local wrapper rejects missing state/questions and arrays as the questions object. **Sources:** [scripts/jev.ps1](../scripts/jev.ps1). **Support:** direct evidence. **Confidence:** high.

3. **Claim:** Question types are:
   - `choice`: `criteria` is an object mapping stable option keys to descriptions.
   - `noul` (yes/no): `criteria` has `true` and `false` descriptions.
   - `score`: `criteria` is an array of one or more criterion descriptions.
   The wrapper's convenience interface enforces these shapes. **Sources:** [scripts/jev.ps1](../scripts/jev.ps1); [README usage](../README.md). **Support:** direct evidence. **Confidence:** high.

4. **Claim:** A good `state` is a compact decision record, not a vague prompt: task, constraints, evidence, candidate IDs, risk/rollback facts, and any hard exclusions. Keep option IDs stable and put their meanings in `criteria`; ask one decision per question. *Inference from the API shape and wrapper.* **Sources:** [scripts/jev.ps1](../scripts/jev.ps1); [OpenRouter Decisions API docs](https://openrouter.ai/docs/api/api-reference/alphadecisions/submit-a-decisions-questions-and-answers-request). **Support:** interpretation/inference. **Confidence:** medium.

5. **Claim:** High-value coding-agent uses include model/provider selection, deployment-target selection, migration strategy, test prioritization, incident mitigation choice, and deciding whether a proposed change is safe to automate. *Inference.* Jev is most valuable after the agent has gathered facts but before it commits an irreversible action. **Sources:** [project README's deployment example](../README.md). **Support:** researcher inference grounded in the checked-in example. **Confidence:** medium.

6. **Claim:** An agent should consult Jev when alternatives are explicit, criteria conflict, the decision is consequential or hard to reverse, and an independent decision pass is cheaper than a bad action. It should not consult Jev for deterministic transformations, ordinary code search, formatting, or a choice already fixed by policy. *Inference.* **Confidence:** medium.

7. **Claim:** The repository wrapper supports `-SessionId`, `-User`, `-ProviderJson`, and `-TraceJson`, passes an API key from `OPENROUTER_API_KEY`, supports request JSON via stdin/file, has a configurable endpoint and timeout (default 120 seconds), and offers `-DryRun`. **Sources:** [scripts/jev.ps1](../scripts/jev.ps1). **Support:** direct evidence. **Confidence:** high.

8. **Claim:** The wrapper treats non-2xx responses, empty responses, invalid JSON, missing API key, and timeout/transport failures as errors; its output is JSON and errors are returned in an `{error:{message,...}}` envelope. **Sources:** [scripts/jev.ps1](../scripts/jev.ps1). **Support:** direct evidence. **Confidence:** high.

9. **Claim:** Account-specific latency, rate limits, retention, privacy terms, and target-workflow accuracy still need local measurement. The endpoint is labeled `/api/alpha/decisions`, and `~typesafe/jev-latest` is a moving alias, so production integrations should assume interface and behavior may change. **Sources:** [Decisions endpoint](https://openrouter.ai/api/alpha/decisions); [OpenRouter Jev Latest page](https://openrouter.ai/~typesafe/jev-latest). **Support:** direct evidence for the endpoint/model-page labels and an operational recommendation. **Confidence:** high.

## Request and question design

Recommended state template:

```json
{
  "task": "Choose a deployment target for build 1842",
  "facts": ["integration tests passed", "artifact is 420 MB"],
  "constraints": ["must support private networking", "rollback under 10 minutes"],
  "options": {"mini": "on-prem mini host", "air": "portable macOS host"},
  "unknowns": ["current target load"],
  "hard_exclusions": ["do not expose credentials"]
}
```

Keep facts separate from preferences; state what evidence is missing; never silently treat a missing fact as false. Use one question ID per decision and ask for a stable answer key where downstream automation needs one. For multi-step workflows, preserve the response and decision rationale in the agent trace, but re-check facts before execution.

### Choice question

```json
{
  "model": "~typesafe/jev-latest",
  "state": {"task":"Choose deployment target","options":["mini","air"],"constraints":["private network"]},
  "questions": {
    "target": {
      "type": "choice",
      "instructions": "Which target best satisfies the constraints? Return one option.",
      "criteria": {"mini":"Prefer private-network access", "air":"Prefer portability"}
    }
  }
}
```

### Noul (yes/no) question

```json
{
  "model": "~typesafe/jev-latest",
  "state": {"change":"Delete generated build artifacts", "paths":["dist/"], "git_status":"clean"},
  "questions": {
    "safe_to_delete": {
      "type": "noul",
      "instructions": "Is deletion safe without losing user-authored work?",
      "criteria": {"true":"All files are reproducible and tracked elsewhere", "false":"Any file may contain user-authored or unrecoverable data"}
    }
  }
}
```

### Score question

```json
{
  "model": "~typesafe/jev-latest",
  "state": {"proposal":"Use cache invalidation strategy B", "evidence":["benchmark on 3 workloads"], "risk":"stale responses"},
  "questions": {
    "proposal_score": {
      "type": "score",
      "instructions": "Score the proposal against each criterion using the API's score format.",
      "criteria": ["correctness under concurrent writes", "rollback simplicity", "latency impact", "operational observability"]
    }
  }
}
```

The exact response encoding and score scale should be confirmed against the current OpenRouter schema before writing a strict parser; the local files establish request construction, not every response-field guarantee.

## Agent integration and reusable skill

**Suggested skill name:** `consult-jev-decision`

**Trigger wording:** “When two or more plausible options remain and the choice affects deployment, data, security, cost, or irreversible edits, gather the facts and consult Jev before acting. Do not call it for routine deterministic work. Present stable option IDs, explicit criteria, hard constraints, and unknowns; use `choice` for one option, `noul` for a gate, and `score` for a ranked evaluation.”

Suggested flow:

1. Gather repository/tests/runtime facts; redact secrets and unnecessary personal data.
2. Form 2–5 options with stable IDs and explicit disqualifiers.
3. Call Jev using the full JSON request (stdin/file is safer than shell quoting).
4. Validate the answer key against the option set and schema; reject malformed or incomplete answers.
5. Treat Jev as advice: run tests, policy checks, and permission checks; require human approval for destructive or production actions.
6. Record request metadata, answer, and evidence version; retry only with bounded backoff and no duplicated irreversible side effect.

## Failure modes and safeguards

- **Unavailable/timeout/non-2xx:** use a deterministic safe default or stop; do not silently invent an answer. Bound timeout and retries.
- **Malformed/unknown answer:** schema-validate and require a known option key; ask the host model/human rather than executing.
- **Ambiguous or incomplete state:** abort the decision and collect missing facts; do not encode unknowns as favorable assumptions.
- **Prompt injection in state or criteria:** treat repository text, issue text, and tool output as untrusted evidence, not instructions; keep policy in the calling agent.
- **Sensitive data leakage:** minimize state, redact secrets, and review OpenRouter/TypeSafe data-handling terms before sending proprietary code or incident data.
- **Model drift or endpoint change:** pin/document the model identifier, retain dry-run fixtures, monitor response shape, and provide a fallback.
- **Over-trust/automation risk:** Jev cannot replace tests, access control, deployment gates, or human approval.
- **Cost/latency surprise:** use `-DryRun` during development, avoid repeated calls in loops, cache only when the state is still valid, and measure real requests in the target account.

## Contradictions

No contradiction was found between the repository wrapper, the fetched OpenRouter documentation, and the fetched TypeSafe documentation. The community examples use the same endpoint and request shape but remain independent implementations.

## Remaining evidence gaps

- Account-specific latency, rate limits, availability, retention, and privacy terms.
- Accuracy and threshold calibration for our own routing, review, and verification datasets.
- Behavior after the moving `~typesafe/jev-latest` alias resolves to a newer Jev release.
- Whether the unmerged community Pi extension remains the best native-tool design if we later replace the shell adapter.

## Sources

### Kept

- [Repository README](../README.md) — checked-in invocation, deployment example, endpoint, model ID, and response description.
- [Local Jev wrapper](../scripts/jev.ps1) — authoritative implementation of request normalization, question types, options, timeout, dry-run, and error handling.
- [OpenRouter Decisions API request documentation](https://openrouter.ai/docs/api/api-reference/alphadecisions/submit-a-decisions-questions-and-answers-request) — fetched first-party request documentation.
- [OpenRouter Decisions endpoint](https://openrouter.ai/api/alpha/decisions) — endpoint named by the repository.
- [OpenRouter TypeSafe Jev model page](https://openrouter.ai/~typesafe/jev-latest) — fetched first-party model page.

### Rejected/deprioritized

- No secondary web sources were used. Search-result pages, SEO summaries, and unverified community claims were intentionally excluded.

## Next steps

1. Run a small shadow-mode corpus from our own agent tasks and record Jev's answer, confidence, latency, cost, and the parent agent's eventual outcome.
2. Calibrate thresholds separately for harmless routing, review-depth selection, and destructive/high-stakes gates.
3. Decide whether to add a native Pi `jev_decide` tool after the shell-based skill proves useful.

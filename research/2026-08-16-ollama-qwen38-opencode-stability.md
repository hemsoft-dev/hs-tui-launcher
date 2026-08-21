# Qwen3.8-27B, Ollama, and OpenCode tool-call stability

Research date: 2026-08-16

## Bottom line

The instability is real on this machine, but the evidence does not show that
Qwen3.8-27B is broadly incapable of tool use. The current setup gives OpenCode
only 32,768 tokens while Ollama recommends at least 64,000 for OpenCode and
other coding agents. The failures cluster right below that 32K ceiling.

The practical order of operations is:

1. Keep Ollama for one controlled retry, but raise its real context allocation
   to 64K and tell OpenCode the matching context and output limits.
2. Enable Flash Attention and use `q8_0` for Ollama's KV cache so 64K remains
   practical on the RTX 5090. Do not start with `q4_0` KV cache for an agent.
3. If the same transcript-rendering error remains, A/B test the same model
   through `llama-server`. It is the easiest alternative on native Windows and
   gives direct control over context, templates, reasoning history, and KV
   precision.
4. If tool-call correctness matters more than setup simplicity, use SGLang in
   WSL2 or Linux with its Qwen-specific reasoning and tool parsers. SGLang's
   official Qwen3.8 recipe includes a verified RTX 5090 NVFP4 configuration.

Restarting OpenCode works because it shortens or replaces the transcript. It
does not repair the underlying context and message-rendering mismatch.

## What is installed here

The checks below were read-only except for inference requests:

| Component | Observed state |
| --- | --- |
| GPU | NVIDIA GeForce RTX 5090, 32,607 MiB VRAM |
| System RAM | 61.6 GiB |
| OpenCode | 1.18.18 |
| Ollama | 0.32.13 |
| Model | `qwen3.8:27b`, 27.3B parameters, Q4_K_M |
| Model capabilities | completion, vision, tools, thinking |
| Model metadata | 262,144 native context; requires Ollama 0.32.12 |
| Ollama implementation | `RENDERER qwen3.8`, `PARSER qwen3.5` |
| Active allocation | 100% GPU, 32,768-token context |
| GPU memory with model loaded | about 25.9 GiB at the time checked |

The official Ollama tag is only two days old. Ollama lists the model as a
tool-capable, thinking model with a 256K context window, but this machine is
not serving it at 256K. It is serving it at 32K. See the
[Ollama Qwen3.8 library entry](https://ollama.com/library/qwen3.8) and the
[Qwen3.8-27B model card](https://huggingface.co/Qwen/Qwen3.8-27B).

The launcher in [`scripts/Start-Ollama.ps1`](../scripts/Start-Ollama.ps1)
defines only the provider URL and model name. It does not declare OpenCode's
`limit.context` or `limit.output` fields. OpenCode says those fields are how it
tracks the remaining context for a custom provider. See
[OpenCode's provider documentation](https://opencode.ai/docs/providers).

## The local failure pattern

The OpenCode log at
`C:\Users\User\.local\share\opencode\log\opencode.log` contains 26 streamed
failures across four Qwen3.8 sessions on 2026-08-16. The repeated error is:

```text
AI_APICallError: no user query found in messages
```

The OpenCode database shows the context position of those sessions:

| Session | Turns | Highest input tokens | Terminal error |
| --- | ---: | ---: | ---: |
| `ses_ff477a...` | 7 | 29,157 | 1 |
| `ses_ff4781...` | 15 | 31,158 | 1 |
| `ses_ff4819...` | 8 | 30,792 | 1 |
| `ses_ff48d5...` | 18 | 30,402 | recovered after retries |

One representative session moved from 26,064 input tokens plus a 2,020-token
model turn to a zero-token renderer error on the next tool continuation. A new
user message later succeeded with 31,158 input tokens. That behavior fits a
multi-step tool transcript which has lost the normal user-query boundary during
trimming. It does not look like an out-of-memory crash or a model that cannot
emit tools at all.

I also sent five fresh, non-streaming OpenAI-compatible requests directly to
Ollama. Each request required exactly one structured `get_weather` tool call.
All five returned:

```text
finish_reason = tool_calls
tool           = get_weather
arguments      = {"city":"Boston"}
```

The calls took 2.8 to 4.0 seconds. This small test cannot establish long-session
reliability, but it proves that the installed checkpoint, renderer, and parser
can produce correct tool calls in a clean context.

## Why the 32K allocation matters

Ollama selects 32K by default on GPUs with 24 to 48 GiB VRAM. Its current
documentation specifically says that web search, agents, and coding tools
should use at least 64K. The current `ollama ps` result matches the documented
32K default exactly. See
[Ollama's context-length documentation](https://docs.ollama.com/context-length)
and its
[OpenCode integration guide](https://docs.ollama.com/integrations/opencode).

There is a second configuration trap. OpenCode connects to
`http://localhost:11434/v1`, the OpenAI-compatible endpoint. Ollama documents
that the OpenAI API has no context-size setting. Adding `num_ctx` to OpenCode's
provider options does not resize the Ollama runner. The context must be set in
the Ollama app, through `OLLAMA_CONTEXT_LENGTH`, or in a derived Modelfile. See
[Ollama's OpenAI compatibility documentation](https://docs.ollama.com/api/openai-compatibility).

This is not a new class of problem. In OpenCode issue
[#1068](https://github.com/anomalyco/opencode/issues/1068), several Ollama users
reported aborted or failed tool calls which started working after they raised
the model's real context allocation. That issue concerns older Qwen models, so
it is supporting history rather than proof about Qwen3.8.

The exact error string also appears in an OpenCode report involving a Qwen3.6
template after context compaction. In that case a multi-part user message was
not recognized as a normal user query by the Qwen template. See OpenCode issue
[#25168](https://github.com/anomalyco/opencode/issues/25168). The Qwen3.5
template in llama.cpp contains the corresponding guard which raises when a
multi-step tool transcript has no remaining non-tool user query. See the
[Qwen3.5 template source](https://github.com/ggml-org/llama.cpp/blob/master/models/templates/Qwen3.5-4B.jinja).

Taken together, the best explanation is:

- OpenCode produces a long series of assistant and tool messages.
- The 32K budget becomes tight at roughly the same point in every failed local
  session.
- Context trimming or compaction leaves a transcript shape which the Qwen
  renderer rejects because it cannot identify a normal user query.
- Restarting or sending a new user turn creates a valid boundary again.

This is an inference from the local token and error correlation plus the Qwen
template behavior. A captured failing HTTP request body would be needed to
prove which layer removes or transforms the user turn.

## Public sentiment, with the limits stated plainly

There is no mature consensus about the exact `qwen3.8:27b` Ollama tag yet. Qwen
released the checkpoint on August 14, and the Ollama tag followed the same day.
As of August 16, GitHub issue searches in `ollama/ollama`,
`anomalyco/opencode`, `ggml-org/llama.cpp`, and `vllm-project/vllm` returned no
issues naming the exact 27B checkpoint.

The first two days of community reports are mixed but useful:

- One OpenCode user published a `llama.cpp` configuration with explicit 128K
  context and 32K output limits for Qwen3.8-27B. The thread is too small to
  establish reliability. See
  [Qwen3.8 27B in OpenCode](https://www.reddit.com/r/opencode/comments/1vocitv/qwen38_27b_in_opencode/).
- A user ran Q6_K through `llama.cpp` and OpenCode at 128K on a 32GB GPU and
  completed a 52K-context repository audit. Another commenter reported an
  agent session around 208K. These are anecdotes, not controlled tests. See
  [Qwen3.8-27B Q6_K at 128K](https://www.reddit.com/r/LocalLLaMA/comments/1vojr6m/qwen3827b_q6_k_at_128k_on_a_single_32gb_gpu/).
- An Ollama plus OpenCode user said the model handled real coding tasks better
  than Qwen3.6 but also reported a tool-call problem with an older Pi harness.
  The same thread repeatedly notes high context use and frequent compaction.
  See
  [Qwen 3.8 27B early thoughts](https://www.reddit.com/r/LocalLLM/comments/1vpfl3d/qwen_38_27b_early_thoughts/).
- Several users reproduced a fresh `system message must be at the beginning`
  error with Ollama's Qwen3.8 MLX tag and Claude Code. That is a different tag
  and harness, but it is evidence that the new renderer integrations still
  have transcript-shape bugs. See
  [Problems with Ollama/Claude Code and Qwen3.8:27b-mlx](https://www.reddit.com/r/ollama/comments/1vohghm/problems_with_ollamaclaude_code_and_qwen3827bmlx/).

There is also a model-side warning from the hosted Qwen3.8 Max Preview. One
Qwen Code issue reports raw XML tool calls after 200 or more turns and roughly
180K context. That is a different, much larger model and endpoint, so it should
not be treated as direct evidence against the local 27B checkpoint. It does
show that Qwen3.8 tool-format adherence can degrade in long sessions. See
[Qwen Code issue #8003](https://github.com/QwenLM/qwen-code/issues/8003).

My read of the sentiment is simple. People are impressed by the model, but the
release is too new and the serving details matter too much for "stable" or
"unstable" to be a meaningful community verdict yet.

## Improve the Ollama setup first

### 1. Allocate a real 64K context

Use the Ollama app's context slider or set the server-wide context before
Ollama starts:

```powershell
[Environment]::SetEnvironmentVariable('OLLAMA_CONTEXT_LENGTH', '65536', 'User')
```

Fully exit and restart Ollama, then verify the allocation while OpenCode is
running:

```powershell
ollama ps
```

The `CONTEXT` column must say `65536`. Merely changing OpenCode JSON will not do
this through `/v1`.

If a global setting is undesirable, create an agent-specific model alias:

```text
FROM qwen3.8:27b
PARAMETER num_ctx 65536
```

```powershell
ollama create qwen3.8:27b-opencode-64k -f .\Modelfile
```

### 2. Use Flash Attention and q8 KV cache

Ollama says Flash Attention reduces memory growth with context, while `q8_0`
KV cache uses about half the memory of `f16` with usually negligible quality
loss. Both are global server options. See the
[Ollama FAQ](https://docs.ollama.com/faq).

```powershell
[Environment]::SetEnvironmentVariable('OLLAMA_FLASH_ATTENTION', '1', 'User')
[Environment]::SetEnvironmentVariable('OLLAMA_KV_CACHE_TYPE', 'q8_0', 'User')
```

Restart Ollama after changing them. Avoid `q4_0` initially. Ollama describes a
larger quality loss for q4 KV cache, and llama.cpp specifically warns that
extreme KV quantization can hurt tool calling. See
[llama.cpp's function-calling guide](https://github.com/ggml-org/llama.cpp/blob/master/docs/function-calling.md).

### 3. Give OpenCode the same limits

The model entry should include explicit limits so OpenCode can compact before
the server ceiling:

```json
"qwen3.8:27b": {
  "name": "Qwen 3.8 27B",
  "limit": {
    "context": 65536,
    "output": 8192
  }
}
```

The context number must match the live `ollama ps` allocation. An 8K output
cap is a conservative starting point for tool loops on a 64K runner. Raise it
only after measuring the remaining input budget.

### 4. Treat reasoning history as a tuning option

Qwen3.8 defaults to `xhigh` reasoning and preserves earlier thinking. Qwen says
preserved thinking helps multi-turn agent consistency, but it also consumes
the transcript budget. After fixing context, compare `medium` reasoning with
the default. Do not disable preserved thinking as the first fix because that
changes model behavior and may increase retries. The model card documents the
[reasoning and preservation controls](https://huggingface.co/Qwen/Qwen3.8-27B#api-usage).

## Better serving alternatives

### llama.cpp: best first alternative on Windows

OpenCode officially documents `llama-server` as a local OpenAI-compatible
provider. llama.cpp supports OpenAI-style tools with `--jinja`, exposes direct
context and KV controls, and can preserve supported reasoning history. See the
[OpenCode provider guide](https://opencode.ai/docs/providers) and
[llama-server documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md).

A sensible RTX 5090 starting point is a Q5 or Q6 Unsloth GGUF, one server slot,
64K or 128K context, Flash Attention, q8 KV cache, Jinja tool rendering, and
reasoning preservation. Q5 or Q6 weights cost more VRAM than the current
Q4_K_M but may retain better format adherence. There is not yet controlled
Qwen3.8 tool-use data proving the size of that gain.

```powershell
llama-server.exe `
  -m D:\models\Qwen3.8-27B-Q5_K_M.gguf `
  --host 127.0.0.1 `
  --port 8080 `
  --ctx-size 131072 `
  --n-gpu-layers 999 `
  --flash-attn on `
  --cache-type-k q8_0 `
  --cache-type-v q8_0 `
  --parallel 1 `
  --jinja `
  --reasoning-preserve
```

Use the current llama.cpp release because Qwen3.8 support is new. Confirm the
tool-aware template at `http://127.0.0.1:8080/props` before trusting an agent
run.

### SGLang: strongest exact-hardware recipe

SGLang's official Qwen3.8 cookbook has a verified RTX 5090 NVFP4 setup. It
enables `--reasoning-parser qwen3` and `--tool-call-parser qwen3_coder`. The
cookbook says that without those parsers, a harness receives raw tool syntax
instead of structured `tool_calls`. See the
[SGLang Qwen3.8-27B cookbook](https://docs.sglang.io/cookbook/autoregressive/Qwen/Qwen3.8-27B).

This is the most compelling option if WSL2 or Linux is acceptable. It uses a
Qwen-specific tool parser instead of relying on a generic compatibility path.
It is a larger setup than llama.cpp, and native Windows is not its normal
deployment target.

### vLLM: good dedicated server, second choice here

The official vLLM recipe requires vLLM 0.17.0 or newer. Its one-GPU Blackwell
NVFP4 command uses `--reasoning-parser qwen3`,
`--enable-auto-tool-choice`, and `--tool-call-parser qwen3_coder`. The recipe
lists about 24.6 GiB for the NVFP4 weights, which fits a 32GB 5090 before KV
cache and runtime overhead. See the
[vLLM Qwen3.8-27B recipe](https://recipes.vllm.ai/Qwen/Qwen3.8-27B).

vLLM is attractive for a shared or high-throughput server. For one Windows
desktop and one OpenCode session, llama.cpp is simpler, while SGLang has the
more explicit exact-5090 verification.

## A fair A/B test

Do not judge the runtimes from one successful edit. Use the same GGUF quality,
sampling values, OpenCode version, tool set, and prompts where possible.

1. Run 20 clean-context single-tool calls and record structured-call success.
2. Run 10 multi-step tasks which require at least five tool calls each.
3. Run one repository task past 40K input tokens and another past 60K.
4. Record malformed arguments, raw XML, unknown tool names, renderer errors,
   retry counts, context at failure, and whether a new user turn recovers.
5. Compare Ollama 64K, llama.cpp 128K, and SGLang with its Qwen parsers.

The current Ollama result already supplies a baseline: 5 of 5 clean-context
tool calls succeeded, while realistic OpenCode sessions failed near the 32K
allocation with a repeatable transcript-rendering error.

## Recommendation

I would not replace Ollama before testing the configuration it now documents
for OpenCode. Raise the real allocation to 64K, add matching OpenCode limits,
and use Flash Attention plus q8 KV cache. That directly addresses the strongest
local evidence and costs little.

If the `no user query found in messages` error survives that change, stop
tuning Ollama templates. Move the model to `llama-server` for a native-Windows
A/B test. If that still loses tool calls, use the SGLang NVFP4 recipe in WSL2.
Its explicit Qwen3.8 parsers and verified RTX 5090 configuration make it the
best high-confidence serving path found in this research.

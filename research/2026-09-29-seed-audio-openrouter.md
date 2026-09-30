# Seed Audio 1.0 on OpenRouter

Checked September 29, 2026. The initial research was read-only. A later setup
created three original synthetic reference voices and tested one reference-backed
request, costing $0.1828 in total.

## What the API supports

[Seed Audio 1.0](https://openrouter.ai/bytedance-seed/seed-audio-1-0) generates
speech and other audio from a descriptive text prompt. The model is
non-streaming, with a maximum of 120 seconds of generated audio per request.
It costs $0.0025 per generated second, or $0.15 per minute. A full two-minute
result costs $0.30 at the published rate. These are output-duration charges,
not the generic per-character TTS pricing described elsewhere in the docs.

The [model-specific API guide](https://openrouter.ai/bytedance-seed/seed-audio-1-0/llms.txt)
confirms `POST https://openrouter.ai/api/v1/audio/speech`. Required JSON fields
are `model` and `input`. Optional `voice` is a provider-specific speaker ID.
`response_format` accepts `mp3` or `pcm`, with PCM the default. Successful
responses contain raw audio bytes, not JSON or base64. Errors contain JSON.
The `X-Generation-Id` response header identifies the generation.

The [speech-model catalog](https://openrouter.ai/api/v1/models?output_modalities=speech)
lists Seed Audio. It is not included in the unfiltered catalog used for chat
models. Its `supported_voices` is null. The
[Seed endpoint metadata](https://openrouter.ai/api/v1/models/bytedance-seed/seed-audio-1-0/endpoints)
advertises reference-audio voice cloning, multiple audio references, and image
references. These are listed capabilities, not successful-generation evidence.

## Consistent voices

Use a saved reference recording rather than redesigning a speaker in each
prompt. The model page explicitly supports reference audio for voice cloning.
This is stateless: each generation sends the same recording again. A local
profile name is not a voice registered on the provider.

There is no published Seed speaker-ID list in the inspected OpenRouter sources.
Names such as `alloy` in generic examples belong to other providers. Do not
assume they work here. A real Seed speaker ID can be stored once its source
and behavior have been verified.

The [speech request schema](https://openrouter.ai/docs/api/api-reference/tts/create-speech.md)
accepts an audio reference and an optional transcript:

```json
{
  "model": "bytedance-seed/seed-audio-1-0",
  "input": "Use the reference speaker. Read clearly: Welcome to the project.",
  "response_format": "mp3",
  "input_references": [
    {
      "type": "input_audio",
      "input_audio": { "data": "<base64 audio bytes>", "format": "wav" }
    },
    { "type": "text", "text": "Exact words spoken in the reference recording." }
  ]
}
```

This body follows the public schema and advertised Seed capability. It has not
been tested against a paid Seed request. The
[TTS guide](https://openrouter.ai/docs/guides/overview/multimodal/tts.md)
says one reference, while the newer schema permits up to three. The launcher
uses one as the conservative overlap. The guide caps references at 15 MiB of
decoded audio. The launcher accepts WAV or MP3 references and MP3 output.
Seed-specific preferred reference length and codec constraints are not documented
in the inspected sources.

### Practical recording advice

These are recommendations, not Seed guarantees:

- Use a short, clean recording with one speaker, no background music, and
  representative delivery. A 10-to-20-second sample is a reasonable starting
  experiment, not a published Seed requirement.
- Use only your own voice or one you have permission to upload and reuse.
  Each request uploads the recording and its transcript to OpenRouter and Seed.
- Keep the recording unchanged for a recurring speaker. Save its exact
  transcript when possible. Re-recording changes the identity reference.
- Keep delivery instructions stable and separate them clearly from the words
  to speak. Example wording is descriptive prompting, not a special markup
  language. Listen for unwanted spoken directions.
- Start with a brief sample. Compare repeated generations before producing
  a series. Reference cloning improves the identity cue but does not guarantee
  identical timbre, accent, or delivery across requests.
- Split longer narration into natural sections that fit the two-minute output
  limit. Keep the same reference and delivery instructions for every section.
  Check transitions and pronunciation before joining the files.

No documented Seed random-seed control, deterministic identity guarantee,
hard duration-request field, supported-language list, or PCM sample-rate/channel
contract was found. The launcher does not invent these controls. A request
timeout or local cancellation must not be described as stopping provider billing.

## Launcher setup

[Start-OpenRouterAudio.ps1](D:/github/HemSoft/hs-tui-launcher/scripts/Start-OpenRouterAudio.ps1)
is launched as OpenRouter choice `M`, directly below Seedream at `L`.
The bundled [voice slots](D:/github/HemSoft/hs-tui-launcher/scripts/seed-audio-voices.json)
are `narrator`, `guide`, and `character`. They are unconfigured names, not
prebuilt Seed voices. The first interactive run offers reference setup. Saved
profiles live in `~/.config/hs-tui-launcher/seed-audio-voices.json` and store an
absolute sample path, optional transcript, and permission acknowledgement.
Audio recordings themselves are not copied into the repository.

Configure a voice locally without generating or spending credits:

```powershell
.\scripts\Start-OpenRouterAudio.ps1 `
  -SaveVoice narrator `
  -ReferenceAudio 'D:\voices\narrator.wav' `
  -ReferenceText 'The exact words spoken in this sample.' `
  -Consent
```

Preview the request without uploading the reference or calling the API:

```powershell
.\scripts\Start-OpenRouterAudio.ps1 `
  -Voice narrator `
  -Prompt 'Use the reference speaker. Read calmly: Welcome to the project.' `
  -DryRun
```

Remove `-DryRun` to generate after the cost/upload confirmation. The script
requires `OPENROUTER_API_KEY`. It saves MP3 files to the user's Music directory
under `OpenRouter/SeedAudio` and opens the result unless `-NoOpen` is supplied.
The neighboring JSON sidecar records the model, profile name, reference SHA-256,
and generation ID, not the prompt, transcript, audio data, or API key.

`-PromptOnly` explicitly opts out of voice identity. `-Force` skips the paid
request confirmation; it does not remove the requirement for permission when
saving a reference voice. There are no automatic request retries.

## Verification and remaining work

Offline tests cover profile persistence, consent, file prompts, no-network dry
runs, malformed inputs, raw MP3 saving, JSON errors, invalid/empty audio, and
menu placement.

The local setup subsequently generated three fictional voices from descriptions:
a warm American male baritone for `narrator`, a smooth middle-register British
female voice for `guide`, and a higher-register bright American female voice
for `character`. These are design intentions, not listening-verified properties.
Their MP3 clips are 25.31, 22.83, and 19.41 seconds long. FFmpeg decoded all
three successfully. The samples are stored outside the repository and the local
voice registry points to them.

One additional live request using the narrator reference produced a valid MP3.
OpenRouter reported $0.1686 for the three initial clips and $0.0142 for the reuse
check, or $0.1828 total. This verifies paid API access and acceptance of one
reference-backed request, not perceptual voice fidelity or identity stability.
Exact reference transcripts were left blank because no transcription was
verified. Listen to the samples and repeated outputs before promising a stable
speaker identity.

The research child produced an artifact from parent-fetched primary-source
snapshots, but its run was marked failed because its configured web tools were
unavailable. The findings above were checked against those official snapshots;
the child run is not a successful independent research gate.

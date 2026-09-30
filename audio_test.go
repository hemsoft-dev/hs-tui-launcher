package main

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func audioScript(t *testing.T) string {
	t.Helper()
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Join(cwd, "scripts", "Start-OpenRouterAudio.ps1")
}

func audioCommand(t *testing.T, args ...string) ([]byte, error) {
	t.Helper()
	command := exec.Command("pwsh", append([]string{"-NoProfile", "-File", audioScript(t)}, args...)...)
	// Never use real credentials in these tests, including subprocess inheritance.
	command.Env = append(os.Environ(), "OPENROUTER_API_KEY=")
	return command.CombinedOutput()
}

func saveAudioVoice(t *testing.T) (string, string) {
	t.Helper()
	dir := t.TempDir()
	clip := filepath.Join(dir, "voice sample.wav")
	if err := os.WriteFile(clip, []byte("RIFF-test-WAVE-reference"), 0o600); err != nil {
		t.Fatal(err)
	}
	registry := filepath.Join(dir, "voices.json")
	out, err := audioCommand(t, "-VoicesFile", registry, "-SaveVoice", "narrator", "-ReferenceAudio", clip, "-ReferenceText", "private reference transcript", "-Consent")
	if err != nil {
		t.Fatalf("save voice: %v\n%s", err, out)
	}
	return registry, clip
}

func TestSeedAudioDryRunWithSavedReferenceDoesNotUploadOrSpend(t *testing.T) {
	registry, clip := saveAudioVoice(t)
	dir := filepath.Join(t.TempDir(), "audio")
	out, err := audioCommand(t, "-VoicesFile", registry, "-Voice", "narrator", "-Prompt", "private production script", "-OutputDirectory", dir, "-DryRun")
	if err != nil {
		t.Fatalf("dry run: %v\n%s", err, out)
	}
	for _, secret := range []string{"private production script", "private reference transcript", "RIFF-test", clip} {
		if strings.Contains(string(out), secret) {
			t.Fatalf("preview exposed private data: %q", secret)
		}
	}
	var result map[string]any
	if err := json.Unmarshal(out, &result); err != nil {
		t.Fatalf("invalid JSON: %v\n%s", err, out)
	}
	if result["Model"] != "bytedance-seed/seed-audio-1-0" || result["VoiceMode"] != "reference-audio" || result["ResponseFormat"] != "mp3" || result["EstimatedMaxCostUSD"] != 0.3 {
		t.Fatalf("unexpected preview: %#v", result)
	}
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Fatalf("dry run created output directory: %v", err)
	}
}

func TestSeedAudioReadsPromptFileAndRequiresExplicitPromptOnly(t *testing.T) {
	file := filepath.Join(t.TempDir(), "audio prompt.txt")
	if err := os.WriteFile(file, []byte("private prompt\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	out, err := audioCommand(t, "-Prompt", `"`+file+`"`, "-PromptOnly", "-DryRun")
	if err != nil {
		t.Fatalf("file preview: %v\n%s", err, out)
	}
	var result map[string]any
	if err := json.Unmarshal(out, &result); err != nil {
		t.Fatal(err)
	}
	if result["PromptLength"] != float64(len("private prompt")) || result["VoiceMode"] != "prompt-only" || strings.Contains(string(out), "private prompt") {
		t.Fatalf("unexpected preview: %s", out)
	}
}

func TestSeedAudioRejectsInvalidInputsBeforeNetwork(t *testing.T) {
	dir := t.TempDir()
	clip := filepath.Join(dir, "clip.wav")
	if err := os.WriteFile(clip, []byte("sample"), 0o600); err != nil {
		t.Fatal(err)
	}
	empty := filepath.Join(dir, "empty.txt")
	if err := os.WriteFile(empty, []byte(" \n"), 0o600); err != nil {
		t.Fatal(err)
	}
	tests := []struct {
		name string
		args []string
		want string
	}{
		{"consent", []string{"-SaveVoice", "narrator", "-ReferenceAudio", clip, "-VoicesFile", filepath.Join(dir, "voices.json")}, "require Consent"},
		{"both identities", []string{"-SaveVoice", "narrator", "-ReferenceAudio", clip, "-SpeakerId", "test", "-Consent"}, "exactly one"},
		{"unknown voice", []string{"-Voice", "missing", "-Prompt", "test", "-DryRun"}, "Unknown voice"},
		{"empty file", []string{"-Prompt", empty, "-PromptOnly", "-DryRun"}, "prompt file is empty"},
		{"empty prompt", []string{"-PromptOnly", "-DryRun"}, "audio prompt is required"},
		{"mixed modes", []string{"-Voice", "narrator", "-Prompt", "test", "-PromptOnly", "-DryRun"}, "cannot be combined with Voice"},
		{"missing key", []string{"-Prompt", "test", "-PromptOnly", "-Force"}, "OPENROUTER_API_KEY is not set"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			out, err := audioCommand(t, test.args...)
			if err == nil || !strings.Contains(string(out), test.want) {
				t.Fatalf("want %q error, got %v\n%s", test.want, err, out)
			}
		})
	}
}

func TestSeedAudioDoesNotInventVoiceIDs(t *testing.T) {
	out, err := audioCommand(t, "-ListVoices", "-VoicesFile", filepath.Join(t.TempDir(), "missing.json"))
	if err != nil {
		t.Fatal(err)
	}
	var voices []struct {
		Name       string
		Configured bool
	}
	if err := json.Unmarshal(out, &voices); err != nil {
		t.Fatal(err)
	}
	if len(voices) != 3 {
		t.Fatalf("voices = %s", out)
	}
	for _, v := range voices {
		if v.Configured {
			t.Fatalf("bundled voice %q was advertised as configured", v.Name)
		}
	}
	out, err = audioCommand(t, "-Prompt", "test", "-DryRun", "-VoicesFile", filepath.Join(t.TempDir(), "missing.json"))
	if err == nil || !strings.Contains(string(out), "Voice is not configured") {
		t.Fatalf("unconfigured voice accepted: %v\n%s", err, out)
	}
}

func TestSeedAudioVerifiedSpeakerIDProfilePreview(t *testing.T) {
	file := filepath.Join(t.TempDir(), "voices.json")
	out, err := audioCommand(t, "-VoicesFile", file, "-SaveVoice", "test-speaker", "-SpeakerId", "test-only-provider-id")
	if err != nil {
		t.Fatalf("save ID: %v\n%s", err, out)
	}
	out, err = audioCommand(t, "-VoicesFile", file, "-Voice", "test-speaker", "-Prompt", "test", "-DryRun")
	if err != nil || !strings.Contains(string(out), `"VoiceMode":"speaker-id"`) {
		t.Fatalf("ID preview: %v\n%s", err, out)
	}
}

func TestSeedAudioInteractiveNumberedVoicesAndOutputFolder(t *testing.T) {
	wrapper := `param($TargetScript, $VoicesFile, $OutputDirectory, $Mode)
$global:audioTestState = @{ promptCount = 0; outputPrompt = ''; requestCount = 0 }
$global:audioTestState.answers = switch ($Mode) {
    'alternate' { @('private prompt', '2', ('"' + $OutputDirectory + '"'), 'yes') }
    'invalid' { @('private prompt', '0', '99', 'not-a-number', '3', $OutputDirectory, 'yes') }
    'defaults' { @('private prompt', '', '', 'n') }
    'explicit' { @('private prompt', '1', 'yes') }
}
function Read-Host {
    param($Prompt)
    if ($Prompt -like 'Output folder*') { $global:audioTestState.outputPrompt = $Prompt }
    if ($Mode -eq 'defaults' -and $Prompt -like 'Generate this audio*' -and $Voice -ne 'narrator') { throw 'Enter did not select narrator' }
    if ($global:audioTestState.promptCount -ge $global:audioTestState.answers.Count) { throw 'Unexpected extra prompt' }
    $answer = $global:audioTestState.answers[$global:audioTestState.promptCount]
    $global:audioTestState.promptCount++
    return $answer
}
function Invoke-WebRequest {
    param($Uri, $Method, $Headers, $ContentType, $Body, $OutFile, [switch] $PassThru, [switch] $SkipHttpErrorCheck, $TimeoutSec)
    $global:audioTestState.requestCount++
    $request = $Body | ConvertFrom-Json
    $expected = switch ($Mode) { 'alternate' { 'guide-id' }; 'invalid' { 'character-id' }; default { 'narrator-id' } }
    if ($request.voice -ne $expected -or $request.input -ne 'private prompt') { throw 'Wrong selected voice or prompt' }
    if ((Split-Path -Parent $OutFile) -ne $OutputDirectory) { throw 'Request was not downloaded to chosen folder' }
    if (-not (Test-Path -LiteralPath $OutFile -PathType Leaf)) { throw 'Folder write access was not checked before the request' }
    [IO.File]::WriteAllBytes($OutFile, [byte[]](73,68,51,4,0,0,0,0,0,0))
    return [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'audio/mpeg' } }
}
if ($Mode -eq 'explicit') { & $TargetScript -VoicesFile $VoicesFile -OutputDirectory $OutputDirectory -NoOpen }
else { & $TargetScript -VoicesFile $VoicesFile -NoOpen }
if ($Mode -eq 'defaults') {
    if ($global:audioTestState.requestCount -ne 0 -or $global:audioTestState.outputPrompt -notlike '*SeedAudio]*') { throw 'Default folder or cancellation was incorrect' }
}
elseif ($global:audioTestState.requestCount -ne 1) { throw 'Expected exactly one mocked request' }
if ($Mode -eq 'explicit' -and $global:audioTestState.outputPrompt) { throw 'Explicit output folder prompted again' }
if ($global:audioTestState.promptCount -ne $global:audioTestState.answers.Count) { throw 'Not all expected prompts were shown' }
`
	for _, mode := range []string{"alternate", "invalid", "defaults", "explicit"} {
		t.Run(mode, func(t *testing.T) {
			dir := t.TempDir()
			voices := []map[string]any{}
			for _, name := range []string{"narrator", "guide", "character"} {
				voices = append(voices, map[string]any{
					"name": name, "description": "Description for " + name, "speaker_id": name + "-id",
					"reference_audio": "", "reference_text": "", "consent": false,
				})
			}
			data, err := json.Marshal(map[string]any{"version": 1, "voices": voices})
			if err != nil {
				t.Fatal(err)
			}
			registry := filepath.Join(dir, "voices.json")
			if err := os.WriteFile(registry, data, 0o600); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(dir, "interactive.ps1")
			if err := os.WriteFile(path, []byte(wrapper), 0o600); err != nil {
				t.Fatal(err)
			}
			outputDir := filepath.Join(dir, "alternate audio folder")
			cmd := exec.Command("pwsh", "-NoProfile", "-File", path, "-TargetScript", audioScript(t), "-VoicesFile", registry, "-OutputDirectory", outputDir, "-Mode", mode)
			cmd.Env = append(os.Environ(), "OPENROUTER_API_KEY=test-only-key")
			out, err := cmd.CombinedOutput()
			if err != nil {
				t.Fatalf("interactive %s: %v\n%s", mode, err, out)
			}
			for _, label := range []string{"1. narrator: Description for narrator", "2. guide: Description for guide", "3. character: Description for character"} {
				if !strings.Contains(string(out), label) {
					t.Fatalf("missing numbered choice %q:\n%s", label, out)
				}
			}
			temps, err := filepath.Glob(filepath.Join(outputDir, ".seed-audio-*.tmp"))
			if err != nil || len(temps) != 0 {
				t.Fatalf("temporary audio files left behind: %v %v", temps, err)
			}
			files, err := filepath.Glob(filepath.Join(outputDir, "*.mp3"))
			if err != nil {
				t.Fatal(err)
			}
			if mode == "defaults" {
				if len(files) != 0 || !strings.Contains(string(out), "Audio generation cancelled") {
					t.Fatalf("cancelled generation saved audio: %s", out)
				}
				return
			}
			if len(files) != 1 {
				t.Fatalf("files in chosen folder = %v", files)
			}
			metadata, err := os.ReadFile(files[0] + ".json")
			if err != nil {
				t.Fatal(err)
			}
			wantVoice := map[string]string{"alternate": "guide", "invalid": "character", "explicit": "narrator"}[mode]
			var result map[string]any
			if err := json.Unmarshal(metadata, &result); err != nil || result["voice_profile"] != wantVoice {
				t.Fatalf("wrong voice metadata: %v\n%s", err, metadata)
			}
		})
	}
}

func TestSeedAudioRejectsOutputFileBeforeSpending(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "not-a-folder")
	if err := os.WriteFile(file, []byte("leave unchanged"), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, output := range []string{file, filepath.Join(file, "child")} {
		out, err := audioCommand(t, "-Prompt", "test", "-PromptOnly", "-OutputDirectory", output, "-Force")
		if err == nil || !strings.Contains(string(out), "points to a file") {
			t.Fatalf("bad folder accepted: %v\n%s", err, out)
		}
	}
}

func TestSeedAudioSaveVoicePreservesNumbering(t *testing.T) {
	registry, _ := saveAudioVoice(t)
	out, err := audioCommand(t, "-ListVoices", "-VoicesFile", registry)
	if err != nil {
		t.Fatalf("list voices: %v\n%s", err, out)
	}
	var voices []struct{ Name string }
	if err := json.Unmarshal(out, &voices); err != nil {
		t.Fatal(err)
	}
	for i, want := range []string{"narrator", "guide", "character"} {
		if i >= len(voices) || voices[i].Name != want {
			t.Fatalf("voice order changed: %s", out)
		}
	}
}

func TestSeedAudioMockedBinaryResponseAndFailures(t *testing.T) {
	registry, _ := saveAudioVoice(t)
	wrapper := `param($TargetScript, $OutputDirectory, $VoicesFile, $Mode)
function Invoke-WebRequest {
    param($Uri, $Method, $Headers, $ContentType, $Body, $OutFile, [switch] $PassThru, [switch] $SkipHttpErrorCheck, $TimeoutSec)
    $r = $Body | ConvertFrom-Json
    if ($Uri -ne 'https://openrouter.ai/api/v1/audio/speech' -or $Method -ne 'Post' -or
        $r.model -ne 'bytedance-seed/seed-audio-1-0' -or $r.response_format -ne 'mp3' -or
        $r.input -ne 'private production script' -or $Headers.Authorization -ne 'Bearer test-only-key' -or
        $r.PSObject.Properties.Name -contains 'voice' -or $r.input_references.Count -ne 2 -or
        $r.input_references[0].input_audio.format -ne 'wav' -or
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($r.input_references[0].input_audio.data)) -ne 'RIFF-test-WAVE-reference' -or
        $r.input_references[1].text -ne 'private reference transcript') { throw 'Unexpected request' }
    $status = 200; $mime = 'audio/mpeg'; $bytes = [byte[]](73,68,51,4,0,0,0,0,0,0)
    switch ($Mode) {
        'http' { $status = 402; $mime = 'application/json'; $bytes = [Text.Encoding]::UTF8.GetBytes('private error with test-only-key') }
        'mime' { $mime = 'application/json' }
        'empty' { $bytes = [byte[]]@() }
        'invalid' { $bytes = [byte[]](1,2,3) }
    }
    [IO.File]::WriteAllBytes($OutFile, $bytes)
    return [pscustomobject]@{ StatusCode = $status; Headers = @{ 'Content-Type' = $mime } }
}
& $TargetScript -VoicesFile $VoicesFile -Voice narrator -Prompt 'private production script' -OutputDirectory $OutputDirectory -Force -NoOpen
`
	for _, mode := range []string{"success", "http", "mime", "empty", "invalid"} {
		t.Run(mode, func(t *testing.T) {
			dir := t.TempDir()
			path := filepath.Join(dir, "mock.ps1")
			if err := os.WriteFile(path, []byte(wrapper), 0o600); err != nil {
				t.Fatal(err)
			}
			outputDir := filepath.Join(dir, "audio")
			cmd := exec.Command("pwsh", "-NoProfile", "-File", path, "-TargetScript", audioScript(t), "-OutputDirectory", outputDir, "-VoicesFile", registry, "-Mode", mode)
			cmd.Env = append(os.Environ(), "OPENROUTER_API_KEY=test-only-key")
			out, err := cmd.CombinedOutput()
			for _, private := range []string{"test-only-key", "private production script", "private reference transcript"} {
				if strings.Contains(string(out), private) {
					t.Fatalf("leaked private data: %s", out)
				}
			}
			files, globErr := filepath.Glob(filepath.Join(outputDir, "*.mp3"))
			if globErr != nil {
				t.Fatal(globErr)
			}
			if mode != "success" {
				if err == nil || len(files) != 0 {
					t.Fatalf("invalid response saved audio: %v files=%v\n%s", err, files, out)
				}
				return
			}
			if err != nil || len(files) != 1 {
				t.Fatalf("mock save failed: %v files=%v\n%s", err, files, out)
			}
			content, err := os.ReadFile(files[0])
			if err != nil || !bytes.Equal(content, []byte{73, 68, 51, 4, 0, 0, 0, 0, 0, 0}) {
				t.Fatalf("binary bytes changed: %v %v", content, err)
			}
			metadata, err := os.ReadFile(files[0] + ".json")
			if err != nil || bytes.Contains(metadata, []byte("private")) || !bytes.Contains(metadata, []byte("narrator")) {
				t.Fatalf("unexpected metadata: %v\n%s", err, metadata)
			}
		})
	}
}

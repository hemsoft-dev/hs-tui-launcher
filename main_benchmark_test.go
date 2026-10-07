package main

import (
	"os"
	"testing"
	"time"
)

var benchmarkInvocation selectionInvocation
var benchmarkInvocationRegression []byte

func BenchmarkSelectionInvocation(b *testing.B) {
	regression := os.Getenv("HS_PERFORMANCE_FIXTURE_REGRESSION") == "1"
	cases := []struct {
		name    string
		command string
	}{
		{"plain", "tool --model sample --reasoning high"},
		{"quoted", `& "C:/Program Files/Example/tool.exe" "two words" "" "embedded'quote"`},
		{"unicode", `tool "雪 café 🚀" "説明 with spaces"`},
		{"repo_root", `& "$repoRoot/scripts/tool.exe" --flag value`},
		{"long", `tool --model sample --reasoning high --session "session with spaces" --config "C:/A Long Folder/config.json" --empty "" --unicode "雪 café 🚀"`},
	}
	for _, fixture := range cases {
		b.Run(fixture.name, func(b *testing.B) {
			b.ReportAllocs()
			for b.Loop() {
				invocation, err := parseSelectionCommand(fixture.command)
				if err != nil {
					b.Fatal(err)
				}
				benchmarkInvocation = invocation
				if regression {
					benchmarkInvocationRegression = make([]byte, 4096)
					time.Sleep(100 * time.Microsecond)
				}
			}
		})
	}
}

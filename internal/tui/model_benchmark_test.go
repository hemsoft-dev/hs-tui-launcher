package tui

import (
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/HemSoft/hs-tui-launcher/internal/config"
)

var benchmarkViewContent string
var benchmarkViewRegression []byte

func BenchmarkLauncherView(b *testing.B) {
	// Fix terminal-dependent color behavior for repeatable headless measurements.
	b.Setenv("NO_COLOR", "1")
	b.Setenv("TERM", "dumb")
	regression := os.Getenv("HS_PERFORMANCE_FIXTURE_REGRESSION") == "1"
	for _, mode := range []string{"menu", "choices"} {
		for _, size := range []int{8, 32, 128} {
			for _, width := range []int{40, 120} {
				for _, text := range []string{"ascii", "unicode"} {
					name := fmt.Sprintf("%s/size_%d/width_%d/%s", mode, size, width, text)
					b.Run(name, func(b *testing.B) {
						label, description := "Model", "A representative model description"
						if text == "unicode" {
							label, description = "模型 café 🚀", "説明 with accented and wide characters 雪"
						}
						items := make([]config.LaunchItem, size)
						choices := make([]config.LaunchChoice, size)
						for index := range items {
							items[index] = config.LaunchItem{Name: fmt.Sprintf("%s %d", label, index), Description: description}
							choices[index] = config.LaunchChoice{Name: fmt.Sprintf("%s %d (detail)", label, index), Description: description}
						}
						model := New(config.Config{Title: "Benchmark", Items: items})
						model.width, model.height, model.cursor = width, 24, size-1
						if mode == "choices" {
							model.choiceParent = &launchItem{LaunchItem: config.LaunchItem{Name: label, Choices: choices}, Number: 1}
						}
						b.ReportAllocs()
						for b.Loop() {
							benchmarkViewContent = model.View().Content
							if regression {
								benchmarkViewRegression = make([]byte, 4096)
								time.Sleep(100 * time.Microsecond)
							}
						}
					})
				}
			}
		}
	}
}

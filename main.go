package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	tea "charm.land/bubbletea/v2"
	"github.com/HemSoft/hs-tui-launcher/internal/config"
	"github.com/HemSoft/hs-tui-launcher/internal/tui"
	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

func main() {
	var configPath string
	var printConfig bool
	var selectionFile string

	rootCmd := &cobra.Command{
		Use:           "hs-tui-launcher",
		Short:         "Terminal launcher overlay for local AI CLIs",
		SilenceErrors: true,
		SilenceUsage:  true,
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, source, err := config.Load(configPath)
			if err != nil {
				return err
			}

			if printConfig {
				out, err := yaml.Marshal(cfg)
				if err != nil {
					return fmt.Errorf("marshal config: %w", err)
				}
				cmd.Print(string(out))
				return nil
			}

			if !hasInteractiveTerminal() {
				return fmt.Errorf("hs-tui-launcher requires an interactive terminal; run .\\run.ps1 from PowerShell or use --print-config")
			}

			model := tui.New(cfg, source)
			finalModel, err := tea.NewProgram(model).Run()
			if err != nil {
				return err
			}

			if strings.TrimSpace(selectionFile) == "" {
				return nil
			}

			final, ok := finalModel.(tui.Model)
			if !ok {
				return fmt.Errorf("unexpected launcher model %T", finalModel)
			}

			item, ok := final.SelectedItem()
			if !ok {
				return nil
			}

			return writeSelection(selectionFile, item)
		},
	}

	rootCmd.Flags().StringVarP(&configPath, "config", "c", "", "path to launcher YAML config")
	rootCmd.Flags().BoolVar(&printConfig, "print-config", false, "print the resolved launcher config and exit")
	rootCmd.Flags().StringVar(&selectionFile, "selection-file", "", "write selected launcher item JSON to a file and exit")
	if err := rootCmd.Flags().MarkHidden("selection-file"); err != nil {
		panic(err)
	}

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

type selectionOutput struct {
	Name       string   `json:"name"`
	Command    string   `json:"command"`
	WorkingDir string   `json:"working_dir,omitempty"`
	Env        []string `json:"env,omitempty"`
}

func writeSelection(path string, item config.LaunchItem) error {
	file, err := os.Create(filepath.Clean(path))
	if err != nil {
		return fmt.Errorf("create selection file: %w", err)
	}
	defer file.Close()

	return json.NewEncoder(file).Encode(selectionOutput{
		Name:       item.Name,
		Command:    item.Command,
		WorkingDir: item.WorkingDir,
		Env:        item.Env,
	})
}

func hasInteractiveTerminal() bool {
	stdin, err := os.Stdin.Stat()
	if err != nil {
		return false
	}
	stdout, err := os.Stdout.Stat()
	if err != nil {
		return false
	}

	return stdin.Mode()&os.ModeCharDevice != 0 && stdout.Mode()&os.ModeCharDevice != 0
}

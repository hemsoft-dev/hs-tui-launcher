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
			cfg, _, err := config.Load(configPath)
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
				return fmt.Errorf("hs-tui-launcher requires an interactive terminal; use run.ps1 on PowerShell, run.sh on macOS/Linux, or --print-config")
			}

			model := tui.New(cfg)
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
	Executable string   `json:"executable"`
	Args       []string `json:"args,omitempty"`
	WorkingDir string   `json:"working_dir,omitempty"`
	Env        []string `json:"env,omitempty"`
}

func writeSelection(path string, item config.LaunchItem) error {
	// run.ps1 owns process launch after Bubble Tea restores the terminal; the Go side writes
	// a structured selection so the child process does not inherit the TUI's terminal state.
	invocation, err := parseSelectionCommand(item.Command)
	if err != nil {
		return err
	}

	file, err := os.Create(filepath.Clean(path))
	if err != nil {
		return fmt.Errorf("create selection file: %w", err)
	}
	defer file.Close()

	return json.NewEncoder(file).Encode(selectionOutput{
		Name:       item.Name,
		Executable: invocation.executable,
		Args:       invocation.args,
		WorkingDir: item.WorkingDir,
		Env:        item.Env,
	})
}

type selectionInvocation struct {
	executable string
	args       []string
}

func parseSelectionCommand(command string) (selectionInvocation, error) {
	tokens, err := tokenizeSelectionCommand(command)
	if err != nil {
		return selectionInvocation{}, err
	}
	if len(tokens) == 0 {
		return selectionInvocation{}, fmt.Errorf("selection command is required")
	}
	if tokens[0] == "&" {
		tokens = tokens[1:]
	}
	if len(tokens) == 0 {
		return selectionInvocation{}, fmt.Errorf("selection command executable is required")
	}
	if tokens[0] == "&" {
		return selectionInvocation{}, fmt.Errorf("selection command executable cannot be the call operator")
	}

	executable, err := resolveSelectionExecutable(tokens[0])
	if err != nil {
		return selectionInvocation{}, err
	}
	if strings.TrimSpace(executable) == "" {
		return selectionInvocation{}, fmt.Errorf("selection command executable cannot be empty")
	}

	return selectionInvocation{
		executable: executable,
		args:       append([]string(nil), tokens[1:]...),
	}, nil
}

func tokenizeSelectionCommand(command string) ([]string, error) {
	var tokens []string
	var token strings.Builder
	var quote rune
	tokenStarted := false
	leadingToken := true

	flushToken := func() {
		if tokenStarted {
			tokens = append(tokens, token.String())
			token.Reset()
			tokenStarted = false
			leadingToken = false
		}
	}

	for _, char := range command {
		if quote != 0 {
			if char == quote {
				quote = 0
				continue
			}
			token.WriteRune(char)
			tokenStarted = true
			continue
		}

		switch {
		case char == '\'' || char == '"':
			quote = char
			tokenStarted = true
		case strings.ContainsRune(" \t\r\n", char):
			flushToken()
		case strings.ContainsRune(";|<>`", char):
			return nil, fmt.Errorf("selection command contains unsupported PowerShell metacharacter %q", char)
		case char == '&':
			if leadingToken && !tokenStarted {
				tokens = append(tokens, "&")
				leadingToken = false
				continue
			}
			return nil, fmt.Errorf("selection command contains unsupported PowerShell metacharacter %q", char)
		default:
			token.WriteRune(char)
			tokenStarted = true
		}
	}
	if quote != 0 {
		return nil, fmt.Errorf("selection command contains an unterminated quote")
	}
	flushToken()

	return tokens, nil
}

func resolveSelectionExecutable(executable string) (string, error) {
	const repoRootVariable = "$repoRoot"
	if executable != repoRootVariable &&
		!strings.HasPrefix(executable, repoRootVariable+`\`) &&
		!strings.HasPrefix(executable, repoRootVariable+"/") {
		return executable, nil
	}

	suffix := strings.TrimPrefix(executable, repoRootVariable)
	suffix = strings.TrimLeft(suffix, `\/`)
	if strings.TrimSpace(suffix) == "" {
		return "", fmt.Errorf("selection command executable cannot be only %s", repoRootVariable)
	}

	workingDir, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("resolve repository root: %w", err)
	}

	return filepath.Join(workingDir, filepath.FromSlash(strings.ReplaceAll(suffix, `\`, `/`))), nil
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

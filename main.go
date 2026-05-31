package main

import (
	"fmt"
	"os"

	tea "charm.land/bubbletea/v2"
	"github.com/HemSoft/hs-tui-launcher/internal/config"
	"github.com/HemSoft/hs-tui-launcher/internal/tui"
	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

func main() {
	var configPath string
	var printConfig bool

	rootCmd := &cobra.Command{
		Use:   "hs-tui-launcher",
		Short: "Terminal launcher overlay for local AI CLIs",
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

			model := tui.New(cfg, source)
			_, err = tea.NewProgram(model).Run()
			return err
		},
	}

	rootCmd.Flags().StringVarP(&configPath, "config", "c", "", "path to launcher YAML config")
	rootCmd.Flags().BoolVar(&printConfig, "print-config", false, "print the resolved launcher config and exit")

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

package fixture

import (
	"context"
	"os/exec"
)

// Scanner fixture only: these commands are never executed.
func variableGoShellCommands(ctx context.Context, untrustedFixtureInput string) {
	_ = exec.Command("sh", "-c", untrustedFixtureInput)
	_ = exec.CommandContext(ctx, "pwsh", "-Command", untrustedFixtureInput)
}

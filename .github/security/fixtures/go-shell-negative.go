package fixture

import (
	"context"
	"os/exec"
)

// Scanner fixture only: literal shell commands must not trigger the variable-input rule.
func literalGoShellCommands(ctx context.Context) {
	_ = exec.Command("sh", "-c", "printf fixture")
	_ = exec.CommandContext(ctx, "pwsh", "-Command", "Write-Output fixture")
}

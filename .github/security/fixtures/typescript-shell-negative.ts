import childProcess, { exec, spawn, spawnSync } from "node:child_process";

// Scanner fixture only: literal shell commands must not trigger the variable-input rule.
exec("printf fixture");
childProcess.exec("printf fixture");
spawn("printf fixture", { shell: true });
childProcess.spawnSync("printf fixture", [], { shell: true });
spawnSync("printf fixture", [], { shell: true });
spawn("sh", ["-c", "printf fixture"]);
childProcess.spawnSync("bash", ["-c", "printf fixture"]);
spawnSync("cmd", ["/c", "echo fixture"]);
childProcess.spawn("powershell", ["-Command", "Write-Output fixture"]);
spawn("pwsh", ["-Command", "Write-Output fixture"]);

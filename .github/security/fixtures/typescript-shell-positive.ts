import childProcess, { exec, spawn, spawnSync } from "node:child_process";

declare const untrustedFixtureInput: string;

// Scanner fixture only: these commands are never executed.
exec(untrustedFixtureInput);
childProcess.exec(untrustedFixtureInput);
spawn(untrustedFixtureInput, { shell: true });
childProcess.spawnSync(untrustedFixtureInput, [], { shell: true });
spawnSync(untrustedFixtureInput, [], { shell: true });

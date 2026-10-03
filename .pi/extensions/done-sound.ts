import { existsSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type {
	AgentSettledEvent,
	ExtensionAPI,
	ExtensionUIContext,
} from "@earendil-works/pi-coding-agent";

export interface DoneSoundContext {
	hasUI: boolean;
	cwd: string;
	ui: Pick<ExtensionUIContext, "notify">;
}

export interface DoneSoundAPI extends Pick<ExtensionAPI, "exec"> {
	on(
		event: "agent_settled",
		handler: (event: AgentSettledEvent, context: DoneSoundContext) => Promise<void> | void,
	): () => void;
}

const repositoryRoot = realpathSync(fileURLToPath(new URL("../../", import.meta.url)));
const playbackScript = join(repositoryRoot, "scripts", "Play-DoneSound.ps1");

// Check real paths and stop at a nested repository boundary.
export function belongsToRepository(cwd: string): boolean {
	try {
		let directory = realpathSync(cwd);
		while (true) {
			if (directory === repositoryRoot) return true;
			if (existsSync(join(directory, ".git"))) return false;
			const parent = dirname(directory);
			if (parent === directory) return false;
			directory = parent;
		}
	} catch {
		return false;
	}
}

export function doneSound(pi: DoneSoundAPI) {
	let playing = false;

	// Unlike agent_end, this runs only after retries and queued follow-ups finish.
	pi.on("agent_settled", async (_event, ctx) => {
		if (!ctx.hasUI || process.env.HS_TUI_LAUNCHER_DONE_SOUND === "0" ||
			playing || !belongsToRepository(ctx.cwd)) return;

		playing = true;
		try {
			const result = await pi.exec("pwsh", ["-NoProfile", "-File", playbackScript], {
				cwd: repositoryRoot,
				timeout: 15000,
			});
			if (result.code !== 0 || result.killed) {
				ctx.ui.notify("Completion audio could not play. Check ffplay and assets/done.mp3.", "warning");
			}
		} catch {
			ctx.ui.notify("Completion audio could not start. Check PowerShell and the audio player.", "warning");
		} finally {
			playing = false;
		}
	});
}

// Keep the narrow test boundary assignable from Pi's complete extension API.
const doneSoundExtension: (pi: ExtensionAPI) => void = doneSound;
export default doneSoundExtension;

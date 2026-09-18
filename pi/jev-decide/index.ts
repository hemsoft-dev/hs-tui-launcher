import { defineTool, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type, type Static } from "typebox";
import {
	JEV_ENDPOINT,
	executeJevDecision,
	JevError,
	type JevAuthMaterial,
	type JevDecisionInput,
} from "./jev-core.ts";

const identifier = Type.String({ pattern: "^[A-Za-z][A-Za-z0-9_.-]*$", minLength: 1, maxLength: 128 });
const text = Type.String({ minLength: 1, maxLength: 32_768 });
const criterionText = Type.String({ minLength: 1, maxLength: 2_048 });
const choiceQuestion = Type.Object(
	{
		type: Type.Literal("choice"),
		instructions: Type.String({ minLength: 1, maxLength: 8_192 }),
		criteria: Type.Record(identifier, criterionText, { minProperties: 1, maxProperties: 20 }),
	},
	{ additionalProperties: false },
);
const noulQuestion = Type.Object(
	{
		type: Type.Literal("noul"),
		instructions: Type.String({ minLength: 1, maxLength: 8_192 }),
		criteria: Type.Object(
			{
				true: criterionText,
				false: criterionText,
			},
			{ additionalProperties: false },
		),
	},
	{ additionalProperties: false },
);
const scoreQuestion = Type.Object(
	{
		type: Type.Literal("score"),
		instructions: Type.String({ minLength: 1, maxLength: 8_192 }),
		criteria: Type.Array(criterionText, { minItems: 1, maxItems: 20 }),
	},
	{ additionalProperties: false },
);

const jevDecideParameters = Type.Object(
	{
		state: Type.Union([
			Type.String({ minLength: 1, maxLength: 32_768 }),
			Type.Record(Type.String({ minLength: 1, maxLength: 128 }), Type.Unknown(), { minProperties: 1, maxProperties: 1_000 }),
		]),
		questions: Type.Record(
			identifier,
			Type.Union([choiceQuestion, noulQuestion, scoreQuestion]),
			{ minProperties: 1, maxProperties: 20 },
		),
		sessionId: Type.Optional(Type.String({ minLength: 1, maxLength: 512 })),
		user: Type.Optional(Type.String({ minLength: 1, maxLength: 512 })),
		provider: Type.Optional(Type.Record(Type.String({ minLength: 1, maxLength: 128 }), Type.Unknown(), { maxProperties: 100 })),
		trace: Type.Optional(Type.Record(Type.String({ minLength: 1, maxLength: 128 }), Type.Unknown(), { maxProperties: 100 })),
		timeoutMs: Type.Optional(Type.Integer({ minimum: 1_000, maximum: 120_000 })),
	},
	{ additionalProperties: false },
);

type JevDecideParameters = Static<typeof jevDecideParameters>;

function authMaterial(ctx: ExtensionContext, signal: AbortSignal): Promise<JevAuthMaterial | undefined> {
	return (async () => {
		if (signal.aborted) throw new JevError("cancelled", "Jev consultation was cancelled.");
		const resolved = await ctx.modelRegistry.getProviderAuth("openrouter");
		if (!resolved) return undefined;
		const headers: Record<string, string | undefined> = {};
		for (const [name, value] of Object.entries(resolved.auth.headers ?? {})) {
			if (value !== null) headers[name] = value;
		}
		return { apiKey: resolved.auth.apiKey, headers };
	})();
}

function resultText(execution: Awaited<ReturnType<typeof executeJevDecision>>): string {
	return JSON.stringify(
		{
			model: execution.response.model,
			id: execution.response.id,
			provider: execution.response.provider,
			answers: execution.response.answers,
			usage: execution.response.usage,
			meta: {
				latencyMs: execution.latencyMs,
				requestBytes: execution.requestBytes,
				questionIds: execution.questionIds,
				redacted: execution.redacted,
			},
		},
		null,
		2,
	);
}

function errorResult(error: unknown) {
	const jevError = error instanceof JevError ? error : new JevError("network", "The Jev request could not be completed.", true);
	return {
		content: [{ type: "text" as const, text: `Jev decision unavailable (${jevError.code}): ${jevError.message}` }],
		details: { code: jevError.code, retryable: jevError.retryable },
		isError: true,
	};
}

export const jevDecideTool = defineTool({
	name: "jev_decide",
	label: "Jev Decision",
	description:
		"Ask TypeSafe Jev for a bounded, typed advisory decision over explicit options or criteria. " +
		"The request is sent through Pi's OpenRouter authentication, sensitive values are redacted, and " +
		"the response is schema-validated. Jev cannot grant permissions, approve destructive actions, " +
		"bypass tests, or replace deterministic policy or human review.",
	promptSnippet: "Get a typed advisory choice, gate, or score from Jev",
	promptGuidelines: [
		"Use jev_decide only after gathering facts and stating two or more explicit options or criteria.",
		"Treat jev_decide answers and confidence as advisory evidence; keep permissions, tests, and human approval in charge.",
		"Do not put API keys, tokens, passwords, cookies, private keys, or unnecessary proprietary data in jev_decide state.",
	],
	parameters: jevDecideParameters,
	async execute(_toolCallId, params: JevDecideParameters, signal, onUpdate, ctx) {
		onUpdate?.({
			content: [{ type: "text", text: "Consulting Jev with a redacted, bounded request..." }],
			details: {},
		});
		try {
			const input = params as unknown as JevDecisionInput;
			const execution = await executeJevDecision(
				input,
				{
					resolveAuth: (authSignal) => authMaterial(ctx, authSignal),
					fetch: (url, init) => fetch(url, init),
					endpoint: JEV_ENDPOINT,
				},
				signal,
			);
			return {
				content: [{ type: "text" as const, text: resultText(execution) }],
				details: {
					model: execution.response.model,
					latencyMs: execution.latencyMs,
					requestBytes: execution.requestBytes,
					questionIds: execution.questionIds,
					redacted: execution.redacted,
				},
			};
		} catch (error) {
			return errorResult(error);
		}
	},
});

export default function jevDecideExtension(pi: ExtensionAPI) {
	pi.registerTool(jevDecideTool);
}

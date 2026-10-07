import test from 'node:test';
import assert from 'node:assert/strict';
import { buildDecisionRequest, redactSensitive } from './jev-core.ts';

test('buildDecisionRequest redacts secret fields and inline bearer tokens without mutating state', () => {
  const state = {
    task: 'Choose a safe route',
    credentials: { apiKey: 'sk-live-do-not-send' },
    note: 'Authorization: Bearer abcdefghijklmnop',
  };

  const built = buildDecisionRequest({
    state,
    questions: {
      route: {
        type: 'choice',
        instructions: 'Choose the safer route.',
        criteria: {
          stop: 'Ask for review',
          continue: 'Continue only when harmless',
        },
      },
    },
  });

  assert.equal((built.payload.state as { credentials: string }).credentials, '[REDACTED]');
  assert.equal((built.payload.state as { note: string }).note, 'Authorization: Bearer [REDACTED]');
  assert.deepEqual(state.credentials, { apiKey: 'sk-live-do-not-send' });
  assert.equal(built.redacted, true);

  for (const label of [
    'PRIVATE KEY',
    'RSA PRIVATE KEY',
    'EC PRIVATE KEY',
    'OPENSSH PRIVATE KEY',
    'ENCRYPTED PRIVATE KEY',
  ]) {
    const pem = `-----BEGIN ${label}-----\nINERT-NOT-A-KEY\n-----END ${label}-----`;
    const original = { note: `before ${pem} after`, ordinary: 'Keep ordinary text.' };
    const snapshot = structuredClone(original);
    assert.deepEqual(redactSensitive(original), {
      value: { note: 'before [REDACTED] after', ordinary: 'Keep ordinary text.' },
      changed: true,
    });
    assert.deepEqual(original, snapshot);
  }
  assert.deepEqual(redactSensitive('ordinary text'), { value: 'ordinary text', changed: false });
  const keyOnly = { credentials: { apiKey: 'INERT-KEY-ONLY' } };
  assert.deepEqual(redactSensitive(keyOnly), {
    value: { credentials: '[REDACTED]' },
    changed: true,
  });
  assert.deepEqual(keyOnly, { credentials: { apiKey: 'INERT-KEY-ONLY' } });
});

test('executeJevDecision sends a redacted request with Pi auth and validates typed answers', async () => {
  let requestUrl = '';
  let requestInit:
    { headers: Record<string, string>; body: string; signal: AbortSignal } | undefined;
  let clock = 100;
  const pem = '-----BEGIN PRIVATE KEY-----\nINERT-NOT-A-KEY\n-----END PRIVATE KEY-----';
  const state = { task: 'Choose a route', apiKey: 'sk-live-secret', note: pem };
  const snapshot = structuredClone(state);
  const { executeJevDecision } = await import('./jev-core.ts');
  const execution = await executeJevDecision(
    {
      state,
      sessionId: pem,
      user: pem,
      provider: { note: pem },
      trace: { note: pem },
      questions: {
        route: {
          type: 'choice',
          instructions: `Choose one route. ${pem}`,
          criteria: { safe: 'No side effects', review: 'Ask a human' },
        },
      },
      timeoutMs: 1_000,
    },
    {
      resolveAuth: async () => ({ apiKey: 'sk-authenticated' }),
      fetch: async (url, init) => {
        requestUrl = url;
        requestInit = init;
        return {
          status: 200,
          ok: true,
          text: async () =>
            JSON.stringify({
              model: 'typesafe/jev-1.13-20260917',
              answers: {
                route: {
                  type: 'choice',
                  choice: 'safe',
                  probabilities: { safe: 0.9, review: 0.1 },
                  confidence: 0.8,
                },
              },
              usage: { input_tokens: 10, output_tokens: 2, cost: 0.001 },
            }),
        };
      },
      endpoint: 'https://example.test/decisions',
      now: () => {
        clock += 25;
        return clock;
      },
    },
  );

  assert.equal(requestUrl, 'https://example.test/decisions');
  assert.equal(requestInit?.headers.Authorization, 'Bearer sk-authenticated');
  assert.equal(JSON.parse(requestInit?.body ?? '{}').state.apiKey, '[REDACTED]');
  assert.ok(requestInit);
  const payload = JSON.parse(requestInit.body);
  assert.equal(payload.state.note, '[REDACTED]');
  assert.equal(payload.questions.route.instructions, 'Choose one route. [REDACTED]');
  assert.equal(payload.session_id, '[REDACTED]');
  assert.equal(payload.user, '[REDACTED]');
  assert.equal(payload.provider.note, '[REDACTED]');
  assert.equal(payload.trace.note, '[REDACTED]');
  assert.equal(requestInit.body.includes('INERT-NOT-A-KEY'), false);
  assert.deepEqual(state, snapshot);
  assert.equal(execution.response.answers.route.type, 'choice');
  assert.equal(execution.response.answers.route.choice, 'safe');
  assert.equal(execution.latencyMs, 25);
  assert.equal(execution.redacted, true);
});

test('parseDecisionResponse rejects an answer that is not one of the requested choices', async () => {
  const { parseDecisionResponse, JevError } = await import('./jev-core.ts');
  assert.throws(
    () =>
      parseDecisionResponse(
        {
          model: 'typesafe/jev-test',
          answers: { route: { type: 'choice', choice: 'unknown' } },
        },
        {
          route: {
            type: 'choice',
            instructions: 'Choose one.',
            criteria: { safe: 'Safe', review: 'Review' },
          },
        },
      ),
    (error) => error instanceof JevError && error.code === 'response',
  );
});

test("parseDecisionResponse accepts Jev's noul probability and score answer shapes", async () => {
  const { parseDecisionResponse } = await import('./jev-core.ts');
  const response = parseDecisionResponse(
    {
      model: 'typesafe/jev-test',
      answers: {
        safe: { type: 'noul', noul: 0.93 },
        quality: {
          type: 'score',
          score: 0.18,
          legend: { '0': 'correctness', '1': 'clarity' },
          probabilities: { '0': 0.82, '1': 0.18 },
          confidence: 0.64,
        },
      },
    },
    {
      safe: { type: 'noul', instructions: 'Is it safe?', criteria: { true: 'Yes', false: 'No' } },
      quality: { type: 'score', instructions: 'Score it.', criteria: ['correctness', 'clarity'] },
    },
  );

  assert.equal(response.answers.safe.type, 'noul');
  assert.equal(response.answers.safe.noul, 0.93);
  assert.equal(response.answers.quality.type, 'score');
  assert.equal(response.answers.quality.score, 0.18);
});

test('executeJevDecision reports cancellation instead of turning it into a retryable network error', async () => {
  const { executeJevDecision, JevError } = await import('./jev-core.ts');
  const controller = new AbortController();
  const pending = executeJevDecision(
    {
      state: { task: 'wait' },
      questions: {
        gate: {
          type: 'noul',
          instructions: 'Is waiting safe?',
          criteria: { true: 'Yes', false: 'No' },
        },
      },
    },
    {
      resolveAuth: async () => ({ apiKey: 'sk-authenticated' }),
      fetch: async (_url, init) =>
        new Promise((_, reject) => {
          init.signal.addEventListener('abort', () => reject(init.signal.reason), { once: true });
        }),
    },
    controller.signal,
  );
  setTimeout(() => controller.abort(), 5);
  await assert.rejects(pending, (error) => error instanceof JevError && error.code === 'cancelled');
});

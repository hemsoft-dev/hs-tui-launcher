export const JEV_MODEL = '~typesafe/jev-latest' as const;
export const JEV_ENDPOINT = 'https://openrouter.ai/api/alpha/decisions' as const;
export const DEFAULT_TIMEOUT_MS = 30_000;
export const MAX_TIMEOUT_MS = 120_000;
export const MAX_REQUEST_BYTES = 128_000;
export const MAX_RESPONSE_BYTES = 128_000;

const MAX_QUESTIONS = 20;
const MAX_CHOICES = 20;
const MAX_TEXT_LENGTH = 32_768;
const MAX_INSTRUCTIONS_LENGTH = 8_192;
const MAX_ID_LENGTH = 128;
const MAX_DEPTH = 8;
const REDACTED = '[REDACTED]';

export type JsonPrimitive = null | boolean | number | string;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type JsonObject = { [key: string]: JsonValue };

export interface ChoiceQuestion {
  type: 'choice';
  instructions: string;
  criteria: Record<string, string>;
}

export interface NoulQuestion {
  type: 'noul';
  instructions: string;
  criteria: { true: string; false: string };
}

export interface ScoreQuestion {
  type: 'score';
  instructions: string;
  criteria: string[];
}

export type JevQuestion = ChoiceQuestion | NoulQuestion | ScoreQuestion;

export interface JevDecisionInput {
  state: unknown;
  questions: Record<string, JevQuestion>;
  sessionId?: string;
  user?: string;
  provider?: JsonObject;
  trace?: JsonObject;
  timeoutMs?: number;
}

export interface JevRequest {
  model: typeof JEV_MODEL;
  state: JsonValue;
  questions: Record<string, JevQuestion>;
  session_id?: string;
  user?: string;
  provider?: JsonObject;
  trace?: JsonObject;
}

export interface BuiltDecisionRequest {
  payload: JevRequest;
  serialized: string;
  requestBytes: number;
  questionIds: string[];
  redacted: boolean;
  timeoutMs: number;
}

export type JevErrorCode = 'input' | 'auth' | 'network' | 'timeout' | 'cancelled' | 'response';

export class JevError extends Error {
  readonly code: JevErrorCode;
  readonly retryable: boolean;

  constructor(code: JevErrorCode, message: string, retryable = false) {
    super(message);
    this.name = 'JevError';
    this.code = code;
    this.retryable = retryable;
  }
}

function fail(message: string): never {
  throw new JevError('input', message);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  if (!isRecord(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function requireText(value: unknown, label: string, maxLength = MAX_TEXT_LENGTH): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    fail(`${label} must be a non-empty string.`);
  }
  if (value.length > maxLength) fail(`${label} exceeds the ${maxLength}-character limit.`);
  return value;
}

function requireId(value: unknown, label: string): string {
  const id = requireText(value, label, MAX_ID_LENGTH);
  if (!/^[A-Za-z][A-Za-z0-9_.-]*$/.test(id)) {
    fail(`${label} must start with a letter and contain only letters, numbers, '.', '_' or '-'.`);
  }
  return id;
}

function requireMetadataText(value: unknown, label: string): string {
  return requireText(value, label, 512);
}

function assertJsonValue(
  value: unknown,
  path: string,
  depth = 0,
  seen = new WeakSet<object>(),
): asserts value is JsonValue {
  if (depth > MAX_DEPTH) fail(`${path} is nested too deeply.`);
  if (value === null || typeof value === 'string' || typeof value === 'boolean') {
    if (typeof value === 'string' && value.length > MAX_TEXT_LENGTH) {
      fail(`${path} exceeds the ${MAX_TEXT_LENGTH}-character limit.`);
    }
    return;
  }
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) fail(`${path} must contain only finite numbers.`);
    return;
  }
  if (typeof value !== 'object') fail(`${path} must contain JSON-compatible values.`);
  if (seen.has(value)) fail(`${path} contains a circular reference.`);
  seen.add(value);
  if (Array.isArray(value)) {
    if (value.length > 1000) fail(`${path} contains too many items.`);
    for (let index = 0; index < value.length; index += 1) {
      assertJsonValue(value[index], `${path}[${index}]`, depth + 1, seen);
    }
  } else {
    if (!isPlainRecord(value)) fail(`${path} must contain plain JSON objects.`);
    const entries = Object.entries(value);
    if (entries.length > 1000) fail(`${path} contains too many properties.`);
    for (const [key, child] of entries) {
      if (key.length > MAX_ID_LENGTH)
        fail(`${path}.${key.slice(0, 20)}... has an overly long key.`);
      assertJsonValue(child, `${path}.${key}`, depth + 1, seen);
    }
  }
  seen.delete(value);
}

function normalizeCriteriaMap(value: unknown, label: string): Record<string, string> {
  if (!isPlainRecord(value)) fail(`${label} must be a non-empty object.`);
  const entries = Object.entries(value);
  if (entries.length === 0) fail(`${label} must contain at least one option.`);
  if (entries.length > MAX_CHOICES)
    fail(`${label} cannot contain more than ${MAX_CHOICES} options.`);
  const result: Record<string, string> = {};
  for (const [key, description] of entries) {
    const normalizedKey = requireId(key, `${label} option key`);
    result[normalizedKey] = requireText(description, `${label}.${normalizedKey}`, 2_048);
  }
  return result;
}

function normalizeQuestion(value: unknown, label: string): JevQuestion {
  if (!isPlainRecord(value)) fail(`${label} must be an object.`);
  const type = value.type;
  const instructions = requireText(
    value.instructions,
    `${label}.instructions`,
    MAX_INSTRUCTIONS_LENGTH,
  );
  if (type === 'choice') {
    return {
      type,
      instructions,
      criteria: normalizeCriteriaMap(value.criteria, `${label}.criteria`),
    };
  }
  if (type === 'noul') {
    if (!isPlainRecord(value.criteria)) fail(`${label}.criteria must be an object.`);
    const keys = Object.keys(value.criteria).sort();
    if (keys.length !== 2 || keys[0] !== 'false' || keys[1] !== 'true') {
      fail(`${label}.criteria must contain exactly 'true' and 'false'.`);
    }
    return {
      type,
      instructions,
      criteria: {
        true: requireText(value.criteria.true, `${label}.criteria.true`, 2_048),
        false: requireText(value.criteria.false, `${label}.criteria.false`, 2_048),
      },
    };
  }
  if (type === 'score') {
    if (!Array.isArray(value.criteria) || value.criteria.length === 0) {
      fail(`${label}.criteria must contain at least one criterion.`);
    }
    if (value.criteria.length > MAX_CHOICES)
      fail(`${label}.criteria cannot contain more than ${MAX_CHOICES} criteria.`);
    return {
      type,
      instructions,
      criteria: value.criteria.map((criterion, index) =>
        requireText(criterion, `${label}.criteria[${index}]`, 2_048),
      ),
    };
  }
  fail(`${label}.type must be 'choice', 'noul', or 'score'.`);
}

function normalizeQuestions(value: unknown): Record<string, JevQuestion> {
  if (!isPlainRecord(value)) fail('questions must be a non-empty object.');
  const entries = Object.entries(value);
  if (entries.length === 0) fail('questions must be a non-empty object.');
  if (entries.length > MAX_QUESTIONS)
    fail(`questions cannot contain more than ${MAX_QUESTIONS} entries.`);
  const result: Record<string, JevQuestion> = {};
  for (const [key, question] of entries) {
    const id = requireId(key, 'question id');
    result[id] = normalizeQuestion(question, `questions.${id}`);
  }
  return result;
}

function sensitiveKey(key: string): boolean {
  return /(?:api[_-]?key|access[_-]?token|refresh[_-]?token|auth(?:orization)?|password|secret|cookie|credential|private[_-]?key|client[_-]?secret)/i.test(
    key,
  );
}

function redactString(value: string): { value: string; changed: boolean } {
  let result = value;
  result = result.replace(
    /-----BEGIN (?:[^-\r\n]+ )?PRIVATE KEY-----[\s\S]*?-----END (?:[^-\r\n]+ )?PRIVATE KEY-----/gi,
    REDACTED,
  );
  result = result.replace(/\bBearer\s+[A-Za-z0-9._~+/=-]{12,}/gi, 'Bearer ' + REDACTED);
  result = result.replace(/\b(?:sk|rk|pk)-[A-Za-z0-9_-]{10,}\b/g, REDACTED);
  result = result.replace(
    /\b(?:ghp|gho|ghs|ghr|github_pat|xox[baprs])_[A-Za-z0-9_-]{10,}\b/g,
    REDACTED,
  );
  result = result.replace(
    /(\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|authorization)\s*[:=]\s*)(?!Bearer\b)([^\s,;]+)/gi,
    `$1${REDACTED}`,
  );
  return { value: result, changed: result !== value };
}

function redactValue(
  value: unknown,
  redactKeys: boolean,
  depth = 0,
  seen = new WeakSet<object>(),
): { value: JsonValue; changed: boolean } {
  if (depth > MAX_DEPTH) fail('request data is nested too deeply.');
  if (value === null || typeof value === 'boolean' || typeof value === 'number') {
    if (typeof value === 'number' && !Number.isFinite(value))
      fail('request data must contain only finite numbers.');
    return { value, changed: false };
  }
  if (typeof value === 'string') return redactString(value);
  if (typeof value !== 'object') fail('request data must contain JSON-compatible values.');
  if (seen.has(value)) fail('request data contains a circular reference.');
  seen.add(value);
  if (Array.isArray(value)) {
    const result: JsonValue[] = [];
    let changed = false;
    if (value.length > 1000) fail('request data contains too many items.');
    for (const item of value) {
      const redacted = redactValue(item, redactKeys, depth + 1, seen);
      result.push(redacted.value);
      changed ||= redacted.changed;
    }
    seen.delete(value);
    return { value: result, changed };
  }
  if (!isPlainRecord(value)) fail('request data must contain plain JSON objects.');
  const result: JsonObject = {};
  let changed = false;
  for (const [key, child] of Object.entries(value)) {
    if (key.length > MAX_ID_LENGTH) fail('request data contains an overly long key.');
    if (redactKeys && sensitiveKey(key)) {
      result[key] = REDACTED;
      changed = true;
      continue;
    }
    const redacted = redactValue(child, redactKeys, depth + 1, seen);
    result[key] = redacted.value;
    changed ||= redacted.changed;
  }
  seen.delete(value);
  return { value: result, changed };
}

export function redactSensitive(value: unknown): { value: JsonValue; changed: boolean } {
  assertJsonValue(value, 'value');
  return redactValue(value, true);
}

function normalizeTimeout(timeoutMs: unknown): number {
  if (timeoutMs === undefined) return DEFAULT_TIMEOUT_MS;
  if (
    typeof timeoutMs !== 'number' ||
    !Number.isInteger(timeoutMs) ||
    timeoutMs < 1_000 ||
    timeoutMs > MAX_TIMEOUT_MS
  ) {
    fail(`timeoutMs must be an integer between 1000 and ${MAX_TIMEOUT_MS}.`);
  }
  return timeoutMs;
}

export function buildDecisionRequest(input: JevDecisionInput): BuiltDecisionRequest {
  if (!input || typeof input !== 'object') fail('input must be an object.');
  assertJsonValue(input.state, 'state');
  const questions = normalizeQuestions(input.questions);
  const state = redactValue(input.state, true);
  const redactedQuestions = redactValue(questions, false);
  const payload: JevRequest = {
    model: JEV_MODEL,
    state: state.value,
    questions: redactedQuestions.value as unknown as Record<string, JevQuestion>,
  };
  let redacted = state.changed || redactedQuestions.changed;
  if (input.sessionId !== undefined) {
    const value = redactString(requireMetadataText(input.sessionId, 'sessionId'));
    payload.session_id = value.value;
    redacted ||= value.changed;
  }
  if (input.user !== undefined) {
    const value = redactString(requireMetadataText(input.user, 'user'));
    payload.user = value.value;
    redacted ||= value.changed;
  }
  if (input.provider !== undefined) {
    assertJsonValue(input.provider, 'provider');
    if (!isPlainRecord(input.provider)) fail('provider must be a JSON object.');
    const value = redactValue(input.provider, true);
    payload.provider = value.value as JsonObject;
    redacted ||= value.changed;
  }
  if (input.trace !== undefined) {
    assertJsonValue(input.trace, 'trace');
    if (!isPlainRecord(input.trace)) fail('trace must be a JSON object.');
    const value = redactValue(input.trace, true);
    payload.trace = value.value as JsonObject;
    redacted ||= value.changed;
  }
  const serialized = JSON.stringify(payload);
  const requestBytes = new TextEncoder().encode(serialized).byteLength;
  if (requestBytes > MAX_REQUEST_BYTES)
    fail(`request exceeds the ${MAX_REQUEST_BYTES}-byte limit.`);
  return {
    payload,
    serialized,
    requestBytes,
    questionIds: Object.keys(questions),
    redacted,
    timeoutMs: normalizeTimeout(input.timeoutMs),
  };
}

export interface JevChoiceAnswer {
  type: 'choice';
  choice: string;
  probabilities?: Record<string, number>;
  confidence?: number;
}

export interface JevNoulAnswer {
  type: 'noul';
  noul: number;
  confidence?: number;
}

export interface JevScoreAnswer {
  type: 'score';
  score: number;
  legend?: Record<string, string>;
  probabilities?: Record<string, number>;
  confidence?: number;
}

export type JevAnswer = JevChoiceAnswer | JevNoulAnswer | JevScoreAnswer;

export interface JevUsage {
  input_tokens?: number;
  output_tokens?: number;
  cost?: number;
}

export interface JevDecisionResponse {
  model: string;
  answers: Record<string, JevAnswer>;
  usage?: JevUsage;
  id?: string;
  provider?: string;
}

function responseText(value: unknown, label: string, maxLength = 512): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new JevError('response', `${label} must be a non-empty string.`);
  }
  if (value.length > maxLength) throw new JevError('response', `${label} is too long.`);
  return value;
}

function probability(value: unknown, label: string): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) {
    throw new JevError('response', `${label} must be a probability between 0 and 1.`);
  }
  return value;
}

function confidence(value: unknown, label: string): number | undefined {
  if (value === undefined) return undefined;
  return probability(value, label);
}

function probabilityMap(
  value: unknown,
  allowedKeys: readonly string[],
  label: string,
): Record<string, number> | undefined {
  if (value === undefined) return undefined;
  if (!isPlainRecord(value)) throw new JevError('response', `${label} must be an object.`);
  const allowed = new Set(allowedKeys);
  const result: Record<string, number> = {};
  for (const [key, item] of Object.entries(value)) {
    if (!allowed.has(key))
      throw new JevError('response', `${label} contains unknown key '${key}'.`);
    result[key] = probability(item, `${label}.${key}`);
  }
  return result;
}

function parseAnswer(answer: unknown, question: JevQuestion, label: string): JevAnswer {
  if (!isPlainRecord(answer)) throw new JevError('response', `${label} must be an object.`);
  if (answer.type !== question.type)
    throw new JevError('response', `${label}.type does not match the question.`);
  if (question.type === 'choice') {
    if (typeof answer.choice !== 'string' || !Object.hasOwn(question.criteria, answer.choice)) {
      throw new JevError('response', `${label}.choice is not one of the requested options.`);
    }
    return {
      type: 'choice',
      choice: answer.choice,
      probabilities: probabilityMap(
        answer.probabilities,
        Object.keys(question.criteria),
        `${label}.probabilities`,
      ),
      confidence: confidence(answer.confidence, `${label}.confidence`),
    };
  }
  if (question.type === 'noul') {
    return {
      type: 'noul',
      noul: probability(answer.noul, `${label}.noul`),
      confidence: confidence(answer.confidence, `${label}.confidence`),
    };
  }
  if (
    typeof answer.score !== 'number' ||
    !Number.isFinite(answer.score) ||
    Math.abs(answer.score) > 1_000_000
  ) {
    throw new JevError('response', `${label}.score must be a finite bounded number.`);
  }
  let legend: Record<string, string> | undefined;
  const criterionKeys = question.criteria.map((_, index) => String(index));
  if (answer.legend !== undefined) {
    if (!isPlainRecord(answer.legend))
      throw new JevError('response', `${label}.legend must be an object.`);
    const legendEntries = Object.entries(answer.legend);
    if (legendEntries.length > MAX_CHOICES)
      throw new JevError('response', `${label}.legend contains too many entries.`);
    legend = {};
    for (const [key, value] of legendEntries) {
      if (!criterionKeys.includes(key))
        throw new JevError('response', `${label}.legend contains unknown key '${key}'.`);
      if (typeof value !== 'string' || value.length > 2_048) {
        throw new JevError('response', `${label}.legend values must be short strings.`);
      }
      legend[key] = value;
    }
  }
  return {
    type: 'score',
    score: answer.score,
    legend,
    probabilities: probabilityMap(answer.probabilities, criterionKeys, `${label}.probabilities`),
    confidence: confidence(answer.confidence, `${label}.confidence`),
  };
}

function parseUsage(value: unknown): JevUsage | undefined {
  if (value === undefined) return undefined;
  if (!isPlainRecord(value)) throw new JevError('response', 'usage must be an object.');
  const result: JevUsage = {};
  for (const key of ['input_tokens', 'output_tokens', 'cost'] as const) {
    const item = value[key];
    if (item === undefined) continue;
    if (
      typeof item !== 'number' ||
      !Number.isFinite(item) ||
      item < 0 ||
      item > 1_000_000_000_000
    ) {
      throw new JevError('response', `usage.${key} must be a finite non-negative number.`);
    }
    result[key] = item;
  }
  return result;
}

export function parseDecisionResponse(
  value: unknown,
  questions: Record<string, JevQuestion>,
): JevDecisionResponse {
  if (!isPlainRecord(value))
    throw new JevError('response', 'OpenRouter returned a non-object response.');
  const model = responseText(value.model, 'response.model');
  if (!isPlainRecord(value.answers))
    throw new JevError('response', 'response.answers must be an object.');
  const answerObject = value.answers;
  const expectedIds = Object.keys(questions);
  const actualIds = Object.keys(answerObject);
  if (
    actualIds.length !== expectedIds.length ||
    expectedIds.some((id) => !Object.hasOwn(answerObject, id))
  ) {
    throw new JevError('response', 'response.answers does not match the requested question ids.');
  }
  const answers: Record<string, JevAnswer> = {};
  for (const id of expectedIds)
    answers[id] = parseAnswer(answerObject[id], questions[id], `response.answers.${id}`);
  const result: JevDecisionResponse = { model, answers, usage: parseUsage(value.usage) };
  if (value.id !== undefined) result.id = responseText(value.id, 'response.id');
  if (value.provider !== undefined)
    result.provider = responseText(value.provider, 'response.provider');
  return result;
}

export interface JevAuthMaterial {
  apiKey?: string;
  headers?: Record<string, string | undefined>;
}

export interface JevResponseLike {
  status: number;
  ok?: boolean;
  text(): Promise<string>;
}

export interface JevRequestDependencies {
  resolveAuth(signal: AbortSignal): Promise<JevAuthMaterial | undefined>;
  fetch(
    input: string,
    init: { method: 'POST'; headers: Record<string, string>; body: string; signal: AbortSignal },
  ): Promise<JevResponseLike>;
  endpoint?: string;
  now?: () => number;
}

export interface JevExecution {
  response: JevDecisionResponse;
  latencyMs: number;
  requestBytes: number;
  questionIds: string[];
  redacted: boolean;
}

function abortable<T>(promise: Promise<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) return Promise.reject(signal.reason ?? new Error('aborted'));
  return new Promise<T>((resolve, reject) => {
    const onAbort = () => reject(signal.reason ?? new Error('aborted'));
    signal.addEventListener('abort', onAbort, { once: true });
    promise.then(
      (value) => {
        signal.removeEventListener('abort', onAbort);
        resolve(value);
      },
      (error) => {
        signal.removeEventListener('abort', onAbort);
        reject(error);
      },
    );
  });
}

function withTimeout(
  parent: AbortSignal | undefined,
  timeoutMs: number,
): { signal: AbortSignal; timedOut: () => boolean; cleanup: () => void } {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(new Error('Jev request timed out.')), timeoutMs);
  const signal = parent ? AbortSignal.any([parent, controller.signal]) : controller.signal;
  return { signal, timedOut: () => controller.signal.aborted, cleanup: () => clearTimeout(timer) };
}

function authHeaders(auth: JevAuthMaterial | undefined): Record<string, string> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
    'Content-Type': 'application/json',
  };
  let authorizationPresent = false;
  for (const [name, value] of Object.entries(auth?.headers ?? {})) {
    if (value === undefined || value.trim().length === 0) continue;
    if (name.toLowerCase() === 'authorization') authorizationPresent = true;
    headers[name] = value;
  }
  if (auth?.apiKey && auth.apiKey.trim().length > 0) {
    headers.Authorization = `Bearer ${auth.apiKey}`;
    authorizationPresent = true;
  }
  if (!authorizationPresent)
    throw new JevError('auth', 'OpenRouter authentication is not configured in Pi.');
  return headers;
}

export async function executeJevDecision(
  input: JevDecisionInput,
  dependencies: JevRequestDependencies,
  parentSignal?: AbortSignal,
): Promise<JevExecution> {
  const built = buildDecisionRequest(input);
  const timeout = withTimeout(parentSignal, built.timeoutMs);
  const started = dependencies.now?.() ?? Date.now();
  try {
    const auth = await abortable(dependencies.resolveAuth(timeout.signal), timeout.signal).catch(
      (error) => {
        if (timeout.signal.aborted) throw error;
        throw new JevError('auth', 'OpenRouter authentication could not be resolved.');
      },
    );
    const headers = authHeaders(auth);
    const response = await abortable(
      dependencies.fetch(dependencies.endpoint ?? JEV_ENDPOINT, {
        method: 'POST',
        headers,
        body: built.serialized,
        signal: timeout.signal,
      }),
      timeout.signal,
    ).catch((error) => {
      if (timeout.signal.aborted) throw error;
      throw new JevError('network', 'The Jev request could not be completed.', true);
    });
    if (response.status < 200 || response.status >= 300 || response.ok === false) {
      throw new JevError(
        'network',
        `OpenRouter returned HTTP ${response.status}.`,
        response.status >= 500 || response.status === 429,
      );
    }
    const text = await abortable(response.text(), timeout.signal).catch((error) => {
      if (timeout.signal.aborted) throw error;
      throw new JevError('network', 'The Jev response could not be read.', true);
    });
    if (text.trim().length === 0)
      throw new JevError('response', 'OpenRouter returned an empty response.', true);
    if (new TextEncoder().encode(text).byteLength > MAX_RESPONSE_BYTES) {
      throw new JevError(
        'response',
        `OpenRouter response exceeds the ${MAX_RESPONSE_BYTES}-byte limit.`,
        true,
      );
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      throw new JevError('response', 'OpenRouter returned invalid JSON.', true);
    }
    const responseData = parseDecisionResponse(parsed, built.payload.questions);
    const ended = dependencies.now?.() ?? Date.now();
    return {
      response: responseData,
      latencyMs: Math.max(0, ended - started),
      requestBytes: built.requestBytes,
      questionIds: built.questionIds,
      redacted: built.redacted,
    };
  } catch (error) {
    if (parentSignal?.aborted) throw new JevError('cancelled', 'Jev consultation was cancelled.');
    if (timeout.timedOut()) throw new JevError('timeout', 'Jev consultation timed out.', true);
    if (error instanceof JevError) throw error;
    throw new JevError('network', 'The Jev request could not be completed.', true);
  } finally {
    timeout.cleanup();
  }
}

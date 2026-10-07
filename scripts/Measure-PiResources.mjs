import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { getEventListeners } from 'node:events';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { cpus } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { setImmediate as nextTurn } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';
import { doneSound } from '../.pi/extensions/done-sound.ts';
import { executeJevDecision, JevError } from '../pi/jev-decide/jev-core.ts';
import { inspectResourceSummary, requestModes } from './PiResourcePolicy.mjs';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const options = {
  output: undefined,
  budget: join(root, 'scripts/pi-resource-budgets.json'),
  recordBaseline: false,
  fixture: undefined,
};
for (let index = 2; index < process.argv.length; index++) {
  const argument = process.argv[index];
  if (argument === '--record-baseline') options.recordBaseline = true;
  else if (['--output', '--budget', '--fixture'].includes(argument)) {
    assert.ok(process.argv[index + 1], 'Missing argument value.');
    options[argument.slice(2)] = process.argv[++index];
  } else throw new Error('Unknown resource measurement argument.');
}
assert.ok(options.output, '--output is required.');
assert.ok(
  !options.fixture || ['timer', 'listener', 'heap'].includes(options.fixture),
  'Unknown controlled fixture.',
);
const output = resolve(options.output);
mkdirSync(output, { recursive: true });

const counters = {
  requests: Object.fromEntries(requestModes.map((name) => [name, 0])),
  completedEvents: 0,
  playerCalls: 0,
  warningCalls: 0,
  registeredCallbacks: 0,
  maximumPlayersInFlight: 0,
};
const resourcePeaks = {
  activeTimers: 0,
  settledTimers: 0,
  visibleChildAbortListeners: 0,
  parentAbortListeners: 0,
  pendingFakeWork: 0,
  inFlightFakeWork: 0,
  settledPlayers: 0,
};
const report = {
  schemaVersion: 1,
  revision: null,
  pullRequestHead: null,
  workingTreeDirty: null,
  node: process.version,
  platform: process.platform + '/' + process.arch,
  processor: cpus()[0]?.model,
  command: process.argv,
  recordBaseline: options.recordBaseline,
  controlledFixture: options.fixture ?? null,
  warmupWaves: 10,
  measuredWaves: 5,
  iterationsPerWave: 25,
  realTimeoutMilliseconds: 1000,
  timeoutDurationsMilliseconds: [],
  before: null,
  samples: [],
  counters,
  resourcePeaks,
  expectedExtensionRegistrations: 1,
  budgetSha256: null,
  policyPassed: false,
  failures: [],
  teardown: {},
};
const nativeSetTimeout = globalThis.setTimeout;
const nativeClearTimeout = globalThis.clearTimeout;
const timers = new Set();
const parent = new AbortController();
const handlers = new Set();
let pendingFakeWork = 0;
let players = 0;
let playerMode = 'success';
let finishPlayer;
let controlledHeap;
let controlledListener;
let primaryError;
const originalMute = process.env.HS_TUI_LAUNCHER_DONE_SOUND;

function git(...arguments_) {
  const result = spawnSync('git', ['-C', root, ...arguments_], { encoding: 'utf8' });
  if (result.error || result.status !== 0)
    throw new Error('Unable to establish resource source provenance.');
  return result.stdout.trim();
}

async function collectedSample() {
  for (let turn = 0; turn < 3; turn++) {
    globalThis.gc();
    await nextTurn();
  }
  return {
    ...process.memoryUsage(),
    forcedCollections: 3,
    activeResourceKinds: process.getActiveResourcesInfo(),
  };
}

function observeSettled(signal, callerSignal) {
  resourcePeaks.settledTimers = Math.max(resourcePeaks.settledTimers, timers.size);
  resourcePeaks.visibleChildAbortListeners = Math.max(
    resourcePeaks.visibleChildAbortListeners,
    signal ? getEventListeners(signal, 'abort').length : 0,
  );
  resourcePeaks.parentAbortListeners = Math.max(
    resourcePeaks.parentAbortListeners,
    getEventListeners(parent.signal, 'abort').length +
      (callerSignal ? getEventListeners(callerSignal, 'abort').length : 0),
  );
  resourcePeaks.pendingFakeWork = Math.max(resourcePeaks.pendingFakeWork, pendingFakeWork);
  resourcePeaks.settledPlayers = Math.max(resourcePeaks.settledPlayers, players);
}

const response = () => ({
  status: 200,
  text: async () =>
    JSON.stringify({
      model: 'offline-resource-fixture',
      answers: { decision: { type: 'noul', noul: 0.7, confidence: 0.9 } },
    }),
});
const input = {
  state: { fixture: 'offline' },
  questions: {
    decision: {
      type: 'noul',
      instructions: 'Inert decision',
      criteria: { true: 'yes', false: 'no' },
    },
  },
  timeoutMs: 1000,
};

async function request(mode, measured) {
  // Each completed invocation releases its caller-owned cancellation context.
  const controller = new AbortController();
  let signal;
  let finish;
  const pending = () => {
    pendingFakeWork++;
    resourcePeaks.inFlightFakeWork = Math.max(resourcePeaks.inFlightFakeWork, pendingFakeWork);
    return new Promise((resolvePromise) => {
      finish = () => {
        pendingFakeWork--;
        resolvePromise(mode === 'timeout' ? { apiKey: 'INERT_RESOURCE_KEY' } : response());
      };
    });
  };
  const started = performance.now();
  try {
    const dependencies = {
      resolveAuth: async (child) => {
        signal = child;
        if (mode === 'auth_failure') throw new Error('inert auth failure');
        if (mode === 'timeout') return pending();
        return { apiKey: 'INERT_RESOURCE_KEY' };
      },
      fetch: async (_url, init) => {
        signal = init.signal;
        if (mode === 'network_failure') throw new Error('inert network failure');
        if (mode === 'response_failure') return { status: 200, text: async () => 'invalid JSON' };
        if (mode === 'cancelled') {
          const result = pending();
          queueMicrotask(() => controller.abort());
          return result;
        }
        return response();
      },
    };
    if (mode === 'success') {
      const result = await executeJevDecision(input, dependencies, controller.signal);
      assert.equal(result.response.answers.decision.type, 'noul');
    } else {
      const expected = {
        auth_failure: 'auth',
        network_failure: 'network',
        response_failure: 'response',
        cancelled: 'cancelled',
        timeout: 'timeout',
      }[mode];
      await assert.rejects(
        executeJevDecision(input, dependencies, controller.signal),
        (error) => error instanceof JevError && error.code === expected,
      );
    }
    if (mode === 'timeout') {
      const duration = performance.now() - started;
      assert.ok(duration >= 900, 'Timeout must exercise the actual 1000ms timer.');
      if (measured) report.timeoutDurationsMilliseconds.push(duration);
    }
    if (measured) counters.requests[mode]++;
  } finally {
    finish?.();
    await nextTurn();
    observeSettled(signal, controller.signal);
  }
}

const context = {
  cwd: root,
  hasUI: true,
  ui: {
    notify: () => {
      if (measuring) counters.warningCalls++;
    },
  },
};
let measuring = false;
const api = {
  on: (name, handler) => {
    assert.equal(name, 'agent_settled');
    counters.registeredCallbacks++;
    handlers.add(handler);
    return () => handlers.delete(handler);
  },
  exec: async () => {
    if (measuring) counters.playerCalls++;
    players++;
    counters.maximumPlayersInFlight = Math.max(counters.maximumPlayersInFlight, players);
    try {
      if (playerMode === 'throw') throw new Error('inert player failure');
      if (playerMode === 'overlap')
        await new Promise((finish) => {
          finishPlayer = finish;
        });
      return {
        code: playerMode === 'exit' ? 7 : 0,
        killed: playerMode === 'killed',
        stdout: '',
        stderr: '',
      };
    } finally {
      players--;
    }
  },
};

async function settled() {
  assert.equal(handlers.size, 1);
  if (measuring) counters.completedEvents++;
  await [...handlers][0]({ type: 'agent_settled' }, context);
}

async function wave(measured) {
  measuring = measured;
  for (let iteration = 0; iteration < 25; iteration++) {
    for (const mode of requestModes.filter((name) => name !== 'timeout'))
      await request(mode, measured);
    playerMode = 'success';
    await settled();
    playerMode = ['throw', 'exit', 'killed'][iteration % 3];
    await settled();
    playerMode = 'overlap';
    const first = settled();
    try {
      await settled();
      assert.equal(players, 1);
    } finally {
      finishPlayer?.();
    }
    await first;
    finishPlayer = undefined;
    playerMode = 'success';
    await settled();
    observeSettled();
  }
  await request('timeout', measured);
}

try {
  assert.equal(process.version, 'v24.12.0', 'Use the reviewed Node toolchain.');
  assert.equal(typeof globalThis.gc, 'function', 'Run with --expose-gc.');
  report.revision = git('rev-parse', 'HEAD');
  assert.match(report.revision, /^[0-9a-f]{40}$/);
  report.pullRequestHead = process.env.RESOURCE_PR_HEAD || report.revision;
  assert.match(report.pullRequestHead, /^[0-9a-f]{40}$/);
  report.workingTreeDirty = git('status', '--porcelain', '--untracked-files=normal').length > 0;
  globalThis.setTimeout = (callback, delay, ...arguments_) => {
    const timer = nativeSetTimeout(() => {
      timers.delete(timer);
      callback(...arguments_);
    }, delay);
    timers.add(timer);
    resourcePeaks.activeTimers = Math.max(resourcePeaks.activeTimers, timers.size);
    return timer;
  };
  globalThis.clearTimeout = (timer) => {
    timers.delete(timer);
    nativeClearTimeout(timer);
  };
  process.env.HS_TUI_LAUNCHER_DONE_SOUND = '1';
  doneSound(api);
  for (let warmup = 0; warmup < 10; warmup++) await wave(false);
  report.before = await collectedSample();
  if (options.fixture === 'timer') globalThis.setTimeout(() => {}, 600000);
  if (options.fixture === 'listener') {
    controlledListener = () => {};
    parent.signal.addEventListener('abort', controlledListener);
  }
  if (options.fixture === 'heap') controlledHeap = new Array(2000000).fill(0);
  for (let index = 0; index < 5; index++) {
    await wave(true);
    report.samples.push(await collectedSample());
  }
  report.controlledDataElements = controlledHeap?.length ?? 0;
} catch (error) {
  primaryError = error;
} finally {
  finishPlayer?.();
  for (const timer of timers) nativeClearTimeout(timer);
  timers.clear();
  globalThis.setTimeout = nativeSetTimeout;
  globalThis.clearTimeout = nativeClearTimeout;
  if (controlledListener) parent.signal.removeEventListener('abort', controlledListener);
  controlledHeap = undefined;
  handlers.clear();
  if (originalMute === undefined) delete process.env.HS_TUI_LAUNCHER_DONE_SOUND;
  else process.env.HS_TUI_LAUNCHER_DONE_SOUND = originalMute;
  report.teardown = {
    timers: timers.size,
    parentAbortListeners: getEventListeners(parent.signal, 'abort').length,
    registeredCallbacks: handlers.size,
    players,
    pendingFakeWork,
  };
  if (typeof globalThis.gc === 'function') {
    report.afterTeardown = await collectedSample();
    report.teardown.nativeTimeouts = report.afterTeardown.activeResourceKinds.filter(
      (name) => name === 'Timeout',
    ).length;
  }
}
try {
  if (primaryError) throw primaryError;
  let budget;
  if (!options.recordBaseline) {
    const text = readFileSync(options.budget, 'utf8').replace(/^\uFEFF/, '');
    report.budgetSha256 = createHash('sha256').update(text).digest('hex');
    budget = JSON.parse(text);
  }
  report.failures = inspectResourceSummary(report, budget);
  report.policyPassed = !options.recordBaseline && report.failures.length === 0;
  if (report.failures.length)
    throw new Error('Resource qualification rejected: ' + report.failures.join(', '));
} catch (error) {
  primaryError ??= error;
  report.policyPassed = false;
  if (!report.failures.length) report.failures.push(primaryError.message);
}
try {
  writeFileSync(join(output, 'summary.json'), JSON.stringify(report, null, 2) + '\n', 'utf8');
} catch (error) {
  if (!primaryError) throw error;
  console.error(
    'Resource evidence could not be written; preserving the original qualification failure.',
  );
}
if (primaryError) throw primaryError;
console.log(
  'Pi resource measurement complete; baseline-only=' +
    options.recordBaseline +
    ', samples=' +
    report.samples.length,
);

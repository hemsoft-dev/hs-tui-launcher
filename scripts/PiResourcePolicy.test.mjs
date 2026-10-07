import assert from 'node:assert/strict';
import { test } from 'node:test';
import { inspectResourceSummary, requestModes } from './PiResourcePolicy.mjs';

function report() {
  return {
    schemaVersion: 1,
    node: 'v24.12.0',
    platform: 'linux/x64',
    warmupWaves: 10,
    iterationsPerWave: 25,
    measuredWaves: 5,
    before: { heapUsed: 1000000, forcedCollections: 3 },
    samples: Array.from({ length: 5 }, (_, index) => ({
      heapUsed: 1010000 + index * 100,
      heapTotal: 2000000,
      rss: 5000000,
      external: 100000,
      arrayBuffers: 10000,
      forcedCollections: 3,
    })),
    counters: {
      requests: Object.fromEntries(
        requestModes.map((name) => [name, name === 'timeout' ? 5 : 125]),
      ),
      completedEvents: 625,
      playerCalls: 500,
      warningCalls: 125,
      registeredCallbacks: 1,
      maximumPlayersInFlight: 1,
    },
    resourcePeaks: {
      inFlightFakeWork: 1,
      settledTimers: 0,
      visibleChildAbortListeners: 0,
      parentAbortListeners: 0,
      pendingFakeWork: 0,
      settledPlayers: 0,
    },
    teardown: {
      nativeTimeouts: 0,
      timers: 0,
      parentAbortListeners: 0,
      registeredCallbacks: 0,
      players: 0,
      pendingFakeWork: 0,
    },
  };
}

const budget = {
  schemaVersion: 1,
  node: 'v24.12.0',
  platforms: { 'linux/x64': { maximumHeapGrowthBytes: 20000 } },
};

test('complete bounded workload qualifies and fixture labels do not decide policy', () => {
  const summary = report();
  summary.controlledFixture = 'heap';
  assert.deepEqual(inspectResourceSummary(summary, budget), []);
});
test('missing samples, uncollected baseline and incomplete workload fail closed', () => {
  for (const mutate of [
    (summary) => summary.samples.pop(),
    (summary) => {
      summary.samples = null;
    },
    (summary) => {
      summary.before.forcedCollections = 0;
    },
    (summary) => {
      summary.counters.requests.cancelled = 0;
    },
    (summary) => {
      summary.counters.completedEvents = 0;
    },
  ]) {
    const summary = report();
    mutate(summary);
    assert.ok(inspectResourceSummary(summary, budget).length > 0);
  }
});
test('each measured retained resource and incomplete cleanup is rejected', () => {
  for (const field of Object.keys(report().resourcePeaks).filter(
    (name) => name !== 'inFlightFakeWork',
  )) {
    const summary = report();
    summary.resourcePeaks[field] = 1;
    assert.ok(inspectResourceSummary(summary, budget).includes('retained resource: ' + field));
  }
  const summary = report();
  summary.teardown.timers = 1;
  assert.ok(inspectResourceSummary(summary, budget).includes('incomplete teardown: timers'));
});
test('observed heap growth fails while RSS growth alone remains diagnostic', () => {
  const summary = report();
  summary.samples[4].rss = 500000000;
  assert.deepEqual(inspectResourceSummary(summary, budget), []);
  summary.samples[4].heapUsed = 1100000;
  assert.ok(
    inspectResourceSummary(summary, budget).includes('managed heap growth exceeds measured budget'),
  );
});
test('unknown platform, toolchain and invalid limits are rejected', () => {
  for (const policy of [
    undefined,
    null,
    false,
    0,
    '',
    [],
    {},
    { ...budget, node: 'v25.0.0' },
    { ...budget, platforms: {} },
    { ...budget, platforms: { 'linux/x64': { maximumHeapGrowthBytes: -1 } } },
  ])
    assert.ok(inspectResourceSummary(report(), policy).length > 0);
  const baseline = report();
  baseline.recordBaseline = true;
  assert.deepEqual(inspectResourceSummary(baseline, undefined), []);
  assert.ok(inspectResourceSummary(baseline, null).length > 0);
});

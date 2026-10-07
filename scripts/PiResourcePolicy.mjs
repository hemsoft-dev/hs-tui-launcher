export const requestModes = [
  'success',
  'auth_failure',
  'network_failure',
  'response_failure',
  'cancelled',
  'timeout',
];

export function inspectResourceSummary(summary, budget) {
  const failures = [];
  const require = (condition, message) => {
    if (!condition) failures.push(message);
  };
  require(summary.schemaVersion === 1, 'unsupported resource report schema');
  require(summary.node === 'v24.12.0', 'unreviewed Node toolchain');
  require(summary.iterationsPerWave === 25 &&
    summary.measuredWaves === 5 &&
    summary.warmupWaves === 10, 'workload dimensions changed');
  require(Array.isArray(summary.samples) &&
    summary.samples.length === 5, 'five collected samples are required');
  require(Number.isFinite(summary.before?.heapUsed) &&
    summary.before.heapUsed > 0 &&
    summary.before.forcedCollections === 3, 'missing collected baseline');
  if (!Array.isArray(summary.samples)) return failures;
  for (const mode of requestModes) {
    const expected = mode === 'timeout' ? 5 : 125;
    require(summary.counters?.requests?.[mode] === expected, 'incomplete request workload: ' +
      mode);
  }
  require(summary.counters?.completedEvents === 625, 'incomplete completion event workload');
  require(summary.counters?.playerCalls === 500, 'incorrect player invocation count');
  require(summary.counters?.warningCalls === 125, 'incorrect player failure count');
  require(summary.counters?.registeredCallbacks ===
    1, 'expected one extension lifetime registration');
  require(summary.counters?.maximumPlayersInFlight === 1, 'player overlap protection failed');
  require(summary.resourcePeaks?.inFlightFakeWork ===
    1, 'pending dependency workload not exercised');
  for (const name of [
    'settledTimers',
    'visibleChildAbortListeners',
    'parentAbortListeners',
    'pendingFakeWork',
    'settledPlayers',
  ]) {
    require(summary.resourcePeaks?.[name] === 0, 'retained resource: ' + name);
  }
  for (const name of [
    'timers',
    'parentAbortListeners',
    'registeredCallbacks',
    'players',
    'pendingFakeWork',
    'nativeTimeouts',
  ]) {
    require(summary.teardown?.[name] === 0, 'incomplete teardown: ' + name);
  }
  for (const sample of summary.samples ?? []) {
    require(['heapUsed', 'heapTotal', 'rss', 'external', 'arrayBuffers'].every(
      (name) => Number.isFinite(sample[name]) && sample[name] >= 0,
    ), 'invalid memory sample');
    require(sample.forcedCollections === 3, 'samples must follow three collection turns');
  }
  if (budget === undefined && summary.recordBaseline === true) return failures;
  const validBudget = budget !== null && typeof budget === 'object' && !Array.isArray(budget);
  require(validBudget, 'a reviewed resource budget object is required');
  if (validBudget) {
    require(budget.schemaVersion === 1 &&
      budget.node === summary.node, 'resource budget toolchain changed');
    const limit = budget.platforms?.[summary.platform]?.maximumHeapGrowthBytes;
    require(Number.isFinite(limit) && limit > 0, 'no reviewed platform heap budget');
    if (Number.isFinite(limit) && summary.before && summary.samples?.length === 5) {
      const growth = Math.max(
        0,
        ...summary.samples.map((sample) => sample.heapUsed - summary.before.heapUsed),
      );
      require(growth <= limit, 'managed heap growth exceeds measured budget');
    }
  }
  return failures;
}

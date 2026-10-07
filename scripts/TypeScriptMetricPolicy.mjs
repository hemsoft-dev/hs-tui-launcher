import assert from 'node:assert/strict';
import { crap, metricVersions } from './TypeScriptMetrics.mjs';

const tolerance = 1e-12;
const fraction = (value) => Number.isFinite(value) && value >= 0 && value <= 1;
const positiveInteger = (value) => Number.isInteger(value) && value > 0;

export function inspectTypeScriptMetrics(report, budget) {
  assert.equal(report.schemaVersion, 1, 'Unsupported TypeScript metric report.');
  assert.deepEqual(report.tools, metricVersions, 'Unreviewed TypeScript metric tools.');
  assert.ok(Array.isArray(report.files) && report.files.length > 0, 'Missing production metrics.');
  const failures = [];
  const files = new Set();
  const functions = new Set();
  for (const file of report.files) {
    assert.ok(
      typeof file.file === 'string' && !files.has(file.file),
      'Duplicate or invalid source metrics.',
    );
    files.add(file.file);
    assert.match(file.sourceSha256, /^[0-9a-f]{64}$/, 'Missing source hash.');
    assert.equal(typeof file.loaded, 'boolean', 'Missing source load state.');
    assert.ok(
      positiveInteger(file.branches?.total) &&
        Number.isInteger(file.branches.covered) &&
        file.branches.covered >= 0 &&
        file.branches.covered <= file.branches.total &&
        Math.abs(file.branches.fraction - file.branches.covered / file.branches.total) <= tolerance,
      'Invalid file branch metrics.',
    );
    assert.ok(Array.isArray(file.functions), 'Missing AST function metrics.');
    for (const func of file.functions) {
      assert.ok(
        typeof func.id === 'string' &&
          func.id.startsWith(file.file + ':') &&
          !functions.has(func.id),
        'Duplicate or invalid function identity.',
      );
      functions.add(func.id);
      assert.ok(
        positiveInteger(func.complexity) &&
          fraction(func.coverage) &&
          Number.isFinite(func.crap) &&
          Math.abs(func.crap - crap(func.complexity, func.coverage)) <= tolerance,
        'Invalid function complexity, coverage or CRAP.',
      );
      assert.ok(
        ['v8-derived branch ranges', 'function invocation'].includes(func.coverageBasis),
        'Unknown per-function coverage basis.',
      );
      assert.equal(typeof func.invoked, 'boolean', 'Missing invocation evidence.');
      assert.ok(
        Number.isInteger(func.invocationCount) &&
          func.invocationCount >= 0 &&
          func.invoked === func.invocationCount > 0,
        'Inconsistent function invocation evidence.',
      );
      if (!func.invoked)
        assert.equal(func.coverage, 0, 'Uncalled function cannot receive coverage.');
    }
  }
  assert.ok(functions.size > 0, 'Missing production functions.');
  if (!budget) return failures;
  assert.equal(budget.schemaVersion, 1, 'Unsupported TypeScript metric budget.');
  assert.deepEqual(budget.tools, metricVersions, 'Unreviewed TypeScript budget tools.');
  const platform = budget.platforms?.[report.platform];
  assert.ok(
    platform && Array.isArray(platform.files) && platform.files.length > 0,
    'No reviewed native TypeScript metric budget.',
  );
  assert.ok(
    positiveInteger(platform.maximumNewComplexity),
    'Invalid new-function complexity limit.',
  );
  const expected = new Map();
  const expectedFunctions = new Set();
  for (const file of platform.files) {
    assert.ok(
      typeof file.file === 'string' &&
        !expected.has(file.file) &&
        fraction(file.minimumBranchCoverage) &&
        Array.isArray(file.functions),
      'Invalid file metric budget.',
    );
    expected.set(file.file, file);
    for (const func of file.functions) {
      assert.ok(
        typeof func.id === 'string' &&
          func.id.startsWith(file.file + ':') &&
          !expectedFunctions.has(func.id) &&
          positiveInteger(func.maximumComplexity) &&
          fraction(func.minimumCoverage) &&
          Number.isFinite(func.maximumCrap) &&
          func.maximumCrap >= 1 &&
          ['v8-derived branch ranges', 'function invocation'].includes(func.coverageBasis),
        'Invalid function metric budget.',
      );
      expectedFunctions.add(func.id);
    }
  }
  for (const file of report.files) {
    const baseline = expected.get(file.file);
    const floor = baseline?.minimumBranchCoverage ?? 1;
    if (file.branches.fraction + tolerance < floor)
      failures.push('branch coverage regression: ' + file.file);
    const byFunction = new Map((baseline?.functions ?? []).map((func) => [func.id, func]));
    for (const func of file.functions) {
      const limit = byFunction.get(func.id);
      if (!limit) {
        if (!func.invoked || func.coverage !== 1)
          failures.push('new uncovered production function: ' + func.id);
        if (func.complexity > platform.maximumNewComplexity)
          failures.push('new function complexity regression: ' + func.id);
        continue;
      }
      if (func.coverageBasis !== limit.coverageBasis)
        failures.push('coverage basis changed: ' + func.id);
      if (func.complexity > limit.maximumComplexity)
        failures.push('complexity regression: ' + func.id);
      if (func.coverage + tolerance < limit.minimumCoverage)
        failures.push('function coverage regression: ' + func.id);
      if (func.crap > limit.maximumCrap + tolerance) failures.push('CRAP regression: ' + func.id);
    }
  }
  for (const file of expected.keys()) {
    if (!files.has(file)) failures.push('missing baseline production source: ' + file);
  }
  for (const id of expectedFunctions) {
    if (!functions.has(id)) failures.push('missing baseline production function: ' + id);
  }
  return failures;
}

export function baselineForMetrics(report) {
  inspectTypeScriptMetrics(report);
  return {
    maximumNewComplexity: Math.max(
      ...report.files.flatMap((file) => file.functions.map((func) => func.complexity)),
    ),
    files: report.files.map((file) => ({
      file: file.file,
      minimumBranchCoverage: file.branches.fraction,
      functions: file.functions.map((func) => ({
        id: func.id,
        coverageBasis: func.coverageBasis,
        maximumComplexity: func.complexity,
        minimumCoverage: func.coverage,
        maximumCrap: func.crap,
      })),
    })),
  };
}

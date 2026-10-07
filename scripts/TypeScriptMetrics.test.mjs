import assert from 'node:assert/strict';
import test from 'node:test';
import { analyzeFunctions, crap, metricVersions } from './TypeScriptMetrics.mjs';
import { baselineForMetrics, inspectTypeScriptMetrics } from './TypeScriptMetricPolicy.mjs';

const fixture = () => ({
  schemaVersion: 1,
  tools: metricVersions,
  platform: 'fixture/x64',
  files: [
    {
      file: 'pi/fixture.ts',
      sourceSha256: 'a'.repeat(64),
      loaded: true,
      branches: { covered: 1, total: 2, fraction: 0.5 },
      functions: [
        {
          id: 'pi/fixture.ts:route#1',
          invoked: true,
          invocationCount: 1,
          complexity: 4,
          coverage: 0.5,
          crap: 6,
          coverageBasis: 'v8-derived branch ranges',
        },
      ],
    },
  ],
});
const budgetFor = (report) => ({
  schemaVersion: 1,
  tools: metricVersions,
  platforms: { [report.platform]: baselineForMetrics(report) },
});

test('AST enumerates nested, anonymous, class and unloaded functions without counting type syntax', () => {
  const text =
    'class C { constructor() {} get value() { return 1; } method(x?: boolean) { ' +
    'const nested = () => { if (x) return 1; return 0; }; return nested(); } } ' +
    'function route(x: boolean) { if (x) return 1; const callback = () => x ? 1 : 2; return callback(); }';
  const functions = analyzeFunctions('fixture.ts', text).functions;
  assert.equal(functions.length, 6);
  assert.deepEqual(
    functions.map((func) => func.complexity),
    [1, 1, 1, 2, 2, 2],
  );
  assert.equal(new Set(functions.map((func) => func.id)).size, 6);
  assert.throws(() => analyzeFunctions('broken.ts', 'function {'), /Invalid production/);
});

test('cyclomatic convention counts runtime decisions and parameter defaults, separating nested bodies', () => {
  const functions = analyzeFunctions(
    'fixture.ts',
    'function f(x = 1) { if (x) {} for (;;) { break; } ' +
      'while (x) break; do {} while (x); switch (x) { case 1: break; default: break; } ' +
      'try {} catch (e) {} const a = x ? 1 : 2; const b = x && x || x ?? x; ' +
      'const c = x?.value; const nested = () => { if (x) return 1; }; }',
  ).functions;
  assert.equal(functions[0].complexity, 13);
  assert.equal(functions[1].complexity, 2);
});

test('CRAP arithmetic uses a coverage fraction and independently reproduced sample', () => {
  assert.equal(crap(4, 0.5), 6);
  assert.equal(crap(20, 0.5), 70);
  assert.equal(crap(6, 0), 42);
  assert.equal(crap(8, 1), 8);
});

test('measured baseline qualifies and independent branch, complexity and CRAP regressions fail', () => {
  const report = fixture();
  const budget = budgetFor(report);
  assert.deepEqual(inspectTypeScriptMetrics(report, budget), []);
  const branch = structuredClone(report);
  branch.files[0].branches = { covered: 0, total: 2, fraction: 0 };
  assert.match(inspectTypeScriptMetrics(branch, budget).join(','), /branch coverage regression/);
  const complex = structuredClone(report);
  complex.files[0].functions[0].complexity = 5;
  complex.files[0].functions[0].crap = crap(5, 0.5);
  assert.match(inspectTypeScriptMetrics(complex, budget).join(','), /complexity regression/);
  const uncovered = structuredClone(report);
  uncovered.files[0].functions[0].coverage = 0.25;
  uncovered.files[0].functions[0].crap = crap(4, 0.25);
  assert.match(
    inspectTypeScriptMetrics(uncovered, budget).join(','),
    /function coverage regression/,
  );
  const crapBudget = structuredClone(budget);
  crapBudget.platforms[report.platform].files[0].functions[0].maximumCrap = 5;
  assert.deepEqual(inspectTypeScriptMetrics(report, crapBudget), [
    'CRAP regression: pi/fixture.ts:route#1',
  ]);
});

test('new uncovered functions and unloaded files fail even if existing aggregate metrics qualify', () => {
  const report = fixture();
  const budget = budgetFor(report);
  report.files[0].functions.push({
    ...report.files[0].functions[0],
    id: 'pi/fixture.ts:uncalled#1',
    invoked: false,
    invocationCount: 0,
    coverage: 0,
    crap: 20,
  });
  assert.match(
    inspectTypeScriptMetrics(report, budget).join(','),
    /new uncovered production function/,
  );
  const extra = structuredClone(fixture().files[0]);
  extra.file = 'pi/unloaded.ts';
  extra.loaded = false;
  extra.branches = { covered: 0, total: 1, fraction: 0 };
  extra.functions = [
    {
      ...extra.functions[0],
      id: 'pi/unloaded.ts:uncalled#1',
      invoked: false,
      invocationCount: 0,
      coverage: 0,
      crap: 20,
    },
  ];
  report.files.push(extra);
  assert.match(
    inspectTypeScriptMetrics(report, budget).join(','),
    /branch coverage regression: pi\/unloaded/,
  );
});

test('missing metrics, unsupported tools, malformed values and budgets fail closed', () => {
  const report = fixture();
  const budget = budgetFor(report);
  for (const modify of [
    (copy) => {
      copy.files = [];
    },
    (copy) => {
      copy.tools.node = 'v0.0.0';
    },
    (copy) => {
      copy.files[0].functions[0].crap = NaN;
    },
    (copy) => {
      copy.files[0].functions[0].complexity = -1;
    },
    (copy) => {
      copy.files[0].branches.covered = 3;
    },
    (copy) => {
      copy.files[0].functions[0].coverageBasis = 'guess';
    },
    (copy) => {
      copy.files[0].functions[0].invoked = false;
    },
  ]) {
    const copy = structuredClone(report);
    modify(copy);
    assert.throws(() => inspectTypeScriptMetrics(copy, budget));
  }
  const invalid = structuredClone(budget);
  invalid.platforms[report.platform].files[0].minimumBranchCoverage = -1;
  assert.throws(() => inspectTypeScriptMetrics(report, invalid), /Invalid file metric budget/);
  assert.throws(
    () => inspectTypeScriptMetrics(report, { ...budget, platforms: {} }),
    /No reviewed native/,
  );
});

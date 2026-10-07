import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { dirname, join, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
assert.equal(process.argv[2], '--output');
assert.ok(process.argv[3] && process.argv.length === 4, 'Use --output <directory>.');
const output = resolve(process.argv[3]);
mkdirSync(output, { recursive: true });
const measure = join(root, 'scripts/Measure-TypeScriptMetrics.mjs');
const budgetPath = join(root, 'scripts/typescript-metric-budgets.json');
function capture(name, extra = [], env = process.env) {
  const folder = join(output, name);
  const result = spawnSync(
    process.execPath,
    [measure, '--output', folder, '--budget', budgetPath, ...extra],
    { cwd: root, env, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 },
  );
  let primaryError;
  try {
    assert.ifError(result.error);
    assert.ok(result.status !== 0, 'Controlled metric failure unexpectedly qualified.');
  } catch (error) {
    primaryError = error;
  }
  try {
    writeFileSync(
      join(folder, 'fixture.log'),
      (result.stdout || '') + (result.stderr || ''),
      'utf8',
    );
  } catch (error) {
    if (!primaryError) throw error;
    console.error('Fixture log write failed; preserving original error.');
  }
  if (primaryError) throw primaryError;
  return JSON.parse(readFileSync(join(folder, 'summary.json'), 'utf8'));
}

const source = join(root, 'pi/jev-decide/jev-core.ts');
const original = readFileSync(source);
const added =
  '\nexport function controlledUncoveredMetricFunction(value: boolean): number { if (value) return 1; return 0; }\n';
let primaryError;
try {
  writeFileSync(source, Buffer.concat([original, Buffer.from(added)]));
  const summary = capture('uncalled-function');
  assert.equal(summary.policyPassed, false);
  assert.ok(
    summary.failures.some(
      (message) =>
        message.includes('new uncovered production function:') &&
        message.includes('controlledUncoveredMetricFunction'),
    ),
  );
  assert.equal(
    summary.files
      .find((file) => file.file === 'pi/jev-decide/jev-core.ts')
      .functions.find((func) => func.name === 'controlledUncoveredMetricFunction').invoked,
    false,
  );
} catch (error) {
  primaryError = error;
} finally {
  try {
    writeFileSync(source, original);
    assert.deepEqual(readFileSync(source), original);
  } catch (error) {
    if (!primaryError) throw error;
    console.error('Source restoration failed; preserving original fixture error.');
  }
}
if (primaryError) throw primaryError;
console.log('Actual uncalled production function rejected; exact source bytes restored.');

const newFile = join(root, 'pi/jev-decide', 'unloaded-metric-fixture-' + randomUUID() + '.ts');
const relativeFile = relative(root, newFile).replaceAll('\\', '/');
let fixtureCreated = false;
assert.ok(
  relativeFile.startsWith('pi/jev-decide/') && !relativeFile.includes('..'),
  'Fixture path outside repository.',
);
try {
  writeFileSync(newFile, 'export function uncalledInUnloadedFile(): number { return 1; }\n', {
    flag: 'wx',
  });
  fixtureCreated = true;
  const summary = capture('unloaded-file');
  const file = summary.files.find((entry) => entry.file === relativeFile);
  assert.ok(file && !file.loaded && file.functions.length === 1 && !file.functions[0].invoked);
  assert.equal(summary.policyPassed, false);
  assert.ok(
    summary.failures.some(
      (message) =>
        message.includes('new uncovered production function:') && message.includes(relativeFile),
    ),
  );
} catch (error) {
  primaryError = error;
} finally {
  try {
    if (fixtureCreated) rmSync(newFile);
    assert.equal(existsSync(newFile), false);
  } catch (error) {
    if (!primaryError) throw error;
    console.error('Fixture file removal failed; preserving original fixture error.');
  }
}
if (primaryError) throw primaryError;
console.log('Actual unloaded production file included and rejected; fixture removed.');

const failure = join(output, 'primary-write-failure');
mkdirSync(join(failure, 'summary.json'), { recursive: true });
const result = spawnSync(process.execPath, [measure, '--output', failure, '--budget', budgetPath], {
  cwd: root,
  env: { ...process.env, TYPESCRIPT_METRICS_PR_HEAD: 'invalid-candidate' },
  encoding: 'utf8',
});
assert.ifError(result.error);
assert.notEqual(result.status, 0);
assert.match(result.stderr, /preserving the original failure/);
assert.match(result.stderr, /AssertionError/);
assert.match(result.stderr, /invalid-candidate/);
writeFileSync(join(failure, 'fixture.log'), result.stderr, 'utf8');
console.log(
  'Original candidate-validation error survives an actual required-summary write failure.',
);

const successfulFailure = join(output, 'successful-write-failure');
mkdirSync(join(successfulFailure, 'summary.json'), { recursive: true });
const baseline = spawnSync(
  process.execPath,
  [measure, '--output', successfulFailure, '--record-baseline'],
  { cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 },
);
assert.ifError(baseline.error);
assert.notEqual(baseline.status, 0);
assert.doesNotMatch(baseline.stderr, /preserving the original failure/);
assert.match(baseline.stderr, /EISDIR|EPERM|EACCES/);
writeFileSync(join(successfulFailure, 'fixture.log'), baseline.stderr, 'utf8');
console.log(
  'Actual required-summary write failure rejects an otherwise successful baseline capture.',
);

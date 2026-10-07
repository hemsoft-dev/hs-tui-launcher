import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { cpus } from 'node:os';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { buildMetrics, metricVersions } from './TypeScriptMetrics.mjs';
import { baselineForMetrics, inspectTypeScriptMetrics } from './TypeScriptMetricPolicy.mjs';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const options = {
  output: undefined,
  budget: join(root, 'scripts/typescript-metric-budgets.json'),
  recordBaseline: false,
};
for (let index = 2; index < process.argv.length; index++) {
  const argument = process.argv[index];
  if (argument === '--record-baseline') options.recordBaseline = true;
  else if (argument === '--output' || argument === '--budget') {
    assert.ok(process.argv[index + 1], 'Missing metric argument value.');
    options[argument.slice(2)] = process.argv[++index];
  } else throw new Error('Unknown TypeScript metric argument.');
}
assert.ok(options.output, '--output is required.');
const output = resolve(options.output);
mkdirSync(output, { recursive: true });
const report = {
  schemaVersion: 1,
  revision: null,
  pullRequestHead: null,
  workingTreeDirty: null,
  platform: process.platform + '/' + process.arch,
  processor: cpus()[0]?.model,
  tools: metricVersions,
  recordBaseline: options.recordBaseline,
  command: [],
  budgetSha256: null,
  files: [],
  worstFunctions: [],
  sourceExclusions: [
    '*.test.ts test suites',
    '*.d.ts erased declarations',
    '.github/security/fixtures/* inert scanner fixtures',
  ],
  externalRuntimeExclusions: [],
  policyPassed: false,
  failures: [],
};
let primaryError;
const run = (command, args, env = process.env) =>
  spawnSync(command, args, { cwd: root, env, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
function git(...args) {
  const result = run('git', args);
  if (result.error || result.status !== 0)
    throw new Error('Unable to establish TypeScript metric source provenance.');
  return result.stdout.trim();
}
function requiredWrite(path, text) {
  try {
    writeFileSync(path, text, 'utf8');
  } catch (error) {
    if (!primaryError) throw error;
    console.error(
      'TypeScript metric evidence could not be written; preserving the original failure.',
    );
  }
}
try {
  assert.equal(process.version, metricVersions.node, 'Use the reviewed Node version.');
  for (const [name, expected] of Object.entries({
    c8: metricVersions.c8,
    typescript: metricVersions.typescript,
  })) {
    const installed = JSON.parse(
      readFileSync(join(root, 'scripts/coverage-tools/node_modules', name, 'package.json'), 'utf8'),
    );
    assert.equal(installed.version, expected, 'Use the pinned report tools.');
  }
  report.revision = git('rev-parse', 'HEAD');
  assert.match(report.revision, /^[0-9a-f]{40}$/);
  report.pullRequestHead = process.env.TYPESCRIPT_METRICS_PR_HEAD || report.revision;
  assert.match(report.pullRequestHead, /^[0-9a-f]{40}$/);
  report.workingTreeDirty = git('status', '--porcelain', '--untracked-files=normal').length > 0;
  const files = [
    ...new Set(
      git('ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', '*.ts').split('\0'),
    ),
  ]
    .filter(
      (file) =>
        file &&
        !file.endsWith('.test.ts') &&
        !file.endsWith('.d.ts') &&
        !file.startsWith('.github/security/fixtures/'),
    )
    .sort();
  assert.ok(files.length > 0, 'No maintained TypeScript production sources.');
  const directory = join(output, 'coverage');
  const args = [
    join(root, 'scripts/coverage-tools/node_modules/c8/bin/c8.js'),
    '--all',
    '--src',
    '.',
    ...files.flatMap((file) => ['--include', file]),
    '--exclude',
    '**/*.test.ts',
    '--exclude',
    '**/*.d.ts',
    '--extension',
    '.ts',
    '--reporter',
    'json',
    '--reporter',
    'json-summary',
    '--reporter',
    'text',
    '--reports-dir',
    directory,
    '--temp-directory',
    join(directory, 'tmp'),
    'pwsh',
    '-NoProfile',
    '-File',
    'scripts/Test-NodeTests.ps1',
  ];
  report.command = [process.execPath, ...args];
  const env = {
    ...process.env,
    NODE_OPTIONS: (
      (process.env.NODE_OPTIONS || '') +
      ' --import=' +
      pathToFileURL(join(root, 'scripts/mutation-tools/offline.mjs')).href
    ).trim(),
  };
  const result = run(process.execPath, args, env);
  report.toolExitCode = result.status;
  if (result.error || result.status !== 0)
    primaryError =
      result.error ?? new Error('Guarded coverage execution failed (exit ' + result.status + ').');
  requiredWrite(join(output, 'tool.log'), (result.stdout || '') + (result.stderr || ''));
  if (primaryError) throw primaryError;
  report.files = buildMetrics(root, files, directory);
  report.worstFunctions = report.files
    .flatMap((file) => file.functions)
    .toSorted((a, b) => b.crap - a.crap)
    .slice(0, 20);
  let budget;
  if (!options.recordBaseline) {
    const text = readFileSync(options.budget, 'utf8').replace(/^\uFEFF/, '');
    report.budgetSha256 = createHash('sha256').update(text).digest('hex');
    budget = JSON.parse(text);
  }
  report.failures = inspectTypeScriptMetrics(report, budget);
  if (options.recordBaseline) report.baselineProposal = baselineForMetrics(report);
  report.policyPassed = !options.recordBaseline && report.failures.length === 0;
  if (report.failures.length)
    throw new Error('TypeScript metric regression: ' + report.failures.join(', '));
} catch (error) {
  primaryError ??= error;
  report.policyPassed = false;
  if (!report.failures.length) report.failures.push(primaryError.message);
}
requiredWrite(join(output, 'summary.json'), JSON.stringify(report, null, 2) + '\n');
if (primaryError) throw primaryError;
console.log(
  'TypeScript metrics complete: ' +
    report.files.length +
    ' sources, ' +
    report.files.reduce((count, file) => count + file.functions.length, 0) +
    ' functions; baseline-only=' +
    options.recordBaseline,
);

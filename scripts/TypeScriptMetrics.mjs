import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from './coverage-tools/node_modules/typescript/lib/typescript.js';

export const metricVersions = { node: 'v24.12.0', c8: '12.0.0', typescript: '5.9.3' };
export const canonicalPath = (path) =>
  process.platform === 'win32' ? resolve(path).toLowerCase() : resolve(path);
export const crap = (complexity, coverage) => complexity ** 2 * (1 - coverage) ** 3 + complexity;

export function analyzeFunctions(file, text) {
  const source = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
  assert.equal(source.parseDiagnostics.length, 0, 'Invalid production TypeScript syntax.');
  const functions = [];
  const ordinals = new Map();
  const decisionKinds = new Set([
    ts.SyntaxKind.IfStatement,
    ts.SyntaxKind.ForStatement,
    ts.SyntaxKind.ForInStatement,
    ts.SyntaxKind.ForOfStatement,
    ts.SyntaxKind.WhileStatement,
    ts.SyntaxKind.DoStatement,
    ts.SyntaxKind.CaseClause,
    ts.SyntaxKind.CatchClause,
    ts.SyntaxKind.ConditionalExpression,
  ]);
  const logicalKinds = new Set([
    ts.SyntaxKind.AmpersandAmpersandToken,
    ts.SyntaxKind.BarBarToken,
    ts.SyntaxKind.QuestionQuestionToken,
    ts.SyntaxKind.AmpersandAmpersandEqualsToken,
    ts.SyntaxKind.BarBarEqualsToken,
    ts.SyntaxKind.QuestionQuestionEqualsToken,
  ]);
  const hasBody = (node) => ts.isFunctionLike(node) && node.body !== undefined;
  function complexity(node) {
    let count = 1;
    function visit(child) {
      if (child !== node && hasBody(child)) return;
      if (ts.isTypeNode(child)) return;
      if (decisionKinds.has(child.kind)) count++;
      if (ts.isBinaryExpression(child) && logicalKinds.has(child.operatorToken.kind)) count++;
      if (child.questionDotToken) count++;
      if (ts.isParameter(child) && child.initializer) count++;
      ts.forEachChild(child, visit);
    }
    visit(node);
    return count;
  }
  function visit(node, container) {
    let next = container;
    if ((ts.isClassDeclaration(node) || ts.isClassExpression(node)) && node.name)
      next = [...container, node.name.text];
    if (hasBody(node)) {
      let name = node.name?.getText(source);
      if (ts.isConstructorDeclaration(node)) name = 'constructor';
      if (!name && (ts.isVariableDeclaration(node.parent) || ts.isPropertyAssignment(node.parent)))
        name = node.parent.name.getText(source);
      name ??= 'callback';
      const base = [...container, name].join('/');
      const ordinal = (ordinals.get(base) ?? 0) + 1;
      ordinals.set(base, ordinal);
      const id = file + ':' + base + '#' + ordinal;
      next = [...container, name + '#' + ordinal];
      functions.push({
        id,
        name,
        start: node.getStart(source),
        end: node.end,
        bodyStart: node.body.getStart(source),
        bodyEnd: node.body.end,
        line: source.getLineAndCharacterOfPosition(node.getStart(source)).line + 1,
        complexity: complexity(node),
      });
    }
    ts.forEachChild(node, (child) => visit(child, next));
  }
  visit(source, []);
  return { source, functions };
}

function checkedCounts(values) {
  assert.ok(
    values.every((value) => Number.isInteger(value) && value >= 0),
    'Invalid coverage counts.',
  );
  const covered = values.filter((value) => value > 0).length;
  return { covered, total: values.length, fraction: values.length ? covered / values.length : 1 };
}

export function buildMetrics(root, files, reportsDirectory) {
  assert.ok(
    files.length > 0 && new Set(files).size === files.length,
    'Missing or duplicate production sources.',
  );
  const istanbul = JSON.parse(
    readFileSync(resolve(reportsDirectory, 'coverage-final.json'), 'utf8'),
  );
  const maps = new Map(
    Object.entries(istanbul).map(([path, value]) => [canonicalPath(path), value]),
  );
  const expected = new Set(files.map((file) => canonicalPath(resolve(root, file))));
  assert.equal(maps.size, expected.size, 'Coverage source set differs from production source set.');
  for (const path of maps.keys()) assert.ok(expected.has(path), 'Unexpected coverage source.');
  const rawFunctions = new Map();
  const temporary = resolve(reportsDirectory, 'tmp');
  const rawFiles = readdirSync(temporary).filter((name) => /^coverage-.*\.json$/.test(name));
  assert.ok(rawFiles.length > 0, 'Missing raw V8 coverage.');
  for (const name of rawFiles) {
    const raw = JSON.parse(readFileSync(resolve(temporary, name), 'utf8'));
    assert.ok(Array.isArray(raw.result), 'Invalid raw V8 coverage.');
    for (const script of raw.result) {
      if (!script.url.startsWith('file:')) continue;
      const path = canonicalPath(fileURLToPath(script.url));
      if (!expected.has(path)) continue;
      const functions = rawFunctions.get(path) ?? [];
      functions.push(...script.functions);
      rawFunctions.set(path, functions);
    }
  }
  return files.map((file) => {
    const path = canonicalPath(resolve(root, file));
    const text = readFileSync(resolve(root, file), 'utf8');
    assert.ok(
      !/\b(?:c8|istanbul|node:coverage)\s+ignore\b/.test(text),
      'Production coverage ignores are not permitted.',
    );
    const { source, functions } = analyzeFunctions(file, text);
    const map = maps.get(path);
    assert.ok(map?.branchMap && map.b && map.fnMap && map.f, 'Incomplete Istanbul report.');
    const offset = (point) => {
      assert.ok(
        Number.isInteger(point?.line) &&
          point.line >= 1 &&
          Number.isInteger(point.column) &&
          point.column >= -2,
        'Invalid coverage source position.',
      );
      const starts = source.getLineStarts();
      assert.ok(point.line <= starts.length, 'Coverage line is outside production source.');
      const lineStart = starts[point.line - 1];
      const position = lineStart + point.column;
      // v8-to-istanbul can assign a newline byte to the following line,
      // yielding column -1/-2. Preserve its exact offset, not a clamped span.
      assert.ok(
        position >= 0 &&
          position <= text.length &&
          (point.column >= 0 || /^[\r\n]+$/.test(text.slice(position, lineStart))),
        'Invalid coverage column.',
      );
      return position;
    };
    const owned = new Map(functions.map((func) => [func.id, []]));
    const allBranches = [];
    assert.deepEqual(
      Object.keys(map.branchMap).sort(),
      Object.keys(map.b).sort(),
      'Incomplete branch counters.',
    );
    assert.deepEqual(
      Object.keys(map.fnMap).sort(),
      Object.keys(map.f).sort(),
      'Incomplete function counters.',
    );
    for (const [key, branch] of Object.entries(map.branchMap)) {
      const counts = map.b[key];
      assert.ok(
        Array.isArray(counts) && counts.length > 0 && counts.length === branch.locations.length,
        'Invalid branch locations/counts.',
      );
      checkedCounts(counts);
      for (let index = 0; index < counts.length; index++) {
        const location = branch.locations[index];
        const start = offset(location.start);
        const end = offset(location.end);
        assert.ok(end >= start && end <= text.length, 'Invalid branch span.');
        allBranches.push(counts[index]);
        const owner = functions
          .filter((func) => start >= func.start && start < func.end)
          .sort((a, b) => a.end - a.start - (b.end - b.start))[0];
        if (owner) owned.get(owner.id).push(counts[index]);
      }
    }
    const raw = rawFunctions.get(path) ?? [];
    const measurements = functions.map((func) => {
      // Native type stripping preserves offsets. Match the exact body end;
      // enclosing module/function execution cannot give an uncalled child credit.
      const matches = raw.filter(
        (item) =>
          item.ranges?.[0]?.endOffset === func.bodyEnd &&
          item.ranges[0].startOffset <= func.bodyStart &&
          item.ranges[0].startOffset >= func.start,
      );
      const invocationCounts = matches.map((item) => item.ranges[0].count);
      checkedCounts(invocationCounts);
      const invoked = invocationCounts.some((count) => count > 0);
      const counts = owned.get(func.id);
      const branches = checkedCounts(counts);
      const coverageBasis = counts.length ? 'v8-derived branch ranges' : 'function invocation';
      const coverage = invoked ? (counts.length ? branches.fraction : 1) : 0;
      return {
        ...func,
        invoked,
        invocationCount: invocationCounts.reduce((a, b) => a + b, 0),
        branchCoverage: branches,
        coverageBasis,
        coverage,
        crap: crap(func.complexity, coverage),
      };
    });
    return {
      file: relative(root, resolve(root, file)).replaceAll('\\', '/'),
      sourceSha256: createHash('sha256').update(text).digest('hex'),
      loaded: rawFunctions.has(path),
      branches: checkedCounts(allBranches),
      functions: measurements,
    };
  });
}

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const count = Math.max(1, Number(process.argv[2] || process.env.VOLUME_COUNT || 20000));
const source = ['Schema.gs', 'AiAudit.gs'].map(name =>
  fs.readFileSync(path.join(__dirname, '..', '..', 'sheets', name), 'utf8')).join('\n');
const context = vm.createContext({ Set, Map, Date, Number, Math, JSON, String, Array });
vm.runInContext(source + `
  this.api = {
    CASE_HEADERS, AI_VOLUME_SCENARIOS, buildSyntheticCaseRow, auditCaseRecord,
    volumeScenario, nationalIdFrequency, formatDay
  };
`, context);
const {
  CASE_HEADERS, AI_VOLUME_SCENARIOS, buildSyntheticCaseRow, auditCaseRecord,
  volumeScenario, nationalIdFrequency, formatDay
} = context.api;

const outDir = path.join(__dirname, '..', '..', 'testdata');
fs.mkdirSync(outDir, { recursive: true });
const stem = 'loadtest-' + count;
const csvPath = path.join(outDir, stem + '.csv');
const jsonlPath = path.join(outDir, stem + '.jsonl');
const summaryPath = path.join(outDir, stem + '.summary.json');

function csvCell(value) {
  if (value instanceof Date) return formatDay(value);
  if (value === true) return 'TRUE';
  if (value === false) return 'FALSE';
  if (value === null || value === undefined) return '';
  const text = String(value);
  if (/[",\n\r]/.test(text)) return '"' + text.replace(/"/g, '""') + '"';
  return text;
}

const started = Date.now();
const rows = Array.from({ length: count }, (_, index) => buildSyntheticCaseRow(index));
const freq = nationalIdFrequency(rows);
const byScenario = {};
const bySuggestion = {};
const byConfidence = {};
const csv = fs.createWriteStream(csvPath);
const jsonl = fs.createWriteStream(jsonlPath);
csv.write('\uFEFF' + CASE_HEADERS.map(csvCell).join(',') + '\n');

for (let index = 0; index < rows.length; index++) {
  const row = rows[index];
  const scenario = volumeScenario(index);
  const result = auditCaseRecord(row, {
    nationalIdCount: freq.get(String(row[5] || '').trim().toUpperCase()) || 0,
    referenceDate: row[1]
  });
  csv.write(row.map(csvCell).join(',') + '\n');
  jsonl.write(JSON.stringify({
    caseId: row[0],
    scenario,
    expected: {
      status: result.status,
      suggestion: result.suggestion,
      confidence: result.confidence,
      codes: result.findings.map(item => item.code)
    },
    redacted: {
      toolName: String(row[26] || ''),
      vendorName: String(row[27] || ''),
      purchaseChannel: String(row[29] || ''),
      twdAmount: row[35],
      identityCategory: String(row[10] || ''),
      findings: result.findings.map(item => item.message)
    }
  }) + '\n');
  byScenario[scenario] = (byScenario[scenario] || 0) + 1;
  bySuggestion[result.suggestion] = (bySuggestion[result.suggestion] || 0) + 1;
  byConfidence[result.confidence] = (byConfidence[result.confidence] || 0) + 1;
}

csv.end();
jsonl.end();
const summary = {
  count,
  generatedAt: new Date().toISOString(),
  elapsedMs: Date.now() - started,
  files: { csv: csvPath, jsonl: jsonlPath },
  scenarios: AI_VOLUME_SCENARIOS,
  byScenario,
  bySuggestion,
  byConfidence,
  notes: [
    '全部為合成資料，人工審查決定皆為待審。',
    'CSV 可匯入 Google 試算表；JSONL 給後續 ChatGPT 比對用。',
    '請把 OPENAI_API_KEY 寫在 .env，不要貼到聊天或 Git。'
  ]
};
fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2));
console.log(JSON.stringify({
  count,
  csv: csvPath,
  jsonl: jsonlPath,
  summary: summaryPath,
  elapsedMs: summary.elapsedMs,
  bySuggestion,
  byConfidence,
  scenarioCount: AI_VOLUME_SCENARIOS.length
}, null, 2));

const fs = require('node:fs');
const path = require('node:path');

function readEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return;
  for (const line of fs.readFileSync(filePath, 'utf8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const eq = trimmed.indexOf('=');
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim().replace(/^['"]|['"]$/g, '');
    if (process.env[key] === undefined) process.env[key] = value;
  }
}

readEnvFile(path.join(__dirname, '..', '.env'));

const apiKey = process.env.OPENAI_API_KEY || '';
const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';
const limit = Number(process.argv[2] || process.env.OPENAI_LIMIT || 50);
const jsonlPath = process.argv[3] || path.join(__dirname, '..', 'testdata', 'loadtest-50000.jsonl');

if (!apiKey) {
  console.error('尚未設定 OPENAI_API_KEY。請寫在專案根目錄 .env，不要貼到聊天或 Git。');
  process.exit(1);
}
if (!fs.existsSync(jsonlPath)) {
  console.error('找不到測試資料：' + jsonlPath + '。請先執行 node scripts/generate-volume-cases.js 50000');
  process.exit(1);
}

const records = fs.readFileSync(jsonlPath, 'utf8').trim().split('\n').slice(0, limit).map(line => JSON.parse(line));

async function chat(record) {
  const body = {
    model,
    temperature: 0,
    response_format: { type: 'json_object' },
    messages: [
      {
        role: 'system',
        content: '你是新竹市青年 AI 補助的查核助理。只根據去識別化欄位與規則疑點提出建議，不得核准或駁回案件。輸出 JSON：{"suggestion":"建議核准（仍須人工）|建議補件|建議駁回（仍須人工）|需人工複核","confidence":"高|中|低","extraFindings":["..."]}。資料不足時選需人工複核。'
      },
      {
        role: 'user',
        content: JSON.stringify({
          caseId: record.caseId,
          scenario: record.scenario,
          redacted: record.redacted,
          ruleSuggestion: record.expected.suggestion
        })
      }
    ]
  };
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + apiKey,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });
  if (!response.ok) {
    throw new Error('OpenAI HTTP ' + response.status + ' ' + await response.text());
  }
  const data = await response.json();
  return JSON.parse(data.choices[0].message.content);
}

(async () => {
  const outPath = path.join(path.dirname(jsonlPath), 'openai-audit-' + records.length + '.jsonl');
  const out = fs.createWriteStream(outPath);
  let matched = 0;
  for (const record of records) {
    const modelResult = await chat(record);
    const same = modelResult.suggestion === record.expected.suggestion;
    if (same) matched += 1;
    out.write(JSON.stringify({
      caseId: record.caseId,
      scenario: record.scenario,
      rule: record.expected,
      model: modelResult,
      suggestionMatched: same
    }) + '\n');
  }
  out.end();
  console.log(JSON.stringify({
    count: records.length,
    model,
    matched,
    outPath
  }, null, 2));
})().catch(error => {
  console.error(String(error.message || error));
  process.exit(1);
});

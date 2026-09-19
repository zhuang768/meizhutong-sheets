const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');

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
const model = process.env.OPENAI_MODEL || 'gpt-4o';
if (!apiKey) {
  console.error('尚未設定 OPENAI_API_KEY。請寫在專案根目錄 .env，不要貼到聊天或 Git。');
  process.exit(1);
}

const source = ['Schema.gs', 'AiAudit.gs'].map(name =>
  fs.readFileSync(path.join(__dirname, '..', 'sheets', name), 'utf8')).join('\n');
const context = vm.createContext({
  Set, Map, Date, Number, Math, JSON, String, Array,
  PropertiesService: { getScriptProperties: () => ({ getProperty: () => '' }) }
});
vm.runInContext(source + `
  this.api = {
    DOCUMENT_VISION_PROMPT, claimedDocumentPayload, mergeDocumentVision,
    auditCaseRecord, buildSyntheticCaseRow
  };
`, context);
const {
  DOCUMENT_VISION_PROMPT, claimedDocumentPayload, mergeDocumentVision,
  auditCaseRecord, buildSyntheticCaseRow
} = context.api;

spawnSync('python3', [path.join(__dirname, 'make-synthetic-documents.py')], { stdio: 'inherit' });
const docs = path.join(__dirname, '..', 'testdata', 'documents');

function imagePart(fileName, label) {
  const bytes = fs.readFileSync(path.join(docs, fileName));
  return [
    { type: 'text', text: label },
    {
      type: 'image_url',
      image_url: { url: 'data:image/png;base64,' + bytes.toString('base64') }
    }
  ];
}

async function inspect(claimed, files) {
  const content = [{ type: 'text', text: '申請資料：' + JSON.stringify(claimed) }];
  files.forEach(file => content.push(...imagePart(file.name, file.label)));
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + apiKey,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      model,
      temperature: 0,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: DOCUMENT_VISION_PROMPT },
        { role: 'user', content }
      ]
    })
  });
  if (!response.ok) {
    throw new Error('OpenAI HTTP ' + response.status + ' ' + await response.text());
  }
  const body = await response.json();
  return JSON.parse(body.choices[0].message.content);
}

const claimedRow = buildSyntheticCaseRow(0, {
  scenario: 'pass',
  nationalId: 'TEST-ID-ONLY',
  fullName: '合成林青禾'
});
const claimed = claimedDocumentPayload(claimedRow);

const samples = [
  {
    name: '三件皆符合',
    files: [
      { name: 'match-id-front.png', label: '身分證正面' },
      { name: 'match-id-back.png', label: '身分證背面' },
      { name: 'match-receipt.png', label: '官方收據' },
      { name: 'match-affidavit.png', label: '親簽切結書' }
    ]
  },
  {
    name: '身分證與發票不符、切結書未簽',
    files: [
      { name: 'mismatch-id-front.png', label: '身分證正面' },
      { name: 'match-id-back.png', label: '身分證背面' },
      { name: 'mismatch-receipt.png', label: '官方收據' },
      { name: 'unsigned-affidavit.png', label: '親簽切結書' }
    ]
  }
];

(async () => {
  const out = [];
  for (const sample of samples) {
    const vision = await inspect(claimed, sample.files);
    const result = mergeDocumentVision(
      auditCaseRecord(claimedRow, { nationalIdCount: 1 }),
      vision
    );
    out.push({
      sample: sample.name,
      vision,
      suggestion: result.suggestion,
      findings: result.findings.filter(item => String(item.code).indexOf('IMAGE') >= 0 || String(item.code).indexOf('AFFIDAVIT') >= 0).map(item => item.message)
    });
  }
  const report = path.join(docs, 'gpt-document-audit.json');
  fs.writeFileSync(report, JSON.stringify(out, null, 2));
  console.log(JSON.stringify({ model, report, samples: out.map(item => ({
    sample: item.sample,
    suggestion: item.suggestion,
    findings: item.findings
  })) }, null, 2));
})().catch(error => {
  console.error(String(error.message || error));
  process.exit(1);
});

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

class Sheet {
  constructor(name, rows = []) { this.name = name; this.rows = rows; }
  getName() { return this.name; }
  getParent() { return book; }
  getLastRow() { return this.rows.length; }
  getLastColumn() { return this.rows.reduce((max, row) => Math.max(max, (row || []).length), 1); }
  getMaxRows() { return 100; }
  appendRow(row) { this.rows.push(row); }
  deleteRow(index) { this.rows.splice(index - 1, 1); }
  hideSheet() {}
  clearContents() { this.rows = []; }
  setConditionalFormatRules() {}
  insertSheet() { return this; }
  getDataRange() { return { getValues: () => this.rows }; }
  getRange(row, column, rowCount = 1, columnCount = 1) {
    return {
      getSheet: () => this,
      getRow: () => row,
      getColumn: () => column,
      getNumRows: () => rowCount,
      getNumColumns: () => columnCount,
      getValue: () => this.rows[row - 1]?.[column - 1],
      getValues: () => Array.from({ length: rowCount }, (_, r) =>
        Array.from({ length: columnCount }, (_, c) => this.rows[row - 1 + r]?.[column - 1 + c] ?? '')),
      setValue: value => {
        this.rows[row - 1] = this.rows[row - 1] || [];
        this.rows[row - 1][column - 1] = value;
      },
      setValues: values => {
        values.forEach((line, r) => {
          this.rows[row - 1 + r] = this.rows[row - 1 + r] || [];
          line.forEach((value, c) => { this.rows[row - 1 + r][column - 1 + c] = value; });
        });
      },
      setDataValidation: () => {},
      setBackground: () => this,
      setBackgrounds: () => this
    };
  }
}

let sequence = 0;
const properties = new Map([
  ['CLIENT_KEY', 'test-only-key'], ['SPREADSHEET_ID', 'test-only-sheet'],
  ['ATTACHMENT_FOLDER_ID', 'test-only-folder'], ['TOKEN_SECRET', 'test-only-secret']
]);
const caseSheet = new Sheet('_原始資料_69欄');
const summarySheet = new Sheet('申請案件', [[
  '案件編號', '送出時間', '申請人姓名', 'AI 工具名稱', '換算新臺幣', '審查狀態', '承辦公開說明'
]]);
const applicantSheet = new Sheet('申請資料');
const attachmentsSheet = new Sheet('附件');
const aiSheet = new Sheet('AI 查核');
const reviewSheet = new Sheet('人工審查');
const tokenSheet = new Sheet('案件憑證', [['送件識別碼', '案件編號', '查詢憑證雜湊']]);
const book = {
  getSheetByName: name => ({
    '_原始資料_69欄': caseSheet, '申請案件': summarySheet,
    '申請資料': applicantSheet, '附件': attachmentsSheet,
    'AI 查核': aiSheet, '人工審查': reviewSheet,
    '案件憑證': tokenSheet
  })[name],
  getId: () => 'test-only-sheet'
};
const context = vm.createContext({
  Set,
  Map,
  Date,
  Logger: { log() {} },
  SpreadsheetApp: { openById: () => book },
  PropertiesService: { getScriptProperties: () => ({
    getProperty: key => properties.get(key), setProperty: (key, value) => properties.set(key, value)
  }) },
  LockService: { getScriptLock: () => ({ waitLock: () => {}, releaseLock: () => {} }) },
  DriveApp: { getFolderById: () => ({ createFile: () => { throw new Error('unexpected upload'); } }) },
  Utilities: {
    getUuid: () => `00000000-0000-0000-0000-${String(++sequence).padStart(12, '0')}`,
    computeHmacSha256Signature: (value, key) => [...crypto.createHmac('sha256', key).update(value).digest()],
    computeDigest: (_algorithm, value) => [...crypto.createHash('sha256').update(value).digest()],
    DigestAlgorithm: { SHA_256: 'sha256' }
  },
  ContentService: {
    MimeType: { JSON: 'json' },
    createTextOutput: text => ({ text, setMimeType() { return this; } })
  }
});
const scripts = ['Schema.gs', 'Server.gs', 'AiAudit.gs'].map(name =>
  fs.readFileSync(path.join(__dirname, '..', '..', 'sheets', name), 'utf8')).join('\n');
vm.runInContext(scripts + '\nthis.api = { CASE_HEADERS, doPost, onEdit, assertCaseHeaders, assertDisplaySheets, approveAiSuggestedPass, applyAiSuggestedRepair, applyAiSuggestedReject, aiDisplayHeaders, ensureAiDisplaySheet, splitAiFindings };', context);
const { CASE_HEADERS, doPost, onEdit, assertCaseHeaders, assertDisplaySheets, approveAiSuggestedPass, applyAiSuggestedRepair, applyAiSuggestedReject, aiDisplayHeaders, ensureAiDisplaySheet, splitAiFindings } = context.api;
caseSheet.rows.push([...CASE_HEADERS]);
applicantSheet.rows.push(['案件編號', ...CASE_HEADERS.slice(4, 49)]);
attachmentsSheet.rows.push(['案件編號', ...CASE_HEADERS.slice(49, 61)]);
aiSheet.rows.push(aiDisplayHeaders());
reviewSheet.rows.push(['案件編號', ...CASE_HEADERS.slice(65, 68)]);
assertCaseHeaders(caseSheet);
assertDisplaySheets(book);

const application = {
  action: 'submit', clientKey: 'test-only-key', clientSubmissionId: 'TEST-SUBMISSION-1',
  applicant: { fullName: '測試申請人' },
  purchase: { toolName: '測試工具', charges: [{ twdAmount: '650' }] },
  form: { nationalID: 'TEST-ID-ONLY', receiptConfirmations: ['buyer'] },
  documents: []
};
function post(body) {
  return JSON.parse(doPost({ postData: { contents: JSON.stringify(body) } }).text);
}
const received = post(application);
assert.equal(received.ok, true);
assert.equal(received.case.status, 'submitted');
assert.equal(caseSheet.rows.length, 2);
assert.equal(caseSheet.rows[1][CASE_HEADERS.indexOf('申請人姓名')], '測試申請人');
assert.equal(caseSheet.rows[1][CASE_HEADERS.indexOf('換算新臺幣')], 650);
assert.equal(summarySheet.rows[1][2], '測試申請人');
assert.equal(summarySheet.rows[1][4], 650);
assert.equal(applicantSheet.rows[1][1], '測試申請人');
assert.equal(attachmentsSheet.rows[1][0], received.case.caseId);
assert.equal(aiSheet.rows[1][1], '已查核');
assert.match(String(aiSheet.rows[1][2]), /^建議|^需人工/);
assert.ok(splitAiFindings(caseSheet.rows[1][CASE_HEADERS.indexOf('AI 疑點')]).length >= 1);
assert.ok(String(aiSheet.rows[1][4] || '').length > 0);
assert.equal(String(aiSheet.rows[1][4]).includes('；'), false);
assert.equal(reviewSheet.rows[1][1], '待審');
assert.equal(caseSheet.rows[1][CASE_HEADERS.indexOf('人工審查決定')], '待審');

const retry = post(application);
assert.equal(retry.case.caseId, received.case.caseId);
assert.equal(retry.accessToken, received.accessToken);
assert.equal(caseSheet.rows.length, 2);
assert.equal(summarySheet.rows.length, 2);

reviewSheet.rows[1][1] = '核准';
onEdit({ range: reviewSheet.getRange(2, 2) });
assert.equal(caseSheet.rows[1][CASE_HEADERS.indexOf('審查狀態')], '已核准');
assert.equal(summarySheet.rows[1][5], '已核准');
assert.equal(caseSheet.rows[1][CASE_HEADERS.indexOf('人工審查決定')], '核准');
const status = post({ action: 'status', clientKey: 'test-only-key',
  caseId: received.case.caseId, accessToken: received.accessToken });
assert.equal(status.ok, true);
assert.equal(status.status, 'approved');
reviewSheet.rows[1][1] = '需補件';
onEdit({ range: reviewSheet.getRange(2, 2) });
assert.equal(summarySheet.rows[1][5], '需補件');
assert.equal(post({ action: 'status', clientKey: 'test-only-key',
  caseId: received.case.caseId, accessToken: received.accessToken }).status, 'needs_documents');
assert.equal(post({ action: 'status', clientKey: 'test-only-key',
  caseId: received.case.caseId, accessToken: 'wrong' }).ok, false);
assert.equal(post({ ...application, clientKey: 'wrong' }).ok, false);

caseSheet.rows[1][CASE_HEADERS.indexOf('AI 查核建議')] = '建議核准（仍須人工）';
caseSheet.rows[1][CASE_HEADERS.indexOf('人工審查決定')] = '待審';
caseSheet.rows[1][CASE_HEADERS.indexOf('審查狀態')] = '待審';
reviewSheet.rows[1][1] = '待審';
assert.match(approveAiSuggestedPass(), /已人工將 1 筆改為「核准」/);
assert.equal(reviewSheet.rows[1][1], '核准');
assert.equal(caseSheet.rows[1][CASE_HEADERS.indexOf('審查狀態')], '已核准');
assert.equal(summarySheet.rows[1][5], '已核准');
assert.equal(post({ action: 'status', clientKey: 'test-only-key',
  caseId: received.case.caseId, accessToken: received.accessToken }).status, 'approved');
assert.match(approveAiSuggestedPass(), /沒有/);

caseSheet.rows[1][CASE_HEADERS.indexOf('AI 查核建議')] = '建議補件';
caseSheet.rows[1][CASE_HEADERS.indexOf('人工審查決定')] = '待審';
caseSheet.rows[1][CASE_HEADERS.indexOf('審查狀態')] = '待審';
reviewSheet.rows[1][1] = '待審';
summarySheet.rows[1][5] = '待審';
assert.match(applyAiSuggestedRepair(), /已人工將 1 筆改為「需補件」/);
assert.equal(reviewSheet.rows[1][1], '需補件');
assert.equal(post({ action: 'status', clientKey: 'test-only-key',
  caseId: received.case.caseId, accessToken: received.accessToken }).status, 'needs_documents');

caseSheet.rows[1][CASE_HEADERS.indexOf('AI 查核建議')] = '建議駁回（仍須人工）';
caseSheet.rows[1][CASE_HEADERS.indexOf('人工審查決定')] = '待審';
caseSheet.rows[1][CASE_HEADERS.indexOf('審查狀態')] = '待審';
reviewSheet.rows[1][1] = '待審';
summarySheet.rows[1][5] = '待審';
assert.match(applyAiSuggestedReject(), /已人工將 1 筆改為「駁回」/);
assert.equal(reviewSheet.rows[1][1], '駁回');
assert.equal(post({ action: 'status', clientKey: 'test-only-key',
  caseId: received.case.caseId, accessToken: received.accessToken }).status, 'rejected');

caseSheet.rows[1][CASE_HEADERS.indexOf('AI 查核建議')] = '需人工複核';
caseSheet.rows[1][CASE_HEADERS.indexOf('人工審查決定')] = '待審';
reviewSheet.rows[1][1] = '待審';
assert.match(applyAiSuggestedReject(), /沒有/);
assert.equal(reviewSheet.rows[1][1], '待審');

aiSheet.rows = [['案件編號', 'AI 查核狀態', 'AI 查核建議', 'AI 疑點', 'AI 信心程度'],
  ['MZT-SPLIT', '已查核', '建議補件', '身分證影像與申請資料一致；切結書未見手寫簽名', '中']];
assert.match(ensureAiDisplaySheet(book), /分階段|上色/);
assert.equal(aiSheet.rows[0][4], '規則');
assert.equal(aiSheet.rows[1][5], '身分證影像與申請資料一致');
assert.equal(aiSheet.rows[1][7], '切結書未見手寫簽名');
aiSheet.rows[0] = aiDisplayHeaders();

caseSheet.rows[0][4] = '錯誤標題';
assert.throws(() => assertCaseHeaders(caseSheet));
applicantSheet.rows[0][1] = '錯誤標題';
assert.throws(() => assertDisplaySheets(book));
console.log('收件、重試、人工決定與狀態查詢測試通過');

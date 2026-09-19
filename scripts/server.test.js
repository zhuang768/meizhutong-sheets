const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

class Sheet {
  constructor(name, rows = []) { this.name = name; this.rows = rows; }
  getName() { return this.name; }
  getLastRow() { return this.rows.length; }
  getMaxRows() { return 100; }
  appendRow(row) { this.rows.push(row); }
  deleteRow(index) { this.rows.splice(index - 1, 1); }
  hideSheet() {}
  getDataRange() { return { getValues: () => this.rows }; }
  getRange(row, column, rowCount = 1, columnCount = 1) {
    return {
      getSheet: () => this,
      getRow: () => row,
      getColumn: () => column,
      getNumRows: () => rowCount,
      getValue: () => this.rows[row - 1]?.[column - 1],
      getValues: () => Array.from({ length: rowCount }, (_, r) =>
        Array.from({ length: columnCount }, (_, c) => this.rows[row - 1 + r]?.[column - 1 + c] ?? '')),
      setValue: value => { this.rows[row - 1][column - 1] = value; },
      setDataValidation: () => {}
    };
  }
}

let sequence = 0;
const properties = new Map([
  ['CLIENT_KEY', 'test-only-key'], ['SPREADSHEET_ID', 'test-only-sheet'],
  ['ATTACHMENT_FOLDER_ID', 'test-only-folder'], ['TOKEN_SECRET', 'test-only-secret']
]);
const caseSheet = new Sheet('申請案件');
const tokenSheet = new Sheet('案件憑證', [['送件識別碼', '案件編號', '查詢憑證雜湊']]);
const book = {
  getSheetByName: name => ({ '申請案件': caseSheet, '案件憑證': tokenSheet })[name],
  getId: () => 'test-only-sheet'
};
const context = vm.createContext({
  Set,
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
const scripts = ['Schema.gs', 'Server.gs'].map(name =>
  fs.readFileSync(path.join(__dirname, '..', 'sheets', name), 'utf8')).join('\n');
vm.runInContext(scripts + '\nthis.api = { CASE_HEADERS, doPost, onEdit, assertCaseHeaders };', context);
const { CASE_HEADERS, doPost, onEdit, assertCaseHeaders } = context.api;
caseSheet.rows.push([...CASE_HEADERS]);
assertCaseHeaders(caseSheet);

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

const retry = post(application);
assert.equal(retry.case.caseId, received.case.caseId);
assert.equal(retry.accessToken, received.accessToken);
assert.equal(caseSheet.rows.length, 2);

const decisionColumn = CASE_HEADERS.indexOf('人工審查決定') + 1;
caseSheet.rows[1][decisionColumn - 1] = '核准';
onEdit({ range: caseSheet.getRange(2, decisionColumn) });
assert.equal(caseSheet.rows[1][CASE_HEADERS.indexOf('審查狀態')], '已核准');
const status = post({ action: 'status', clientKey: 'test-only-key',
  caseId: received.case.caseId, accessToken: received.accessToken });
assert.equal(status.ok, true);
assert.equal(status.status, 'approved');
assert.equal(post({ action: 'status', clientKey: 'test-only-key',
  caseId: received.case.caseId, accessToken: 'wrong' }).ok, false);
assert.equal(post({ ...application, clientKey: 'wrong' }).ok, false);

caseSheet.rows[0][4] = '錯誤標題';
assert.throws(() => assertCaseHeaders(caseSheet));
console.log('收件、重試、人工決定與狀態查詢測試通過');

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', 'sheets', 'Schema.gs'), 'utf8');
const context = vm.createContext({ Set });
vm.runInContext(source + '\nthis.schema = { CASE_HEADERS, submissionToRow, sheetText };', context);
const { CASE_HEADERS, submissionToRow, sheetText } = context.schema;

assert.equal(CASE_HEADERS.length, 69);
assert.equal(CASE_HEADERS[0], '案件編號');
assert.equal(CASE_HEADERS[68], '案件查詢代碼');
const submission = {
  applicant: { fullName: '測試申請人', phone: '0900000000' },
  form: { nationalID: 'TEST-ID-ONLY', receiptConfirmations: ['buyer', 'tool'] },
  purchase: { toolName: '測試工具', charges: [{ twdAmount: '650' }] }
};
const row = submissionToRow(submission, {
  caseId: 'TEST-001', submittedAt: '2026-09-19', accessCode: 'TEST-CODE',
  documentLinks: { idFront: 'https://example.invalid/test-only' }
});
assert.equal(row.length, 69);
assert.equal(row[CASE_HEADERS.indexOf('申請人姓名')], '測試申請人');
assert.equal(row[CASE_HEADERS.indexOf('AI 工具名稱')], '測試工具');
assert.equal(row[CASE_HEADERS.indexOf('換算新臺幣')], 650);
assert.equal(row[CASE_HEADERS.indexOf('身分證正面連結')], 'https://example.invalid/test-only');
assert.equal(row[CASE_HEADERS.indexOf('收據已註明購買人')], true);
assert.equal(row[CASE_HEADERS.indexOf('收據有軟體名稱')], true);
assert.equal(row[CASE_HEADERS.indexOf('收據有公司名稱')], false);
assert.equal(row[CASE_HEADERS.indexOf('人工審查決定')], '待審');
assert.equal(sheetText('=IMPORTXML("x", "y")'), "'=IMPORTXML(\"x\", \"y\")");
console.log('試算表 69 欄與申請資料對應測試通過');

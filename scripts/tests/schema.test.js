const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', '..', 'sheets', 'Schema.gs'), 'utf8');
const context = vm.createContext({ Set });
vm.runInContext(source + '\nthis.schema = { CASE_HEADERS, submissionToRow, sheetText, aiDisplayHeaders, splitAiFindings, aiDisplayRow, colorForSuggestion, colorForDecision, colorForFindingText, AI_STAGE_HEADERS, COLOR_APPROVE, COLOR_REPAIR, COLOR_REJECT, COLOR_NOTE };', context);
const { CASE_HEADERS, submissionToRow, sheetText, aiDisplayHeaders, splitAiFindings, aiDisplayRow, colorForSuggestion, colorForDecision, colorForFindingText, AI_STAGE_HEADERS, COLOR_APPROVE, COLOR_REPAIR, COLOR_REJECT, COLOR_NOTE } = context.schema;

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
assert.equal(CASE_HEADERS.slice(65, 68).join(','), '人工審查決定,承辦備註,決定時間');
assert.equal(row[CASE_HEADERS.indexOf('人工審查決定')], '待審');
assert.equal(sheetText('=IMPORTXML("x", "y")'), "'=IMPORTXML(\"x\", \"y\")");
const findings = splitAiFindings('合成測試身分證字號，未做真實檢查碼檢核；預估補助 320 元；切結書未見手寫簽名');
assert.equal(findings.length, 3);
const display = aiDisplayRow('MZT-1', '已查核', '建議補件', '中', findings);
assert.equal(display[0], 'MZT-1');
assert.equal(display[4], '');
assert.equal(display[7], '切結書未見手寫簽名');
assert.match(display[8], /合成測試/);
assert.match(display[8], /預估補助/);
assert.equal(display.length, 4 + AI_STAGE_HEADERS.length);
assert.equal(aiDisplayHeaders()[4], '規則');
assert.equal(colorForSuggestion('建議核准（仍須人工）'), COLOR_APPROVE);
assert.equal(colorForSuggestion('建議補件'), COLOR_REPAIR);
assert.equal(colorForSuggestion('需人工複核'), COLOR_REJECT);
assert.equal(colorForFindingText('身分證影像與申請資料一致'), COLOR_APPROVE);
assert.equal(colorForFindingText('切結書未見手寫簽名'), COLOR_REJECT);
assert.equal(colorForFindingText('預估補助 320 元，非核定金額'), COLOR_NOTE);
assert.equal(colorForDecision('核准'), COLOR_APPROVE);
assert.equal(colorForDecision('已核准'), COLOR_APPROVE);
assert.equal(colorForDecision('需補件'), COLOR_REPAIR);
assert.equal(colorForDecision('駁回'), COLOR_REJECT);
assert.equal(colorForDecision('待審'), '');
console.log('試算表 69 欄與申請資料對應測試通過');

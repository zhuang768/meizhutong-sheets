const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = ['Schema.gs', 'AiAudit.gs'].map(name =>
  fs.readFileSync(path.join(__dirname, '..', 'sheets', name), 'utf8')).join('\n');
const context = vm.createContext({ Set, Map, Date, Number, Math, JSON, String, Array });
vm.runInContext(source + `
  this.api = {
    CASE_HEADERS, AI_VOLUME_SCENARIOS, auditCaseRecord, buildSyntheticCaseRow,
    volumeScenario, plannedNationalId, makeTaiwanId, taiwanIdChecksumOk,
    redactedModelPayload, nationalIdFrequency, applyResultToRow, formatDay,
    claimedDocumentPayload, mergeDocumentVision, hasDocumentVision
  };
`, context);
const {
  CASE_HEADERS, AI_VOLUME_SCENARIOS, auditCaseRecord, buildSyntheticCaseRow,
  volumeScenario, plannedNationalId, makeTaiwanId, taiwanIdChecksumOk,
  redactedModelPayload, nationalIdFrequency, applyResultToRow,
  claimedDocumentPayload, mergeDocumentVision, hasDocumentVision
} = context.api;

assert.equal(taiwanIdChecksumOk('A123456789'), true);
assert.equal(taiwanIdChecksumOk('A123456780'), false);
assert.equal(taiwanIdChecksumOk('TEST-ID-ONLY'), false);
assert.equal(taiwanIdChecksumOk(makeTaiwanId(42)), true);

function audit(row, extra) {
  return auditCaseRecord(row, extra || {});
}

const pass = buildSyntheticCaseRow(0, { scenario: 'pass', nationalId: makeTaiwanId(0) });
const passResult = audit(pass, { nationalIdCount: 1 });
assert.equal(passResult.status, '已查核');
assert.equal(passResult.suggestion, '建議核准（仍須人工）');
assert.equal(passResult.confidence, '中');
assert.equal(pass[CASE_HEADERS.indexOf('人工審查決定')], '待審');

const resident = buildSyntheticCaseRow(1, { scenario: 'notResident' });
assert.equal(audit(resident).suggestion, '建議駁回（仍須人工）');
assert.ok(audit(resident).findings.some(item => item.code === 'RESIDENT'));

const badId = buildSyntheticCaseRow(2, { scenario: 'badId', nationalId: 'A123456780' });
const badIdResult = audit(badId, { nationalIdCount: 1 });
assert.equal(badIdResult.suggestion, '建議補件');
assert.ok(badIdResult.findings.some(item => item.code === 'ID_CHECKSUM'));
assert.equal(badIdResult.findingsText.includes('A123456780'), false);

const missing = buildSyntheticCaseRow(3, { scenario: 'missingDocs' });
assert.equal(audit(missing).suggestion, '建議補件');
assert.ok(audit(missing).findings.some(item => String(item.code).indexOf('DOC_') === 0));

const prepaid = buildSyntheticCaseRow(4, { scenario: 'prepaid' });
assert.equal(audit(prepaid).suggestion, '建議駁回（仍須人工）');
assert.ok(audit(prepaid).findings.some(item => item.code === 'PREPAID'));

const aggregator = buildSyntheticCaseRow(5, { scenario: 'aggregator' });
assert.equal(audit(aggregator).suggestion, '建議駁回（仍須人工）');
assert.ok(audit(aggregator).findings.some(item => item.code === 'CHANNEL'));

const age = buildSyntheticCaseRow(6, { scenario: 'ageTooOld' });
assert.equal(audit(age).suggestion, '建議駁回（仍須人工）');
assert.ok(audit(age).findings.some(item => item.code === 'AGE'));

const special = buildSyntheticCaseRow(7, { scenario: 'specialMissing' });
assert.equal(audit(special).suggestion, '建議補件');
assert.ok(audit(special).findings.some(item => item.message.includes('特定對象')));

const proxy = buildSyntheticCaseRow(8, { scenario: 'proxyMissing' });
assert.equal(audit(proxy).suggestion, '建議補件');
assert.ok(audit(proxy).findings.some(item => item.message.includes('代付')));

const duplicate = buildSyntheticCaseRow(9, { scenario: 'duplicate', nationalId: makeTaiwanId(9999999) });
const duplicateResult = audit(duplicate, { nationalIdCount: 12 });
assert.equal(duplicateResult.suggestion, '需人工複核');
assert.equal(duplicateResult.confidence, '低');
assert.equal(duplicateResult.findingsText.includes(makeTaiwanId(9999999)), false);

const synthetic = buildSyntheticCaseRow(10, { scenario: 'pass', nationalId: 'TEST-ID-ONLY' });
const syntheticResult = audit(synthetic, { nationalIdCount: 99 });
assert.ok(syntheticResult.findings.some(item => item.code === 'ID_SYNTHETIC'));
assert.equal(syntheticResult.findings.some(item => item.code === 'ID_CHECKSUM'), false);
assert.equal(syntheticResult.findings.some(item => item.code === 'ID_DUPLICATE'), false);

const payload = JSON.stringify(redactedModelPayload(pass));
assert.equal(payload.includes(pass[CASE_HEADERS.indexOf('身分證字號')]), false);
assert.equal(payload.includes(pass[CASE_HEADERS.indexOf('聯絡電話')]), false);
assert.equal(payload.includes(pass[CASE_HEADERS.indexOf('電子郵件')]), false);
assert.equal(payload.includes(pass[CASE_HEADERS.indexOf('戶籍地址')]), false);
assert.ok(payload.includes('ChatGPT Plus'));

const rows = Array.from({ length: AI_VOLUME_SCENARIOS.length * 2 }, (_, index) => buildSyntheticCaseRow(index));
const freq = nationalIdFrequency(rows);
assert.equal(volumeScenario(0), 'pass');
assert.equal(volumeScenario(AI_VOLUME_SCENARIOS.indexOf('duplicate')), 'duplicate');
assert.equal(AI_VOLUME_SCENARIOS.length, 40);
assert.ok((freq.get(plannedNationalId(AI_VOLUME_SCENARIOS.indexOf('duplicate'))) || 0) >= 2);

AI_VOLUME_SCENARIOS.forEach((scenario, index) => {
  const row = buildSyntheticCaseRow(index, { scenario });
  assert.equal(row.length, 69);
  const result = audit(row, { nationalIdCount: scenario === 'duplicate' ? 3 : 1 });
  assert.equal(result.status, '已查核');
  assert.equal(row[CASE_HEADERS.indexOf('人工審查決定')], '待審');
  assert.match(result.suggestion, /^建議|^需人工/);
});

const specialPass = audit(buildSyntheticCaseRow(1, { scenario: 'passSpecial' }));
assert.equal(specialPass.suggestion, '建議核准（仍須人工）');
assert.equal(audit(buildSyntheticCaseRow(12, { scenario: 'vendorRegion' })).suggestion, '建議駁回（仍須人工）');
assert.equal(audit(buildSyntheticCaseRow(11, { scenario: 'reseller' })).suggestion, '建議駁回（仍須人工）');
assert.equal(audit(buildSyntheticCaseRow(22, { scenario: 'missingReceipt' })).suggestion, '建議補件');

applyResultToRow(pass, passResult);
assert.equal(pass[CASE_HEADERS.indexOf('AI 查核狀態')], '已查核');
assert.equal(pass[CASE_HEADERS.indexOf('人工審查決定')], '待審');
assert.match(String(pass[CASE_HEADERS.indexOf('AI 查核建議')]), /建議|需人工/);

const claimed = claimedDocumentPayload(buildSyntheticCaseRow(0, {
  scenario: 'pass', nationalId: 'TEST-ID-ONLY', fullName: '合成林青禾'
}));
assert.equal(claimed.fullName, '合成林青禾');
assert.equal(claimed.toolName, 'ChatGPT Plus');

const matchedVision = mergeDocumentVision(audit(pass, { nationalIdCount: 1 }), {
  idCard: { readable: true, matches: true, mismatches: [] },
  receipt: { readable: true, matches: true, mismatches: [] },
  affidavit: { readable: true, hasSignature: true, nameMatches: true, mismatches: [] }
});
assert.equal(matchedVision.suggestion, '建議核准（仍須人工）');
assert.ok(matchedVision.findings.some(item => item.code === 'ID_IMAGE_OK'));

const mismatchedVision = mergeDocumentVision(audit(pass, { nationalIdCount: 1 }), {
  idCard: { readable: true, matches: false, mismatches: ['姓名'] },
  receipt: { readable: true, matches: false, mismatches: ['金額'] },
  affidavit: { readable: true, hasSignature: false, nameMatches: false, mismatches: ['姓名'] }
});
assert.equal(mismatchedVision.suggestion, '建議補件');
assert.equal(mismatchedVision.findingsText.includes('A123456789'), false);
assert.ok(mismatchedVision.findings.some(item => item.code === 'AFFIDAVIT_SIGNATURE'));
assert.equal(hasDocumentVision(pass), false);
applyResultToRow(pass, mismatchedVision);
assert.equal(hasDocumentVision(pass), true);

console.log('AI 查核規則、信心度分流與去識別化測試通過');

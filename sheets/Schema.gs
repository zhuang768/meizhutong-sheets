// 與「梅竹通」Google 試算表的「申請案件」工作表第一列保持一致。
// 編輯欄位時，請同步更新 schema.test.js，避免資料寫錯欄。
const CASE_HEADERS = [
  '案件編號', '送出時間', '審查狀態', '承辦公開說明',
  '申請人姓名', '身分證字號', '出生日期', '聯絡電話', '電子郵件',
  '設籍新竹市', '身分類別', '特定對象類別', '文化語言證明類別',
  '戶籍郵遞區號', '戶籍行政區', '戶籍地址', '通訊地址同戶籍',
  '通訊郵遞區號', '通訊縣市', '通訊行政區', '通訊詳細地址',
  '匯款銀行', '帳戶末碼', '繳費制度', '月費期數', '工具類別',
  'AI 工具名稱', '軟體公司名稱', '廠商地區符合規定', '購買管道',
  '購買日期', '訂閱起日', '訂閱迄日', '原始費用幣別', '原始費用',
  '換算新臺幣', '付款方式', '預付點數或代幣', '是否由他人代付',
  '代付人姓名', '代付關係', '收據已註明購買人',
  '帳單可證明購買品項', '已附信用卡末四碼及姓名證明',
  '收據有軟體名稱', '收據有公司名稱', '收據有購買日期',
  '收據有原始費用', '收據有新臺幣換算',
  '身分證正面連結', '身分證背面連結', '官方收據連結',
  '新臺幣換算證明連結', '繳款或出帳憑證連結',
  '信用卡末四碼及姓名證明連結', '存摺封面連結',
  '親簽切結書連結', '特定對象證明連結', '文化語言證明連結',
  '代付親屬關係證明連結', '代付共同簽署切結書連結',
  'AI 查核狀態', 'AI 查核建議', 'AI 疑點', 'AI 信心程度',
  '人工審查決定', '承辦備註', '決定時間', '案件查詢代碼'
];

const COLOR_APPROVE = '#D4E2D1';
const COLOR_REPAIR = '#F3E6C8';
const COLOR_REJECT = '#E6D3D1';
const COLOR_NOTE = '#D6E3F0';
const AI_STAGE_HEADERS = ['規則', '身分證影像', '發票影像', '切結書', '說明'];

function aiDisplayHeaders() {
  return ['案件編號', 'AI 查核狀態', 'AI 查核建議', 'AI 信心程度'].concat(AI_STAGE_HEADERS);
}

function splitAiFindings(text) {
  return String(text || '')
    .replace(/身分證影像/g, '；身分證影像')
    .replace(/發票影像/g, '；發票影像')
    .replace(/切結書/g, '；切結書')
    .split(/[；;\n|｜]/)
    .map(item => String(item).trim())
    .filter(Boolean);
}

function findingStage(item) {
  const code = String(item && item.code || '');
  const text = String((item && item.message) || item || '');
  if (code === 'ID_SYNTHETIC' || code === 'SUBSIDY_HINT' || code === 'VISION_ERROR') return '說明';
  if (code.indexOf('ID_IMAGE') === 0 || /身分證影像/.test(text)) return '身分證影像';
  if (code.indexOf('RECEIPT_IMAGE') === 0 || /發票影像/.test(text)) return '發票影像';
  if (code.indexOf('AFFIDAVIT') === 0 || /切結書/.test(text)) return '切結書';
  if (/合成測試|預估補助|非核定/.test(text)) return '說明';
  return '規則';
}

function groupFindingsByStage(findings) {
  const groups = {};
  AI_STAGE_HEADERS.forEach(name => { groups[name] = []; });
  (findings || []).forEach(item => {
    const message = typeof item === 'string' ? item : (item && item.message);
    if (!message) return;
    const stage = findingStage(typeof item === 'string' ? { message: item } : item);
    groups[stage].push(message);
  });
  return AI_STAGE_HEADERS.map(name => groups[name].join('\n'));
}

function aiDisplayRow(caseId, status, suggestion, confidence, findings) {
  return [caseId, status || '', suggestion || '', confidence || ''].concat(groupFindingsByStage(findings));
}

function aiFindingsFromResult(result) {
  if (result && result.findings && result.findings.length) return result.findings;
  return splitAiFindings(result && result.findingsText);
}

function colorForSuggestion(text) {
  const value = String(text || '');
  if (value.indexOf('建議核准') === 0 || value === '核准' || value === '已核准') return COLOR_APPROVE;
  if (value === '建議補件' || value === '需補件') return COLOR_REPAIR;
  if (value.indexOf('建議駁回') === 0 || value === '需人工複核' || value === '駁回' || value === '已駁回') return COLOR_REJECT;
  return '';
}

function colorForDecision(text) {
  const value = String(text || '');
  if (!value || value === '待審') return '';
  return colorForSuggestion(value);
}

function colorForFindingText(text) {
  const value = String(text || '');
  if (!value) return '';
  if (/不一致|未見手寫|不予補助|未設籍|預付|不是官方|集合式|代購|出生日期不在/.test(value)) return COLOR_REJECT;
  if (/未填|無法辨識|請補|缺件|缺所有|缺存摺|格式或檢查碼|不是新竹市|郵遞區號/.test(value)) return COLOR_REPAIR;
  if (/一致|可見簽名/.test(value)) return COLOR_APPROVE;
  if (/合成測試|預估補助|非核定|影像模型未完成/.test(value)) return COLOR_NOTE;
  if (/缺/.test(value)) return COLOR_REPAIR;
  return COLOR_REPAIR;
}

const DOCUMENT_COLUMN_TYPES = [
  'idFront', 'idBack', 'officialReceipt', 'twdConversionProof',
  'paymentProof', 'cardLast4NamePhoto', 'passbookCover',
  'signedAffidavit', 'specialIdentityProof',
  'culturalLanguageCertificate', 'kinshipProof', 'proxyPaymentAffidavit'
];

function sheetText(value) {
  if (value === null || value === undefined) return '';
  if (typeof value === 'boolean' || typeof value === 'number' || value instanceof Date) return value;
  const text = Array.isArray(value) ? value.join('、') : String(value);
  // 試算表會把這些前綴當公式；申請人輸入必須保持純文字。
  return /^[\s]*[=+\-@]/.test(text) ? "'" + text : text;
}

function sheetDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return '';
  const date = new Date(value + 'T12:00:00');
  return Number.isNaN(date.getTime()) ? '' : date;
}

function sheetAmount(value) {
  if (value === null || value === undefined || value === '') return '';
  const number = Number(value);
  return Number.isFinite(number) ? number : '';
}

function submissionToRow(submission, metadata) {
  const applicant = submission.applicant || {};
  const purchase = submission.purchase || {};
  const form = submission.form || {};
  const charge = (purchase.charges || [])[0] || {};
  const receipt = new Set(form.receiptConfirmations || []);
  const links = metadata.documentLinks || {};
  const values = [
    metadata.caseId, metadata.submittedAt, '待審', '',
    applicant.fullName, form.nationalID, sheetDate(applicant.birthDate),
    applicant.phone, applicant.contactEmail, applicant.isHsinchuResident,
    applicant.identityCategory, applicant.specialIdentityKinds,
    applicant.culturalLanguageKinds, form.householdPostalCode,
    form.householdDistrict, applicant.householdAddress,
    form.mailingSameAsHousehold, form.mailingPostalCode, form.mailingCity,
    form.mailingDistrict, form.mailingStreet,
    applicant.bankName, applicant.bankAccountMasked,
    purchase.subscriptionPlan, form.monthlyPeriods,
    purchase.toolCategory, purchase.toolName, purchase.vendorName,
    purchase.vendorRegionCompliant, purchase.purchaseChannel,
    sheetDate(charge.purchaseDate), sheetDate(charge.periodStart), sheetDate(charge.periodEnd),
    charge.originalCurrency, sheetAmount(charge.originalAmount), sheetAmount(charge.twdAmount),
    purchase.paymentMethod, purchase.isPrepaidCreditOrToken,
    purchase.isProxyPaid, purchase.proxyPayerName,
    purchase.proxyPayerRelation,
    receipt.has('buyer'), receipt.has('statement'), receipt.has('card'),
    receipt.has('tool'), receipt.has('vendor'), receipt.has('date'),
    receipt.has('amount'), receipt.has('twd'),
    ...DOCUMENT_COLUMN_TYPES.map(type => links[type] || ''),
    '尚未查核', '', '', '', '待審', '', '', metadata.accessCode
  ];
  if (values.length !== CASE_HEADERS.length) {
    throw new Error('申請資料與試算表欄位數不一致');
  }
  return values.map(sheetText);
}

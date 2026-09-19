// 梅竹通 AI 輔助查核：規則先行、影像模型可選、人工最後決定。
// 只寫入「AI 查核狀態／建議／疑點／信心程度」，絕不改「人工審查決定」。
const AI_LOADTEST_PREFIX = 'MZT-LOADTEST-';
const AI_SYNTHETIC_ID = 'TEST-ID-ONLY';
const AI_BATCH_LIMIT = 250;
const AI_SEED_BATCH = 300;
const AI_FINDINGS_MAX = 45000;
const AI_BIRTH_MIN = '1985-04-03';
const AI_BIRTH_MAX = '2010-04-02';
const AI_PURCHASE_MIN = '2026-04-02';
const AI_PURCHASE_MAX = '2026-10-31';
const AI_HSINCHU_DISTRICTS = ['東區', '北區', '香山區'];
const AI_TAIWAN_ID_LETTERS = {
  A: 10, B: 11, C: 12, D: 13, E: 14, F: 15, G: 16, H: 17, I: 34, J: 18,
  K: 19, L: 20, M: 21, N: 22, O: 35, P: 23, Q: 24, R: 25, S: 26, T: 27,
  U: 28, V: 29, W: 32, X: 30, Y: 31, Z: 33
};
const AI_REQUIRED_DOCS = [
  ['idFront', '身分證正面連結', '身分證正面'],
  ['idBack', '身分證背面連結', '身分證背面'],
  ['officialReceipt', '官方收據連結', '官方收據'],
  ['twdConversionProof', '新臺幣換算證明連結', '換算臺幣證明'],
  ['paymentProof', '繳款或出帳憑證連結', '繳款／出帳憑證'],
  ['cardLast4NamePhoto', '信用卡末四碼及姓名證明連結', '信用卡末四碼及姓名證明'],
  ['passbookCover', '存摺封面連結', '存摺封面'],
  ['signedAffidavit', '親簽切結書連結', '親簽切結書']
];
const AI_RECEIPT_FLAGS = [
  ['收據已註明購買人', '收據證明註明購買人'],
  ['帳單可證明購買品項', '帳單可證明購買品項'],
  ['已附信用卡末四碼及姓名證明', '信用卡末四碼及姓名證明'],
  ['收據有軟體名稱', '收據有軟體名稱'],
  ['收據有公司名稱', '收據有公司名稱'],
  ['收據有購買日期', '收據有購買日期'],
  ['收據有原始費用', '收據有原始費用'],
  ['收據有新臺幣換算', '收據有新臺幣換算']
];

function onOpen() {
  try {
    SpreadsheetApp.getUi().createMenu('梅竹通 AI')
      .addItem('查核尚未查核案件（本批）', 'runAiAuditPending')
      .addItem('重查全部案件（仍不改人工決定）', 'runAiAuditAll')
      .addItem('GPT 核對身分證／發票／切結書（本批）', 'runAiDocumentAuditPending')
      .addSeparator()
      .addItem('產生 1,000 筆合成壓力測試', 'seedVolumeTest1000')
      .addItem('產生 50,000 筆合成壓力測試（分批）', 'seedVolumeTest50000')
      .addItem('清除合成壓力測試資料', 'removeLoadTestCases')
      .addToUi();
  } catch (error) {
    // 由觸發器執行時沒有試算表 UI。
  }
}

function runAiAuditPending() {
  return runAiAuditBatch({ force: false, limit: AI_BATCH_LIMIT });
}

function runAiAuditAll() {
  return runAiAuditBatch({ force: true, limit: AI_BATCH_LIMIT });
}

function seedVolumeTest1000() {
  return seedVolumeTestCases(1000, 0);
}

function seedVolumeTest50000() {
  return seedVolumeTestCases(50000, 0);
}

function continueVolumeSeed() {
  const raw = PropertiesService.getScriptProperties().getProperty('LOADTEST_CURSOR');
  if (!raw) return '沒有待續跑的壓力測試';
  const cursor = JSON.parse(raw);
  return seedVolumeTestCases(cursor.total, cursor.start);
}

function continueAiAudit() {
  const raw = PropertiesService.getScriptProperties().getProperty('AI_AUDIT_CURSOR');
  if (!raw) return '沒有待續跑的查核';
  const cursor = JSON.parse(raw);
  return runAiAuditBatch(cursor);
}

function applyAiAuditForRow(book, rowIndex) {
  const cases = book.getSheetByName(CASE_SHEET_NAME);
  const rows = cases.getDataRange().getValues();
  const row = rows[rowIndex - 1];
  if (!row || !row[0]) return null;
  const freq = nationalIdFrequency(rows.slice(1));
  const result = auditCaseRecord(row, {
    nationalIdCount: freq.get(normalizeNationalId(row[aiCol('身分證字號')])) || 0,
    referenceDate: asDate(row[aiCol('送出時間')]) || new Date()
  });
  writeAiResultToSheets(book, row[0], result);
  return result;
}

function auditCaseRecord(row, options) {
  const opts = options || {};
  const findings = [];
  const nationalId = normalizeNationalId(row[aiCol('身分證字號')]);
  const category = identityCategoryOf(row);
  const submittedAt = asDate(row[aiCol('送出時間')]) || asDate(opts.referenceDate) || new Date();

  if (!String(row[aiCol('申請人姓名')] || '').trim()) {
    findings.push(finding('repair', 'NAME', '未填申請人姓名'));
  }
  auditNationalId(nationalId, opts.nationalIdCount || 0, findings);
  auditResidency(row, findings);
  auditBirthDate(asDate(row[aiCol('出生日期')]), findings);
  auditContact(row, findings);
  auditIdentityExtras(row, category, findings);
  auditPurchase(row, submittedAt, findings);
  auditBank(row, findings);
  auditReceiptFlags(row, findings);
  auditRequiredDocuments(row, category, findings);
  addSubsidyHint(row, category, findings);

  const result = routeAiFindings(findings);
  result.status = '已查核';
  result.findings = findings;
  result.findingsText = clipFindings(findings.map(item => item.message).join('；') || '規則未發現缺件或資格問題；附件尚未做影像辨識。');
  return result;
}

function routeAiFindings(findings) {
  const has = severity => findings.some(item => item.severity === severity);
  let suggestion = '建議核准（仍須人工）';
  let confidence = '中';
  if (has('block')) suggestion = '建議駁回（仍須人工）';
  else if (has('repair')) suggestion = '建議補件';
  else if (has('review')) suggestion = '需人工複核';

  if (has('review')) confidence = '低';
  else if (has('block') && has('repair')) confidence = '中';
  else if (has('block') || has('repair')) confidence = '高';
  else confidence = '中';

  return { suggestion: suggestion, confidence: confidence };
}

const DOCUMENT_VISION_PROMPT = '你是新竹市青年 AI 補助的文件查核助理。只比對影像與申請資料是否一致，不得核准、駁回或核定補助。必須檢查：（1）身分證正反面的姓名、身分證字號、出生日期、戶籍地址是否與申請資料一致；（2）發票／官方收據的購買人、AI 工具名稱、軟體公司、購買日期、金額與幣別是否與申請資料一致；（3）切結書是否有手寫簽名，且簽名或文件上的姓名是否與申請人姓名一致。輸出 JSON：{"idCard":{"readable":true,"matches":true,"mismatches":["欄位名"]},"receipt":{"readable":true,"matches":true,"mismatches":["欄位名"]},"affidavit":{"readable":true,"hasSignature":true,"nameMatches":true,"mismatches":["欄位名"]}}。看不清楚就 readable=false。mismatches 只寫欄位名稱，不要回傳證件上的完整字號或地址。';

function claimedDocumentPayload(row) {
  return {
    fullName: String(row[aiCol('申請人姓名')] || ''),
    nationalId: normalizeNationalId(row[aiCol('身分證字號')]),
    birthDate: formatDay(row[aiCol('出生日期')]),
    householdAddress: String(row[aiCol('戶籍地址')] || ''),
    householdPostalCode: String(row[aiCol('戶籍郵遞區號')] || ''),
    isHsinchuResident: truthy(row[aiCol('設籍新竹市')]),
    toolName: String(row[aiCol('AI 工具名稱')] || ''),
    vendorName: String(row[aiCol('軟體公司名稱')] || ''),
    purchaseDate: formatDay(row[aiCol('購買日期')]),
    originalCurrency: String(row[aiCol('原始費用幣別')] || ''),
    originalAmount: row[aiCol('原始費用')],
    twdAmount: row[aiCol('換算新臺幣')],
    proxyPaid: truthy(row[aiCol('是否由他人代付')]),
    proxyName: String(row[aiCol('代付人姓名')] || '')
  };
}

function documentVisionFindings(vision) {
  const extra = [];
  if (!vision || vision.error) {
    extra.push(finding('review', 'VISION_ERROR', '影像模型未完成核對，請人工查看身分證、發票與切結書'));
    return extra;
  }
  const idCard = vision.idCard || {};
  if (idCard.readable === false) {
    extra.push(finding('repair', 'ID_IMAGE', '身分證影像無法辨識，請補清晰正面與背面'));
  } else if (idCard.matches === true) {
    extra.push(finding('info', 'ID_IMAGE_OK', '身分證影像與申請資料一致'));
  } else {
    extra.push(finding('repair', 'ID_IMAGE_MISMATCH', '身分證影像與申請資料不一致' + fieldList(idCard.mismatches)));
  }
  const receipt = vision.receipt || {};
  if (receipt.readable === false) {
    extra.push(finding('repair', 'RECEIPT_IMAGE', '發票影像無法辨識，請補清晰官方收據'));
  } else if (receipt.matches === true) {
    extra.push(finding('info', 'RECEIPT_IMAGE_OK', '發票影像與申請資料一致'));
  } else {
    extra.push(finding('repair', 'RECEIPT_IMAGE_MISMATCH', '發票影像與申請資料不一致' + fieldList(receipt.mismatches)));
  }
  const affidavit = vision.affidavit || {};
  if (affidavit.readable === false) {
    extra.push(finding('repair', 'AFFIDAVIT_IMAGE', '切結書影像無法辨識，請補清晰親簽切結書'));
  } else {
    if (affidavit.hasSignature === false) {
      extra.push(finding('repair', 'AFFIDAVIT_SIGNATURE', '切結書未見手寫簽名'));
    } else {
      extra.push(finding('info', 'AFFIDAVIT_SIGNATURE_OK', '切結書可見簽名'));
    }
    if (affidavit.nameMatches === true) {
      extra.push(finding('info', 'AFFIDAVIT_NAME_OK', '切結書姓名與申請人姓名一致'));
    } else {
      extra.push(finding('repair', 'AFFIDAVIT_NAME', '切結書姓名與申請人姓名不一致' + fieldList(affidavit.mismatches)));
    }
  }
  return extra;
}

function mergeDocumentVision(result, vision) {
  const extra = documentVisionFindings(vision);
  result.findings = (result.findings || []).concat(extra);
  const routed = routeAiFindings(result.findings);
  result.suggestion = routed.suggestion;
  result.confidence = routed.confidence;
  result.status = '已查核';
  result.findingsText = clipFindings(result.findings.map(item => item.message).join('；'));
  return result;
}

function fieldList(values) {
  if (!values || !values.length) return '';
  return '（' + values.join('、') + '）';
}

function runAiDocumentAuditPending() {
  const key = PropertiesService.getScriptProperties().getProperty('OPENAI_API_KEY');
  if (!key) return '尚未設定 OPENAI_API_KEY；請寫在指令碼屬性，不要貼進儲存格或 Git';
  const book = openBook();
  const cases = book.getSheetByName(CASE_SHEET_NAME);
  const rows = cases.getDataRange().getValues();
  const freq = nationalIdFrequency(rows.slice(1));
  let processed = 0;
  for (let index = 1; index < rows.length && processed < 8; index++) {
    const row = rows[index];
    if (!row[0] || String(row[0]).indexOf(AI_LOADTEST_PREFIX) === 0) continue;
    const idLink = String(row[aiCol('身分證正面連結')] || '');
    if (idLink.indexOf('drive.google.com') < 0) continue;
    const result = auditCaseRecord(row, {
      nationalIdCount: freq.get(normalizeNationalId(row[aiCol('身分證字號')])) || 0,
      referenceDate: asDate(row[aiCol('送出時間')]) || new Date()
    });
    const vision = requestOpenAiDocumentVision(row, key);
    mergeDocumentVision(result, vision);
    writeAiResultToSheets(book, row[0], result);
    processed += 1;
  }
  return 'GPT 文件核對完成 ' + processed + ' 筆；人工審查決定未改動';
}

function requestOpenAiDocumentVision(row, key) {
  const claimed = claimedDocumentPayload(row);
  const parts = [{ type: 'text', text: '申請資料：' + JSON.stringify(claimed) }];
  appendDriveImagePart(parts, row[aiCol('身分證正面連結')], '身分證正面');
  appendDriveImagePart(parts, row[aiCol('身分證背面連結')], '身分證背面');
  appendDriveImagePart(parts, row[aiCol('官方收據連結')], '官方收據');
  appendDriveImagePart(parts, row[aiCol('親簽切結書連結')], '親簽切結書');
  const payload = {
    model: PropertiesService.getScriptProperties().getProperty('OPENAI_MODEL') || 'gpt-4o',
    temperature: 0,
    response_format: { type: 'json_object' },
    messages: [
      { role: 'system', content: DOCUMENT_VISION_PROMPT },
      { role: 'user', content: parts }
    ]
  };
  try {
    const response = UrlFetchApp.fetch('https://api.openai.com/v1/chat/completions', {
      method: 'post',
      contentType: 'application/json',
      headers: { Authorization: 'Bearer ' + key },
      payload: JSON.stringify(payload),
      muteHttpExceptions: true
    });
    if (response.getResponseCode() >= 300) return { error: true };
    const body = JSON.parse(response.getContentText());
    return JSON.parse(body.choices[0].message.content);
  } catch (error) {
    return { error: true };
  }
}

function appendDriveImagePart(parts, url, label) {
  const fileId = driveFileIdFromUrl(url);
  if (!fileId) return;
  try {
    const blob = DriveApp.getFileById(fileId).getBlob();
    const mime = String(blob.getContentType() || '');
    if (mime.indexOf('pdf') >= 0) return;
    parts.push({ type: 'text', text: label });
    parts.push({
      type: 'image_url',
      image_url: { url: 'data:' + mime + ';base64,' + Utilities.base64Encode(blob.getBytes()) }
    });
  } catch (error) {
    // 附件讀取失敗時略過該檔，由模型標 readable=false。
  }
}

function driveFileIdFromUrl(url) {
  const text = String(url || '');
  const matched = text.match(/[-\w]{25,}/);
  return matched ? matched[0] : '';
}

function auditNationalId(nationalId, nationalIdCount, findings) {
  if (!nationalId) {
    findings.push(finding('repair', 'ID_MISSING', '未填身分證字號'));
    return;
  }
  if (isSyntheticNationalId(nationalId)) {
    findings.push(finding('info', 'ID_SYNTHETIC', '合成測試身分證字號，未做真實檢查碼檢核'));
    return;
  }
  if (!taiwanIdChecksumOk(nationalId)) {
    findings.push(finding('repair', 'ID_CHECKSUM', '身分證字號格式或檢查碼不符'));
  }
  if (nationalIdCount > 1) {
    findings.push(finding('review', 'ID_DUPLICATE', '與其他 ' + (nationalIdCount - 1) + ' 筆案件使用相同身分證字號'));
  }
}

function auditResidency(row, findings) {
  const resident = truthy(row[aiCol('設籍新竹市')]);
  const address = String(row[aiCol('戶籍地址')] || '');
  const district = String(row[aiCol('戶籍行政區')] || '').trim();
  const postal = String(row[aiCol('戶籍郵遞區號')] || '').replace(/\s/g, '');
  if (!resident) {
    findings.push(finding('block', 'RESIDENT', '申請人未設籍新竹市'));
  }
  if (address && address.indexOf('新竹市') < 0) {
    findings.push(finding('repair', 'ADDRESS', '戶籍地址未包含「新竹市」'));
  }
  if (!address.trim()) {
    findings.push(finding('repair', 'ADDRESS_MISSING', '未填戶籍地址'));
  }
  if (district && AI_HSINCHU_DISTRICTS.indexOf(district) < 0) {
    findings.push(finding('repair', 'DISTRICT', '戶籍行政區不是新竹市東區、北區或香山區'));
  }
  if (postal && postal.indexOf('300') !== 0) {
    findings.push(finding('repair', 'POSTAL', '戶籍郵遞區號不是新竹市 300 開頭'));
  }
}

function auditBirthDate(birth, findings) {
  if (!birth) {
    findings.push(finding('repair', 'BIRTH_MISSING', '未填出生日期'));
    return;
  }
  if (dayStamp(birth) < dayStamp(parseIsoDay(AI_BIRTH_MIN)) ||
      dayStamp(birth) > dayStamp(parseIsoDay(AI_BIRTH_MAX))) {
    findings.push(finding('block', 'AGE', '出生日期不在民國 74 年 4 月 3 日至 99 年 4 月 2 日'));
  }
}

function auditContact(row, findings) {
  const email = String(row[aiCol('電子郵件')] || '');
  const phone = String(row[aiCol('聯絡電話')] || '').replace(/\D/g, '');
  if (email.indexOf('@') < 0) findings.push(finding('repair', 'EMAIL', '電子郵件格式不正確'));
  if (phone.length < 8) findings.push(finding('repair', 'PHONE', '聯絡電話不足 8 碼'));
}

function auditIdentityExtras(row, category, findings) {
  if (category === 'specialTarget' && !String(row[aiCol('特定對象類別')] || '').trim()) {
    findings.push(finding('repair', 'SPECIAL_KIND', '特定對象未勾選身分類別'));
  }
  if (category === 'culturalLanguageKeeper' && !String(row[aiCol('文化語言證明類別')] || '').trim()) {
    findings.push(finding('repair', 'LANGUAGE_KIND', '文化語言保存者未勾選證照類別'));
  }
}

function auditPurchase(row, submittedAt, findings) {
  const tool = String(row[aiCol('AI 工具名稱')] || '').trim();
  const vendor = String(row[aiCol('軟體公司名稱')] || '').trim();
  const channel = String(row[aiCol('購買管道')] || '').trim();
  const original = Number(row[aiCol('原始費用')]);
  const twd = Number(row[aiCol('換算新臺幣')]);
  const currency = String(row[aiCol('原始費用幣別')] || '').trim();
  const payment = String(row[aiCol('付款方式')] || '').trim();
  const purchaseDate = asDate(row[aiCol('購買日期')]);
  const start = asDate(row[aiCol('訂閱起日')]);
  const end = asDate(row[aiCol('訂閱迄日')]);
  const plan = String(row[aiCol('繳費制度')] || '');

  if (!tool) findings.push(finding('repair', 'TOOL', '未填 AI 工具名稱'));
  if (!vendor) findings.push(finding('repair', 'VENDOR', '未填軟體公司／賣方名稱'));
  if (!truthy(row[aiCol('廠商地區符合規定')])) {
    findings.push(finding('block', 'VENDOR_REGION', '未確認該工具非中國（含港澳）廠商開發或營運'));
  }
  if (!channel) {
    findings.push(finding('repair', 'CHANNEL_MISSING', '未填購買管道'));
  } else if (!isOfficialChannel(channel)) {
    findings.push(finding('block', 'CHANNEL', '購買管道不是 AI 軟體官方網站，公開說明不予補助'));
  }
  if (truthy(row[aiCol('預付點數或代幣')])) {
    findings.push(finding('block', 'PREPAID', '預付儲值、Credit、點數、Token 或 API 額度不予補助'));
  }
  if (!currency) findings.push(finding('repair', 'CURRENCY', '未填原始費用幣別'));
  if (!Number.isFinite(original) || original <= 0) {
    findings.push(finding('repair', 'ORIGINAL_AMOUNT', '原始費用須大於 0'));
  }
  if (!Number.isFinite(twd) || twd <= 0) {
    findings.push(finding('repair', 'TWD_AMOUNT', '換算新臺幣須大於 0'));
  }
  if (!payment) findings.push(finding('repair', 'PAYMENT', '未填付款方式'));
  if (!purchaseDate) {
    findings.push(finding('repair', 'PURCHASE_DATE_MISSING', '未填購買日期'));
  } else if (dayStamp(purchaseDate) < dayStamp(parseIsoDay(AI_PURCHASE_MIN)) ||
             dayStamp(purchaseDate) > dayStamp(parseIsoDay(AI_PURCHASE_MAX))) {
    findings.push(finding('block', 'PURCHASE_WINDOW', '購買日期不在民國 115 年 4 月 2 日至 10 月 31 日'));
  }
  if (start && end && dayStamp(end) < dayStamp(start)) {
    findings.push(finding('repair', 'PERIOD', '訂閱結束日不可早於開始日'));
  }
  const months = applyWithinMonths(plan);
  if (purchaseDate && months && submittedAt &&
      dayStamp(submittedAt) > dayStamp(addMonths(purchaseDate, months))) {
    findings.push(finding('block', 'APPLY_LATE',
      planLabel(plan) + '須於購買後' + (months === 1 ? '一個月' : '兩個月') + '內提出申請'));
  }
  if (truthy(row[aiCol('是否由他人代付')])) {
    if (!String(row[aiCol('代付人姓名')] || '').trim()) {
      findings.push(finding('repair', 'PROXY_NAME', '代付時未填代付人姓名'));
    }
    if (!String(row[aiCol('代付關係')] || '').trim()) {
      findings.push(finding('repair', 'PROXY_RELATION', '代付時未填與申請人關係'));
    }
  }
}

function auditBank(row, findings) {
  if (!String(row[aiCol('匯款銀行')] || '').trim()) {
    findings.push(finding('repair', 'BANK', '未填匯款銀行'));
  }
  const masked = String(row[aiCol('帳戶末碼')] || '');
  if (!/\d{4}/.test(masked)) {
    findings.push(finding('repair', 'ACCOUNT_LAST4', '帳戶末碼不是 4 位數字'));
  }
}

function auditReceiptFlags(row, findings) {
  AI_RECEIPT_FLAGS.forEach(([header, title]) => {
    if (!truthy(row[aiCol(header)])) {
      findings.push(finding('repair', 'RECEIPT_' + header, '未確認憑證：' + title));
    }
  });
}

function auditRequiredDocuments(row, category, findings) {
  const required = AI_REQUIRED_DOCS.slice();
  if (category === 'specialTarget') {
    required.push(['specialIdentityProof', '特定對象證明連結', '特定對象身分證明']);
  }
  if (category === 'culturalLanguageKeeper') {
    required.push(['culturalLanguageCertificate', '文化語言證明連結', '本土語言證照證明']);
  }
  if (truthy(row[aiCol('是否由他人代付')])) {
    required.push(['kinshipProof', '代付親屬關係證明連結', '代付親屬關係證明']);
    required.push(['proxyPaymentAffidavit', '代付共同簽署切結書連結', '代付共同簽署切結書']);
  }
  required.forEach(([, header, title]) => {
    if (!String(row[aiCol(header)] || '').trim()) {
      findings.push(finding('repair', 'DOC_' + header, '尚未檢附：' + title));
    }
  });
}

function addSubsidyHint(row, category, findings) {
  const twd = Number(row[aiCol('換算新臺幣')]);
  if (!Number.isFinite(twd) || twd <= 0) return;
  const rate = category === 'generalYouth' ? 0.5 : 0.9;
  const cap = category === 'generalYouth' ? 3000 : 6000;
  const amount = Math.min(Math.round(twd * rate), cap);
  findings.push(finding('info', 'SUBSIDY_HINT',
    '預估補助 ' + amount + ' 元（' + identityLabel(category) + ' ' +
    Math.round(rate * 100) + '%、上限 ' + cap + ' 元），非核定金額'));
}

function redactedModelPayload(row) {
  const payload = {
    toolName: String(row[aiCol('AI 工具名稱')] || ''),
    vendorName: String(row[aiCol('軟體公司名稱')] || ''),
    originalCurrency: String(row[aiCol('原始費用幣別')] || ''),
    originalAmount: row[aiCol('原始費用')],
    twdAmount: row[aiCol('換算新臺幣')],
    purchaseDate: formatDay(row[aiCol('購買日期')]),
    receiptFlags: {}
  };
  AI_RECEIPT_FLAGS.forEach(([header]) => {
    payload.receiptFlags[header] = truthy(row[aiCol(header)]);
  });
  return payload;
}

function taiwanIdChecksumOk(id) {
  const text = String(id || '').trim().toUpperCase();
  if (!/^[A-Z][12]\d{8}$/.test(text)) return false;
  const code = AI_TAIWAN_ID_LETTERS[text[0]];
  if (!code) return false;
  const digits = [Math.floor(code / 10), code % 10].concat(text.slice(1).split('').map(Number));
  const weights = [1, 9, 8, 7, 6, 5, 4, 3, 2, 1, 1];
  const sum = digits.reduce((total, digit, index) => total + digit * weights[index], 0);
  return sum % 10 === 0;
}

function makeTaiwanId(serial) {
  const body = '1' + String(Math.abs(serial) % 10000000).padStart(7, '0');
  for (let check = 0; check <= 9; check++) {
    const id = 'A' + body + check;
    if (taiwanIdChecksumOk(id)) return id;
  }
  throw new Error('無法產生測試身分證字號');
}

const AI_VOLUME_SCENARIOS = [
  'pass', 'passSpecial', 'passCultural', 'passMonthly', 'passProxy',
  'passXiangshan', 'passSyntheticId', 'passHighAmount',
  'notResident', 'prepaid', 'aggregator', 'reseller', 'vendorRegion',
  'ageTooOld', 'ageTooYoung', 'purchaseTooEarly', 'purchaseTooLate', 'applyLateMonthly',
  'badId', 'missingId', 'missingName', 'missingDocs', 'missingReceipt',
  'specialMissing', 'culturalMissing', 'proxyMissing', 'proxyMissingName',
  'missingBank', 'badContact', 'zeroAmount', 'periodInverted',
  'missingChannel', 'missingTool', 'addressInconsistent', 'badDistrict',
  'badPostal', 'specialNoKind', 'missingBirth', 'missingPassbook',
  'duplicate'
];

function volumeScenario(index) {
  return AI_VOLUME_SCENARIOS[index % AI_VOLUME_SCENARIOS.length];
}

function makeInvalidTaiwanId(serial) {
  const valid = makeTaiwanId(serial);
  const last = Number(valid.slice(-1));
  return valid.slice(0, -1) + ((last + 1) % 10);
}

function plannedNationalId(index) {
  const scenario = volumeScenario(index);
  if (scenario === 'missingId') return '';
  if (scenario === 'passSyntheticId') return AI_SYNTHETIC_ID;
  if (scenario === 'badId') return makeInvalidTaiwanId(index);
  if (scenario === 'duplicate') return makeTaiwanId(9999999);
  return makeTaiwanId(index);
}

function defaultPassLinks(caseId) {
  const links = {};
  DOCUMENT_COLUMN_TYPES.forEach(type => {
    links[type] = 'https://example.invalid/loadtest/' + caseId + '/' + type;
  });
  links.specialIdentityProof = '';
  links.culturalLanguageCertificate = '';
  links.kinshipProof = '';
  links.proxyPaymentAffidavit = '';
  return links;
}

function applyVolumeScenario(rec, scenario) {
  if (scenario === 'passSpecial') {
    rec.identity = 'specialTarget';
    rec.specialKinds = 'lowIncome';
    rec.links.specialIdentityProof = rec.links.idFront.replace('/idFront', '/specialIdentityProof');
  } else if (scenario === 'passCultural') {
    rec.identity = 'culturalLanguageKeeper';
    rec.culturalKinds = 'indigenousLanguage';
    rec.links.culturalLanguageCertificate = rec.links.idFront.replace('/idFront', '/culturalLanguageCertificate');
  } else if (scenario === 'passMonthly') {
    rec.plan = 'monthly';
    rec.purchaseDate = '2026-08-20';
    rec.start = '2026-08-20';
    rec.end = '2026-09-19';
  } else if (scenario === 'passProxy') {
    rec.proxy = true;
    rec.proxyName = '合成代付人';
    rec.proxyRelation = '父母';
    rec.links.kinshipProof = rec.links.idFront.replace('/idFront', '/kinshipProof');
    rec.links.proxyPaymentAffidavit = rec.links.idFront.replace('/idFront', '/proxyPaymentAffidavit');
  } else if (scenario === 'passXiangshan') {
    rec.district = '香山區';
    rec.address = '新竹市香山區測試路 1 號';
  } else if (scenario === 'passHighAmount') {
    rec.original = 400;
    rec.twd = 12000;
  } else if (scenario === 'notResident') {
    rec.resident = false;
    rec.district = '竹北市';
    rec.address = '新竹縣竹北市測試路 1 號';
    rec.postal = '302';
  } else if (scenario === 'prepaid') {
    rec.prepaid = true;
  } else if (scenario === 'aggregator') {
    rec.channel = 'aggregator';
  } else if (scenario === 'reseller') {
    rec.channel = 'reseller';
  } else if (scenario === 'vendorRegion') {
    rec.vendorOk = false;
  } else if (scenario === 'ageTooOld') {
    rec.birth = '1970-01-01';
  } else if (scenario === 'ageTooYoung') {
    rec.birth = '2012-01-01';
  } else if (scenario === 'purchaseTooEarly') {
    rec.purchaseDate = '2026-03-01';
    rec.start = '2026-03-01';
  } else if (scenario === 'purchaseTooLate') {
    rec.purchaseDate = '2026-11-01';
    rec.start = '2026-11-01';
    rec.end = '2027-10-31';
  } else if (scenario === 'applyLateMonthly') {
    rec.plan = 'monthly';
    rec.purchaseDate = '2026-06-01';
    rec.start = '2026-06-01';
    rec.end = '2026-06-30';
  } else if (scenario === 'missingId') {
    rec.nationalId = '';
  } else if (scenario === 'missingName') {
    rec.name = '';
  } else if (scenario === 'missingDocs') {
    DOCUMENT_COLUMN_TYPES.forEach(type => { rec.links[type] = ''; });
  } else if (scenario === 'missingReceipt') {
    rec.receipts = [false, false, false, false, false, false, false, false];
  } else if (scenario === 'specialMissing') {
    rec.identity = 'specialTarget';
    rec.specialKinds = 'lowIncome';
  } else if (scenario === 'culturalMissing') {
    rec.identity = 'culturalLanguageKeeper';
    rec.culturalKinds = 'taiwanese';
  } else if (scenario === 'proxyMissing') {
    rec.proxy = true;
    rec.proxyName = '合成代付人';
    rec.proxyRelation = '父母';
  } else if (scenario === 'proxyMissingName') {
    rec.proxy = true;
    rec.proxyName = '';
    rec.proxyRelation = '';
    rec.links.kinshipProof = rec.links.idFront.replace('/idFront', '/kinshipProof');
    rec.links.proxyPaymentAffidavit = rec.links.idFront.replace('/idFront', '/proxyPaymentAffidavit');
  } else if (scenario === 'missingBank') {
    rec.bank = '';
    rec.last4 = '';
  } else if (scenario === 'badContact') {
    rec.email = 'not-an-email';
    rec.phone = '12';
  } else if (scenario === 'zeroAmount') {
    rec.original = 0;
    rec.twd = 0;
  } else if (scenario === 'periodInverted') {
    rec.start = '2026-09-01';
    rec.end = '2026-08-01';
  } else if (scenario === 'missingChannel') {
    rec.channel = '';
  } else if (scenario === 'missingTool') {
    rec.tool = '';
    rec.vendor = '';
  } else if (scenario === 'addressInconsistent') {
    rec.resident = true;
    rec.district = '東區';
    rec.address = '新竹縣竹北市測試路 1 號';
  } else if (scenario === 'badDistrict') {
    rec.district = '竹北市';
  } else if (scenario === 'badPostal') {
    rec.postal = '302';
  } else if (scenario === 'specialNoKind') {
    rec.identity = 'specialTarget';
    rec.specialKinds = '';
    rec.links.specialIdentityProof = rec.links.idFront.replace('/idFront', '/specialIdentityProof');
  } else if (scenario === 'missingBirth') {
    rec.birth = '';
  } else if (scenario === 'missingPassbook') {
    rec.links.passbookCover = '';
  }
}

function buildSyntheticCaseRow(index, extras) {
  const extra = extras || {};
  const scenario = extra.scenario || volumeScenario(index);
  const caseId = extra.caseId || (AI_LOADTEST_PREFIX + String(index + 1).padStart(6, '0'));
  const rec = {
    caseId: caseId,
    scenario: scenario,
    submittedAt: extra.submittedAt || parseIsoDay('2026-09-01'),
    name: extra.fullName || ('合成申請人-' + String(index + 1).padStart(5, '0')),
    nationalId: extra.nationalId !== undefined ? extra.nationalId : plannedNationalId(index),
    birth: '1998-06-15',
    phone: '0912345678',
    email: 'loadtest@example.invalid',
    resident: true,
    identity: 'generalYouth',
    specialKinds: '',
    culturalKinds: '',
    postal: '300',
    district: '東區',
    address: '新竹市東區測試路 1 號',
    bank: '台灣銀行',
    last4: '1234',
    plan: 'yearly',
    periods: 1,
    tool: 'ChatGPT Plus',
    vendor: 'OpenAI',
    vendorOk: true,
    channel: 'officialWebsite',
    purchaseDate: '2026-08-01',
    start: '2026-08-01',
    end: '2027-07-31',
    currency: 'USD',
    original: 20,
    twd: 2000,
    payment: '信用卡',
    prepaid: false,
    proxy: false,
    proxyName: '',
    proxyRelation: '',
    receipts: [true, true, true, true, true, true, true, true],
    links: defaultPassLinks(caseId)
  };
  applyVolumeScenario(rec, scenario);
  if (extra.fullName) rec.name = extra.fullName;
  if (extra.nationalId !== undefined) rec.nationalId = extra.nationalId;
  const row = [
    rec.caseId, rec.submittedAt, '待審', '',
    rec.name, rec.nationalId, rec.birth ? parseIsoDay(rec.birth) : '',
    rec.phone, rec.email, rec.resident, rec.identity, rec.specialKinds,
    rec.culturalKinds, rec.postal, rec.district, rec.address,
    true, '', '', '', '',
    rec.bank, rec.last4, rec.plan, rec.periods, 'general',
    rec.tool, rec.vendor, rec.vendorOk, rec.channel,
    parseIsoDay(rec.purchaseDate), parseIsoDay(rec.start), parseIsoDay(rec.end),
    rec.currency, rec.original, rec.twd, rec.payment, rec.prepaid,
    rec.proxy, rec.proxyName, rec.proxyRelation,
    rec.receipts[0], rec.receipts[1], rec.receipts[2], rec.receipts[3],
    rec.receipts[4], rec.receipts[5], rec.receipts[6], rec.receipts[7],
    ...DOCUMENT_COLUMN_TYPES.map(type => rec.links[type] || ''),
    '尚未查核', '', '', '', '待審', '合成情境：' + scenario, '', rec.caseId.slice(-6)
  ];
  if (row.length !== CASE_HEADERS.length) throw new Error('合成案件欄位數不一致');
  return row.map(sheetText);
}

function seedVolumeTestCases(total, start) {
  const book = openBook();
  const cases = book.getSheetByName(CASE_SHEET_NAME);
  assertCaseHeaders(cases);
  assertDisplaySheets(book);
  const from = Number(start) || 0;
  const goal = Number(total) || 1000;
  const until = Math.min(from + AI_SEED_BATCH, goal);
  const freq = {};
  for (let i = 0; i < goal; i++) {
    const id = plannedNationalId(i);
    freq[id] = (freq[id] || 0) + 1;
  }
  const blocks = [[], [], [], [], [], []];
  for (let i = from; i < until; i++) {
    const row = buildSyntheticCaseRow(i);
    const result = auditCaseRecord(row, {
      nationalIdCount: freq[normalizeNationalId(row[aiCol('身分證字號')])] || 0,
      referenceDate: asDate(row[aiCol('送出時間')])
    });
    applyResultToRow(row, result);
    const display = displayRowsFor(row);
    blocks[0].push(row);
    display.forEach((item, index) => blocks[index + 1].push(item));
  }
  appendRows(cases, blocks[0]);
  DISPLAY_SHEETS.forEach((name, index) => appendRows(book.getSheetByName(name), blocks[index + 1]));
  if (until < goal) {
    PropertiesService.getScriptProperties().setProperty(
      'LOADTEST_CURSOR', JSON.stringify({ start: until, total: goal })
    );
    scheduleContinue('continueVolumeSeed');
    return '已寫入 ' + until + ' / ' + goal + ' 筆合成案件，將自動續跑';
  }
  PropertiesService.getScriptProperties().deleteProperty('LOADTEST_CURSOR');
  return '已寫入 ' + goal + ' 筆合成壓力測試案件；AI 四欄已填，人工審查仍為待審';
}

function removeLoadTestCases() {
  const book = openBook();
  const names = [CASE_SHEET_NAME].concat(DISPLAY_SHEETS);
  let removed = 0;
  names.forEach(name => {
    const sheet = book.getSheetByName(name);
    const values = sheet.getDataRange().getValues();
    if (!values.length) return;
    const kept = [values[0]].concat(values.slice(1).filter(row =>
      String(row[0] || '').indexOf(AI_LOADTEST_PREFIX) !== 0));
    removed = Math.max(removed, values.length - kept.length);
    sheet.clearContents();
    if (kept.length) sheet.getRange(1, 1, kept.length, kept[0].length).setValues(kept);
  });
  return '已清除 ' + removed + ' 筆合成壓力測試案件';
}

function runAiAuditBatch(options) {
  const opts = options || {};
  const book = openBook();
  const cases = book.getSheetByName(CASE_SHEET_NAME);
  const rows = cases.getDataRange().getValues();
  const freq = nationalIdFrequency(rows.slice(1));
  const statusIndex = aiCol('AI 查核狀態');
  const start = Number(opts.start) || 1;
  let processed = 0;
  let index = start;
  for (; index < rows.length && processed < (opts.limit || AI_BATCH_LIMIT); index++) {
    const row = rows[index];
    if (!row[0]) continue;
    if (!opts.force && String(row[statusIndex] || '') === '已查核') continue;
    const result = auditCaseRecord(row, {
      nationalIdCount: freq.get(normalizeNationalId(row[aiCol('身分證字號')])) || 0,
      referenceDate: asDate(row[aiCol('送出時間')]) || new Date()
    });
    applyResultToRow(row, result);
    writeAiResultToSheets(book, row[0], result);
    processed += 1;
  }
  if (index < rows.length) {
    PropertiesService.getScriptProperties().setProperty(
      'AI_AUDIT_CURSOR', JSON.stringify({
        force: !!opts.force, limit: opts.limit || AI_BATCH_LIMIT, start: index
      })
    );
    scheduleContinue('continueAiAudit');
    return '本批查核 ' + processed + ' 筆，將自動續跑';
  }
  PropertiesService.getScriptProperties().deleteProperty('AI_AUDIT_CURSOR');
  return '本批查核 ' + processed + ' 筆，已完成';
}

function writeAiResultToSheets(book, caseId, result) {
  const payload = [result.status, result.suggestion, result.findingsText, result.confidence];
  const raw = book.getSheetByName(CASE_SHEET_NAME);
  const rawRow = findCaseRow(raw, caseId);
  const start = aiCol('AI 查核狀態') + 1;
  if (rawRow) {
    payload.forEach((value, offset) => raw.getRange(rawRow, start + offset).setValue(value));
  }
  const display = book.getSheetByName('AI 查核');
  const displayRow = findCaseRow(display, caseId);
  if (displayRow) {
    payload.forEach((value, offset) => display.getRange(displayRow, 2 + offset).setValue(value));
  }
}

function applyResultToRow(row, result) {
  row[aiCol('AI 查核狀態')] = result.status;
  row[aiCol('AI 查核建議')] = result.suggestion;
  row[aiCol('AI 疑點')] = result.findingsText;
  row[aiCol('AI 信心程度')] = result.confidence;
}

function appendRows(sheet, rows) {
  if (!rows.length) return;
  const start = sheet.getLastRow() + 1;
  const width = rows[0].length;
  if (typeof sheet.getRange(start, 1, rows.length, width).setValues === 'function') {
    sheet.getRange(start, 1, rows.length, width).setValues(rows);
    return;
  }
  rows.forEach(row => sheet.appendRow(row));
}

function scheduleContinue(handlerName) {
  if (typeof ScriptApp === 'undefined') return;
  ScriptApp.getProjectTriggers().forEach(trigger => {
    if (trigger.getHandlerFunction() === handlerName) ScriptApp.deleteTrigger(trigger);
  });
  ScriptApp.newTrigger(handlerName).timeBased().after(20000).create();
}

function nationalIdFrequency(dataRows) {
  const freq = new Map();
  const index = aiCol('身分證字號');
  dataRows.forEach(row => {
    const id = normalizeNationalId(row[index]);
    if (!id || isSyntheticNationalId(id)) return;
    freq.set(id, (freq.get(id) || 0) + 1);
  });
  return freq;
}

function identityCategoryOf(row) {
  const raw = String(row[aiCol('身分類別')] || '');
  if (raw === 'specialTarget' || raw === '特定對象') return 'specialTarget';
  if (raw === 'culturalLanguageKeeper' || raw === '文化語言保存者') return 'culturalLanguageKeeper';
  return 'generalYouth';
}

function identityLabel(category) {
  return {
    generalYouth: '一般青年',
    specialTarget: '特定對象',
    culturalLanguageKeeper: '文化語言保存者'
  }[category] || '一般青年';
}

function isOfficialChannel(value) {
  const text = String(value || '');
  return text === 'officialWebsite' || text.indexOf('官方網站') >= 0;
}

function applyWithinMonths(plan) {
  const text = String(plan || '');
  if (text === 'monthly' || text.indexOf('月費') >= 0) return 1;
  if (text === 'yearly' || text.indexOf('年費') >= 0) return 2;
  return 0;
}

function planLabel(plan) {
  return applyWithinMonths(plan) === 1 ? '月費制' : '年費制';
}

function isSyntheticNationalId(id) {
  return id === AI_SYNTHETIC_ID || id.indexOf('TEST-') === 0;
}

function normalizeNationalId(value) {
  return String(value || '').trim().toUpperCase();
}

function truthy(value) {
  return value === true || value === 1 || value === 'TRUE' || value === 'true' || value === '是';
}

function asDate(value) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
  if (typeof value === 'number' && Number.isFinite(value)) {
    return new Date(Math.round((value - 25569) * 86400 * 1000));
  }
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}/.test(value)) {
    return parseIsoDay(value.slice(0, 10));
  }
  return null;
}

function parseIsoDay(text) {
  const parts = String(text).split('-').map(Number);
  if (parts.length !== 3 || parts.some(part => !Number.isFinite(part))) return null;
  return new Date(parts[0], parts[1] - 1, parts[2], 12, 0, 0);
}

function formatDay(value) {
  const date = asDate(value);
  if (!date) return '';
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return date.getFullYear() + '-' + month + '-' + day;
}

function dayStamp(date) {
  return Date.UTC(date.getFullYear(), date.getMonth(), date.getDate());
}

function addMonths(date, months) {
  return new Date(date.getFullYear(), date.getMonth() + months, date.getDate(), 12, 0, 0);
}

function finding(severity, code, message) {
  return { severity: severity, code: code, message: message };
}

function clipFindings(text) {
  return text.length <= AI_FINDINGS_MAX ? text : text.slice(0, AI_FINDINGS_MAX);
}

function aiCol(name) {
  const index = CASE_HEADERS.indexOf(name);
  if (index < 0) throw new Error('找不到欄位：' + name);
  return index;
}

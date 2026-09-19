// 貼到「梅竹通」試算表的繫結 Apps Script 專案；須與 Schema.gs 一起使用。
// 尚未部署前，這份程式不會接收手機送件。
const CASE_SHEET_NAME = '申請案件';
const TOKEN_SHEET_NAME = '案件憑證';
const DECISIONS = ['待審', '需補件', '核准', '駁回'];
const DOCUMENT_BYTES_MAX = 10 * 1024 * 1024;
const TOTAL_DOCUMENT_BYTES_MAX = 25 * 1024 * 1024;

function setupService() {
  const book = SpreadsheetApp.getActiveSpreadsheet();
  if (!book) throw new Error('請從梅竹通試算表開啟 Apps Script 後執行');
  const cases = book.getSheetByName(CASE_SHEET_NAME);
  if (!cases) throw new Error('找不到申請案件工作表');
  assertCaseHeaders(cases);
  const tokenSheet = book.getSheetByName(TOKEN_SHEET_NAME) || book.insertSheet(TOKEN_SHEET_NAME);
  if (tokenSheet.getLastRow() === 0) {
    tokenSheet.appendRow(['送件識別碼', '案件編號', '查詢憑證雜湊']);
  }
  tokenSheet.hideSheet();
  const decisionIndex = CASE_HEADERS.indexOf('人工審查決定') + 1;
  const rule = SpreadsheetApp.newDataValidation().requireValueInList(DECISIONS, true).setAllowInvalid(false).build();
  cases.getRange(2, decisionIndex, Math.max(cases.getMaxRows() - 1, 1), 1).setDataValidation(rule);
  const properties = PropertiesService.getScriptProperties();
  properties.setProperty('SPREADSHEET_ID', book.getId());
  if (!properties.getProperty('TOKEN_SECRET')) {
    properties.setProperty('TOKEN_SECRET', Utilities.getUuid() + Utilities.getUuid());
  }
  if (!properties.getProperty('ATTACHMENT_FOLDER_ID')) {
    properties.setProperty('ATTACHMENT_FOLDER_ID', DriveApp.createFolder('梅竹通申請附件').getId());
  }
  // CLIENT_KEY 必須由擁有者在「專案設定 > 指令碼屬性」自行填入。
  return '欄位、人工審查選單與附件資料夾已備妥；尚未部署收件網址。';
}

function doPost(e) {
  try {
    const body = JSON.parse(e.postData.contents);
    const expectedKey = PropertiesService.getScriptProperties().getProperty('CLIENT_KEY');
    if (!expectedKey || body.clientKey !== expectedKey) throw new Error('收件設定未完成或憑證錯誤');
    if (body.action === 'submit') return jsonResponse(submitApplication(body));
    if (body.action === 'status') return jsonResponse(readApplicationStatus(body));
    throw new Error('不支援的操作');
  } catch (error) {
    return jsonResponse({ ok: false, error: String(error.message || error) });
  }
}

function submitApplication(body) {
  if (!body.clientSubmissionId || !body.applicant || !body.purchase || !body.form) {
    throw new Error('申請資料不完整');
  }
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    const book = openBook();
    const cases = book.getSheetByName(CASE_SHEET_NAME);
    const tokens = book.getSheetByName(TOKEN_SHEET_NAME);
    assertCaseHeaders(cases);
    const previous = findTokenRow(tokens, body.clientSubmissionId);
    if (previous) {
      // 同一次送件重試回傳同一筆案件，避免斷線後新增重複案件。
      return {
        ok: true, case: { caseId: previous[1], status: 'submitted' },
        accessToken: accessTokenFor(body.clientSubmissionId, previous[1])
      };
    }
    const caseId = 'MZT-' + Utilities.getUuid().slice(0, 12).toUpperCase();
    const accessToken = accessTokenFor(body.clientSubmissionId, caseId);
    const folder = DriveApp.getFolderById(PropertiesService.getScriptProperties().getProperty('ATTACHMENT_FOLDER_ID'));
    const createdFiles = [];
    try {
      const links = saveDocuments(body.documents || [], folder, caseId, createdFiles);
      const row = submissionToRow(body, {
        caseId: caseId,
        submittedAt: new Date(),
        documentLinks: links,
        accessCode: caseId.slice(-6)
      });
      tokens.appendRow([sheetText(body.clientSubmissionId), caseId, tokenHash(accessToken)]);
      try {
        cases.appendRow(row);
      } catch (error) {
        tokens.deleteRow(tokens.getLastRow());
        throw error;
      }
      return { ok: true, case: { caseId: caseId, status: 'submitted' }, accessToken: accessToken };
    } catch (error) {
      // 只回收本次失敗操作剛建立的檔案，可由雲端硬碟垃圾桶復原。
      createdFiles.forEach(file => file.setTrashed(true));
      throw error;
    }
  } finally {
    lock.releaseLock();
  }
}

function saveDocuments(documents, folder, caseId, createdFiles) {
  if (!Array.isArray(documents)) throw new Error('附件格式錯誤');
  let total = 0;
  const links = {};
  for (const document of documents) {
    if (!DOCUMENT_COLUMN_TYPES.includes(document.type) || links[document.type]) {
      throw new Error('附件類別不正確或重複');
    }
    if (!['image/jpeg', 'image/png', 'application/pdf'].includes(document.contentType)) {
      throw new Error('附件格式只支援 JPEG、PNG 或 PDF');
    }
    if (!/^[A-Za-z0-9+/]+={0,2}$/.test(document.base64 || '')) throw new Error('附件內容不是有效的 Base64');
    const bytes = Utilities.base64Decode(document.base64);
    total += bytes.length;
    if (!bytes.length || bytes.length > DOCUMENT_BYTES_MAX || total > TOTAL_DOCUMENT_BYTES_MAX) {
      throw new Error('附件超過單檔 10 MB 或單次送件 25 MB 上限');
    }
    const ext = { 'image/jpeg': 'jpg', 'image/png': 'png', 'application/pdf': 'pdf' }[document.contentType];
    const blob = Utilities.newBlob(bytes, document.contentType, caseId + '-' + document.type + '.' + ext);
    const file = folder.createFile(blob);
    createdFiles.push(file);
    links[document.type] = file.getUrl();
  }
  return links;
}

function readApplicationStatus(body) {
  if (!body.caseId || !body.accessToken) throw new Error('缺少案件查詢資料');
  const book = openBook();
  const tokens = book.getSheetByName(TOKEN_SHEET_NAME);
  const tokenData = tokens.getDataRange().getValues();
  const found = tokenData.slice(1).some(row => row[1] === body.caseId && row[2] === tokenHash(body.accessToken));
  if (!found) throw new Error('案件不存在或查詢憑證錯誤');
  const cases = book.getSheetByName(CASE_SHEET_NAME);
  const rows = cases.getDataRange().getValues();
  const record = rows.slice(1).find(row => row[0] === body.caseId);
  if (!record) throw new Error('找不到案件');
  const status = {
    '待審': 'submitted', '審查中': 'under_manual_review',
    '需補件': 'needs_documents', '已核准': 'approved', '已駁回': 'rejected'
  }[record[2]];
  if (!status) throw new Error('試算表審查狀態不正確');
  return { ok: true, caseId: body.caseId, status: status, statusNote: String(record[3] || '') };
}

function onEdit(e) {
  if (!e || !e.range || e.range.getSheet().getName() !== CASE_SHEET_NAME || e.range.getRow() < 2) return;
  const sheet = e.range.getSheet();
  const decisionColumn = CASE_HEADERS.indexOf('人工審查決定') + 1;
  if (e.range.getColumn() !== decisionColumn || e.range.getNumRows() !== 1) return;
  const decision = e.range.getValue();
  if (!DECISIONS.includes(decision)) return;
  const status = { '待審': '待審', '需補件': '需補件', '核准': '已核准', '駁回': '已駁回' }[decision];
  sheet.getRange(e.range.getRow(), CASE_HEADERS.indexOf('審查狀態') + 1).setValue(status);
  sheet.getRange(e.range.getRow(), CASE_HEADERS.indexOf('決定時間') + 1)
    .setValue(decision === '待審' ? '' : new Date());
}

function assertCaseHeaders(sheet) {
  const actual = sheet.getRange(1, 1, 1, CASE_HEADERS.length).getValues()[0];
  if (actual.some((value, index) => value !== CASE_HEADERS[index])) {
    throw new Error('試算表標題與程式不一致；已停止寫入以免資料錯欄');
  }
}

function openBook() {
  const id = PropertiesService.getScriptProperties().getProperty('SPREADSHEET_ID');
  if (!id) throw new Error('尚未執行 setupService');
  return SpreadsheetApp.openById(id);
}

function findTokenRow(sheet, submissionId) {
  if (sheet.getLastRow() < 2) return null;
  return sheet.getRange(2, 1, sheet.getLastRow() - 1, 3).getValues()
    .find(row => row[0] === submissionId) || null;
}

function tokenHash(token) {
  return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, token)
    .map(byte => ('0' + (byte & 255).toString(16)).slice(-2)).join('');
}

function accessTokenFor(submissionId, caseId) {
  const secret = PropertiesService.getScriptProperties().getProperty('TOKEN_SECRET');
  if (!secret) throw new Error('查詢憑證尚未設定');
  return Utilities.computeHmacSha256Signature(submissionId + ':' + caseId, secret)
    .map(byte => ('0' + (byte & 255).toString(16)).slice(-2)).join('');
}

function jsonResponse(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
}

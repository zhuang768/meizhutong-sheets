// 貼到「梅竹通」試算表的繫結 Apps Script 專案；須與 Schema.gs 一起使用。
// 部署後仍須設定 CLIENT_KEY；無憑證或憑證錯誤的請求會被拒絕。
const CASE_SHEET_NAME = '_原始資料_69欄';
const TOKEN_SHEET_NAME = '案件憑證';
const DISPLAY_SHEETS = ['申請案件', '申請資料', '附件', 'AI 查核', '人工審查'];
const DECISIONS = ['待審', '需補件', '核准', '駁回'];
const DOCUMENT_BYTES_MAX = 10 * 1024 * 1024;
const TOTAL_DOCUMENT_BYTES_MAX = 25 * 1024 * 1024;

function setupService() {
  const properties = PropertiesService.getScriptProperties();
  const book = SpreadsheetApp.getActiveSpreadsheet() ||
    (properties.getProperty('SPREADSHEET_ID') ? SpreadsheetApp.openById(properties.getProperty('SPREADSHEET_ID')) : null);
  if (!book) throw new Error('請從梅竹通試算表開啟 Apps Script 後執行');
  const cases = book.getSheetByName(CASE_SHEET_NAME);
  if (!cases) throw new Error('找不到原始資料工作表（_原始資料_69欄）');
  assertCaseHeaders(cases);
  if (typeof ensureAiDisplaySheet === 'function') ensureAiDisplaySheet();
  if (typeof ensureReviewSheet === 'function') ensureReviewSheet(book);
  assertDisplaySheets(book);
  const tokenSheet = book.getSheetByName(TOKEN_SHEET_NAME) || book.insertSheet(TOKEN_SHEET_NAME);
  if (tokenSheet.getLastRow() === 0) {
    tokenSheet.appendRow(['送件識別碼', '案件編號', '查詢憑證雜湊']);
  }
  tokenSheet.hideSheet();
  properties.setProperty('SPREADSHEET_ID', book.getId());
  if (!properties.getProperty('TOKEN_SECRET')) {
    properties.setProperty('TOKEN_SECRET', Utilities.getUuid() + Utilities.getUuid());
  }
  if (!properties.getProperty('ATTACHMENT_FOLDER_ID')) {
    const existing = DriveApp.getFoldersByName('梅竹通申請附件');
    properties.setProperty(
      'ATTACHMENT_FOLDER_ID',
      existing.hasNext() ? existing.next().getId() : DriveApp.createFolder('梅竹通申請附件').getId()
    );
  }
  if (typeof installSpreadsheetMenuTrigger === 'function') installSpreadsheetMenuTrigger();
  if (typeof onOpen === 'function') {
    try { onOpen({ source: book }); } catch (ignore) {}
  }
  return '欄位、人工審查選單、AI 查核選單、淡色標示與附件資料夾已備妥；CLIENT_KEY 仍須另行設定。';
}

function installSpreadsheetMenuTrigger() {
  const id = PropertiesService.getScriptProperties().getProperty('SPREADSHEET_ID');
  if (!id) throw new Error('尚未設定 SPREADSHEET_ID');
  ScriptApp.getProjectTriggers().forEach(trigger => {
    const name = trigger.getHandlerFunction();
    if (name === 'onOpen' || name === 'applySpreadsheetPresentationOnOpen') ScriptApp.deleteTrigger(trigger);
  });
  ScriptApp.newTrigger('onOpen').forSpreadsheet(id).onOpen().create();
  ScriptApp.newTrigger('applySpreadsheetPresentationOnOpen').forSpreadsheet(id).onOpen().create();
  return '已安裝試算表「梅竹通 AI」選單與自動上色；請重新整理試算表';
}

function applyClientKeyOnce(key) {
  const trimmed = String(key || '').trim();
  if (!trimmed) throw new Error('CLIENT_KEY 空白');
  PropertiesService.getScriptProperties().setProperty('CLIENT_KEY', trimmed);
  return 'CLIENT_KEY 已設定';
}

function applyOpenAiKeyOnce(key) {
  const trimmed = String(key || '').trim();
  if (!trimmed) throw new Error('OPENAI_API_KEY 空白');
  PropertiesService.getScriptProperties().setProperty('OPENAI_API_KEY', trimmed);
  return 'OPENAI_API_KEY 已設定；送件後會自動核對身分證、發票與切結書影像';
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
    ensureAiDisplaySheet(book);
    assertDisplaySheets(book);
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
      const appended = [];
      try {
        cases.appendRow(row);
        appended.push(cases);
        const displayRows = displayRowsFor(row);
        DISPLAY_SHEETS.forEach((name, index) => {
          const sheet = book.getSheetByName(name);
          sheet.appendRow(displayRows[index]);
          appended.push(sheet);
        });
        tokens.appendRow([sheetText(body.clientSubmissionId), caseId, tokenHash(accessToken)]);
      } catch (error) {
        // 只回復本次新增的列；不碰既有案件。
        appended.reverse().forEach(sheet => {
          const last = sheet.getLastRow();
          if (last > 1 && sheet.getRange(last, 1).getValue() === caseId) sheet.deleteRow(last);
        });
        throw error;
      }
      try {
        if (typeof applyAiAuditForRow === 'function') applyAiAuditForRow(book, cases.getLastRow());
      } catch (auditError) {
        const message = String(auditError.message || auditError);
        const rawRow = findCaseRow(cases, caseId);
        if (rawRow) {
          cases.getRange(rawRow, CASE_HEADERS.indexOf('AI 查核狀態') + 1).setValue('查核失敗');
          cases.getRange(rawRow, CASE_HEADERS.indexOf('AI 疑點') + 1).setValue(message);
        }
        const aiDisplay = book.getSheetByName('AI 查核');
        const aiRow = findCaseRow(aiDisplay, caseId);
        if (aiRow) {
          aiDisplay.getRange(aiRow, 2).setValue('查核失敗');
          aiDisplay.getRange(aiRow, 4).setValue(message);
        }
      }
      // 先回覆 App，避免 GPT 看圖或整表上色把 Web App 拖到逾時，青年端會以為送不出。
      return { ok: true, case: { caseId: caseId, status: 'submitted' }, accessToken: accessToken };
    } catch (error) {
      // 只回收本次失敗操作剛建立的檔案，可由雲端硬碟垃圾桶復原。
      createdFiles.forEach(file => file.setTrashed(true));
      throw error;
    }
  } finally {
    try { lock.releaseLock(); } catch (ignore) {}
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

function applyManualDecision(book, caseId, decision) {
  if (!DECISIONS.includes(decision)) return false;
  const sheet = book.getSheetByName(CASE_SHEET_NAME);
  const summary = book.getSheetByName('申請案件');
  const review = book.getSheetByName('人工審查');
  const rawRow = findCaseRow(sheet, caseId);
  const summaryRow = findCaseRow(summary, caseId);
  const reviewRow = findCaseRow(review, caseId);
  if (!caseId || !rawRow || !summaryRow || !reviewRow) return false;
  const status = { '待審': '待審', '需補件': '需補件', '核准': '已核准', '駁回': '已駁回' }[decision];
  const when = decision === '待審' ? '' : new Date();
  sheet.getRange(rawRow, 66).setValue(decision);
  sheet.getRange(rawRow, 3).setValue(status);
  sheet.getRange(rawRow, 68).setValue(when);
  summary.getRange(summaryRow, 6).setValue(status);
  review.getRange(reviewRow, 2).setValue(decision);
  review.getRange(reviewRow, 4).setValue(when);
  const reviewCell = review.getRange(reviewRow, 2);
  if (typeof reviewCell.setBackground === 'function') reviewCell.setBackground(colorForDecision(decision) || null);
  const summaryCell = summary.getRange(summaryRow, 6);
  if (typeof summaryCell.setBackground === 'function') summaryCell.setBackground(colorForDecision(status) || null);
  return true;
}

function applyHumanDecisionsByAiColor(color, decision, label) {
  const book = openBook();
  const cases = book.getSheetByName(CASE_SHEET_NAME);
  const ids = collectPendingAiDecisionCaseIds(cases.getDataRange().getValues(), color, AI_BATCH_LIMIT);
  if (!ids.length) return '沒有「' + label + '」且仍為待審的案件';
  if (!confirmHumanBatch(
    '批次人工決定',
    '將 ' + ids.length + ' 筆「' + label + '」且目前待審的案件改為「' + decision + '」。這是承辦人批次決定，不是 AI 自動核定。需人工複核的案件不會一併處理。'
  )) {
    return '已取消，未改任何人工審查決定';
  }
  let count = 0;
  ids.forEach(id => {
    if (applyManualDecision(book, id, decision)) count += 1;
  });
  applyDecisionColumnColors(book.getSheetByName('人工審查'), 2);
  applyDecisionColumnColors(book.getSheetByName('申請案件'), 6);
  return '已人工將 ' + count + ' 筆改為「' + decision + '」（AI 僅提供建議）';
}

function approveAiSuggestedPass() {
  return applyHumanDecisionsByAiColor('approve', '核准', '淡綠／建議核准');
}

function applyAiSuggestedRepair() {
  return applyHumanDecisionsByAiColor('repair', '需補件', '淡黃／建議補件');
}

function applyAiSuggestedReject() {
  return applyHumanDecisionsByAiColor('reject', '駁回', '淡紅／建議駁回');
}

function onEdit(e) {
  if (!e || !e.range || e.range.getSheet().getName() !== '人工審查' ||
      e.range.getRow() < 2 || e.range.getColumn() !== 2 ||
      e.range.getNumRows() !== 1 || e.range.getNumColumns() !== 1) return;
  const decision = e.range.getValue();
  const caseId = e.range.getSheet().getRange(e.range.getRow(), 1).getValue();
  applyManualDecision(e.range.getSheet().getParent(), caseId, decision);
}

function findCaseRow(sheet, caseId) {
  if (!sheet || sheet.getLastRow() < 2 || !caseId) return null;
  const index = sheet.getRange(2, 1, sheet.getLastRow() - 1, 1).getValues()
    .findIndex(row => row[0] === caseId);
  return index < 0 ? null : index + 2;
}

function displayRowsFor(row) {
  return [
    [row[0], row[1], row[4], row[26], row[35], row[2], row[3]],
    [row[0]].concat(row.slice(4, 49)),
    [row[0]].concat(row.slice(49, 61)),
    aiDisplayRow(
      row[0],
      row[CASE_HEADERS.indexOf('AI 查核狀態')],
      row[CASE_HEADERS.indexOf('AI 查核建議')],
      row[CASE_HEADERS.indexOf('AI 信心程度')],
      splitAiFindings(row[CASE_HEADERS.indexOf('AI 疑點')])
    ),
    [row[0]].concat(row.slice(65, 68))
  ];
}

function ensureAiDisplaySheet(book) {
  const target = (book && typeof book.getSheetByName === 'function') ? book : openBook();
  const sheet = target.getSheetByName('AI 查核');
  if (!sheet) throw new Error('找不到 AI 查核分頁');
  const headers = aiDisplayHeaders();
  const width = Math.max(typeof sheet.getLastColumn === 'function' ? sheet.getLastColumn() : headers.length, headers.length);
  const current = sheet.getRange(1, 1, 1, width).getValues()[0] || [];
  if (headers.every((value, index) => current[index] === value)) {
    if (typeof paintAiSheetColors === 'function') paintAiSheetColors(sheet);
    return 'AI 查核已是分階段欄位，已重新上色';
  }
  const old = ['案件編號', 'AI 查核狀態', 'AI 查核建議', 'AI 疑點', 'AI 信心程度'];
  const isOld = old.every((value, index) => current[index] === value);
  const isNumbered = String(current[4] || '').indexOf('疑點') === 0;
  const values = sheet.getLastRow() ? sheet.getDataRange().getValues() : [[]];
  const next = [headers];
  values.slice(1).forEach(row => {
    if (!row || !row[0]) return;
    if (isOld) {
      next.push(aiDisplayRow(row[0], row[1], row[2], row[4], splitAiFindings(row[3])));
    } else if (isNumbered) {
      next.push(aiDisplayRow(row[0], row[1], row[2], row[3], row.slice(4).filter(Boolean)));
    } else {
      next.push(aiDisplayRow(row[0], row[1], row[2], row[3], splitAiFindings(row.slice(4).join('\n'))));
    }
  });
  if (typeof sheet.clearContents === 'function') sheet.clearContents();
  next.forEach((row, index) => {
    const range = sheet.getRange(index + 1, 1, 1, row.length);
    if (typeof range.setValues === 'function') range.setValues([row]);
    else row.forEach((value, column) => sheet.getRange(index + 1, column + 1).setValue(value));
  });
  try {
    sheet.getRange(1, 1, 1, headers.length).setFontWeight('bold').setBackground('#E8F0FA');
  } catch (ignore) {}
  if (typeof paintAiSheetColors === 'function') paintAiSheetColors(sheet);
  return '已把 AI 結果分成規則／身分證／發票／切結書／說明，並依核准色上色';
}

function assertDisplaySheets(book) {
  const expected = [
    ['案件編號', '送出時間', '申請人姓名', 'AI 工具名稱', '換算新臺幣', '審查狀態', '承辦公開說明'],
    ['案件編號'].concat(CASE_HEADERS.slice(4, 49)),
    ['案件編號'].concat(CASE_HEADERS.slice(49, 61)),
    aiDisplayHeaders(),
    ['案件編號'].concat(CASE_HEADERS.slice(65, 68))
  ];
  DISPLAY_SHEETS.forEach((name, index) => {
    const sheet = book.getSheetByName(name);
    if (!sheet || expected[index].some((value, column) =>
      sheet.getRange(1, column + 1).getValue() !== value)) {
      throw new Error(name + ' 欄位不一致，已停止寫入');
    }
  });
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

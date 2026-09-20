/** @OnlyCurrentDoc */
// 五個可見分頁的第一階段版面。原始 69 欄保留為隱藏底稿，避免資料遺失。
const LAYOUT_RAW_SHEET = '_原始資料_69欄';
const LAYOUT_CHOICES = ['待審', '需補件', '核准', '駁回'];

function setupFiveTabs() {
  const book = SpreadsheetApp.getActiveSpreadsheet();
  let raw = book.getSheetByName(LAYOUT_RAW_SHEET);
  if (!raw) {
    raw = book.getSheetByName('申請案件');
    if (!raw) throw new Error('找不到原本的申請案件工作表');
    if (raw.getLastRow() > 1) throw new Error('原表已有案件，請先規劃資料搬移，未更動任何資料');
    const headers = raw.getRange(1, 1, 1, 69).getValues()[0];
    if (headers.length !== 69 || headers[0] !== '案件編號' ||
        headers[49] !== '身分證正面連結' || headers[65] !== '人工審查決定' ||
        headers[68] !== '案件查詢代碼') {
      throw new Error('原始 69 欄標題與預期不同，未更動任何資料');
    }
    raw.setName(LAYOUT_RAW_SHEET);
  }

  const source = raw.getRange(1, 1, 1, 69).getValues()[0];
  const groups = [
    ['申請案件', ['案件編號', '送出時間', '申請人姓名', 'AI 工具名稱', '換算新臺幣', '審查狀態', '承辦公開說明']],
    ['申請資料', ['案件編號'].concat(source.slice(4, 49))],
    ['附件', ['案件編號'].concat(source.slice(49, 61))],
    ['AI 查核', typeof aiDisplayHeaders === 'function' ? aiDisplayHeaders() : ['案件編號'].concat(source.slice(61, 65))],
    ['人工審查', reviewSheetHeaders()],
  ];
  groups.forEach(([name, headers], index) => {
    const sheet = book.getSheetByName(name) || book.insertSheet(name);
    const current = sheet.getRange(1, 1, 1, headers.length).getValues()[0];
    if (current.some(value => value !== '')) {
      if (name !== '人工審查' && current.some((value, i) => value !== headers[i])) {
        throw new Error(name + ' 的欄位已被更動，未覆蓋');
      }
    } else {
      sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
    }
    sheet.getRange(1, 1, 1, headers.length).setFontWeight('bold').setBackground('#E8F0FA');
    sheet.setFrozenRows(1);
    sheet.setFrozenColumns(1);
    book.setActiveSheet(sheet);
    book.moveActiveSheet(index + 1);
  });

  ensureReviewSheet(book);
  raw.hideSheet();
  book.setActiveSheet(book.getSheetByName('申請案件'));
  if (typeof applyMeiZhuTongColors === 'function') applyMeiZhuTongColors();
  return '已建立五個可見分頁；原始 69 欄保留在隱藏底稿。';
}

function reviewSheetHeaders() {
  return ['案件編號', '人工審查決定', '承辦備註', '決定時間'];
}

function looksLikeCaseId(value) {
  return /^MZT-/i.test(String(value || '').trim());
}

function restoredReviewDecision(current, caseId, fromRaw) {
  const value = String(current || '').trim();
  if (LAYOUT_CHOICES.indexOf(value) >= 0) return value;
  if (LAYOUT_CHOICES.indexOf(String(fromRaw || '').trim()) >= 0) return String(fromRaw).trim();
  if (looksLikeCaseId(value) || value === String(caseId || '')) return '待審';
  return value || '待審';
}

/** 恢復 B 欄「待審／需補件／核准／駁回」下拉。標題被改掉或清除內容後驗證會消失。 */
function ensureReviewSheet(book) {
  const target = book || (typeof SpreadsheetApp.getActiveSpreadsheet === 'function' && SpreadsheetApp.getActiveSpreadsheet());
  const review = target && target.getSheetByName('人工審查');
  if (!review) return '找不到人工審查分頁';
  const headers = reviewSheetHeaders();
  review.getRange(1, 1, 1, headers.length).setValues([headers]);
  review.getRange(1, 1, 1, headers.length).setFontWeight('bold').setBackground('#E8F0FA');
  if (review.getLastRow() >= 2) {
    const raw = target.getSheetByName('_原始資料_69欄');
    const pairs = review.getRange(2, 1, review.getLastRow() - 1, 2).getValues();
    const decisionCol = (typeof CASE_HEADERS !== 'undefined')
      ? CASE_HEADERS.indexOf('人工審查決定') + 1
      : 66;
    const restored = pairs.map(pair => {
      const caseId = pair[0];
      let fromRaw = '';
      if (caseId && raw && typeof findCaseRow === 'function') {
        const rawRow = findCaseRow(raw, caseId);
        if (rawRow) fromRaw = raw.getRange(rawRow, decisionCol).getValue();
      }
      return [restoredReviewDecision(pair[1], caseId, fromRaw)];
    });
    review.getRange(2, 2, restored.length, 1).setValues(restored);
  }
  const rule = SpreadsheetApp.newDataValidation()
    .requireValueInList(LAYOUT_CHOICES, true).setAllowInvalid(false).build();
  review.getRange(2, 2, Math.max(review.getMaxRows() - 1, 1), 1).setDataValidation(rule);
  review.getRange(2, 4, Math.max(review.getMaxRows() - 1, 1), 1).setNumberFormat('yyyy-mm-dd hh:mm');
  review.setFrozenRows(1);
  review.setFrozenColumns(1);
  return '人工審查第 B 欄已恢復下拉：待審／需補件／核准／駁回';
}

function ensureReviewSheetFromMenu() {
  const book = SpreadsheetApp.getActiveSpreadsheet();
  const message = ensureReviewSheet(book);
  try {
    SpreadsheetApp.getUi().alert(message);
  } catch (error) {}
  return message;
}

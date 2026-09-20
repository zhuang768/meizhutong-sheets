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
    ['人工審查', ['案件編號'].concat(source.slice(65, 68))],
  ];
  groups.forEach(([name, headers], index) => {
    const sheet = book.getSheetByName(name) || book.insertSheet(name);
    const current = sheet.getRange(1, 1, 1, headers.length).getValues()[0];
    if (current.some(value => value !== '')) {
      if (current.some((value, i) => value !== headers[i])) {
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

  const review = book.getSheetByName('人工審查');
  const rule = SpreadsheetApp.newDataValidation()
    .requireValueInList(LAYOUT_CHOICES, true).setAllowInvalid(false).build();
  review.getRange(2, 2, review.getMaxRows() - 1, 1).setDataValidation(rule);
  review.getRange(2, 4, review.getMaxRows() - 1, 1).setNumberFormat('yyyy-mm-dd hh:mm');
  raw.hideSheet();
  book.setActiveSheet(book.getSheetByName('申請案件'));
  if (typeof applyMeiZhuTongColors === 'function') applyMeiZhuTongColors();
  return '已建立五個可見分頁；原始 69 欄保留在隱藏底稿。';
}

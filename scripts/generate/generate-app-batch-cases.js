#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = ['Schema.gs', 'AiAudit.gs'].map(name =>
  fs.readFileSync(path.join(__dirname, '..', '..', 'sheets', name), 'utf8')).join('\n');
const context = vm.createContext({ Set, Map, Date, Number, Math, JSON, String, Array });
vm.runInContext(source + `
  this.api = {
    CASE_HEADERS, AI_VOLUME_SCENARIOS, buildSyntheticCaseRow, volumeScenario, formatDay
  };
`, context);
const { CASE_HEADERS, AI_VOLUME_SCENARIOS, buildSyntheticCaseRow, volumeScenario, formatDay } = context.api;

const col = name => CASE_HEADERS.indexOf(name);
const iso = value => {
  if (value instanceof Date) return formatDay(value);
  if (value == null || value === '') return '';
  return String(value);
};
const flag = value => value === true || value === 'TRUE' || value === 'true';
const text = value => value == null ? '' : String(value);

function documentVariant(scenario) {
  if (scenario === 'missingDocs') return 'none';
  if (scenario === 'missingPassbook') return 'skipPassbook';
  if (scenario === 'passXiangshan') return 'idMismatch';
  if (scenario === 'passSyntheticId') return 'receiptMismatch';
  if (scenario === 'passHighAmount') return 'unsignedAffidavit';
  return 'match';
}

function youthRow(index) {
  const scenario = volumeScenario(index);
  const row = buildSyntheticCaseRow(index);
  return {
    caseId: text(row[col('案件編號')]),
    scenario,
    documentVariant: documentVariant(scenario),
    fullName: text(row[col('申請人姓名')]),
    nationalID: text(row[col('身分證字號')]),
    birthDate: iso(row[col('出生日期')]),
    phone: text(row[col('聯絡電話')]),
    contactEmail: text(row[col('電子郵件')]),
    isHsinchuResident: flag(row[col('設籍新竹市')]),
    identityCategory: text(row[col('身分類別')]),
    specialIdentityKinds: text(row[col('特定對象類別')]),
    culturalLanguageKinds: text(row[col('文化語言證明類別')]),
    householdPostalCode: text(row[col('戶籍郵遞區號')]),
    householdDistrict: text(row[col('戶籍行政區')]),
    householdAddress: text(row[col('戶籍地址')]),
    mailingSameAsHousehold: flag(row[col('通訊地址同戶籍')]),
    mailingPostalCode: text(row[col('通訊郵遞區號')]),
    mailingCity: text(row[col('通訊縣市')]),
    mailingDistrict: text(row[col('通訊行政區')]),
    mailingStreet: text(row[col('通訊詳細地址')]),
    bankName: text(row[col('匯款銀行')]),
    bankAccountMasked: text(row[col('帳戶末碼')]),
    subscriptionPlan: text(row[col('繳費制度')]),
    monthlyPeriods: Number(row[col('月費期數')] || 1),
    toolCategory: text(row[col('工具類別')]) || 'general',
    toolName: text(row[col('AI 工具名稱')]),
    vendorName: text(row[col('軟體公司名稱')]),
    vendorRegionCompliant: flag(row[col('廠商地區符合規定')]),
    purchaseChannel: text(row[col('購買管道')]),
    purchaseDate: iso(row[col('購買日期')]),
    subscriptionStart: iso(row[col('訂閱起日')]),
    subscriptionEnd: iso(row[col('訂閱迄日')]),
    originalCurrency: text(row[col('原始費用幣別')]),
    originalAmount: String(row[col('原始費用')] ?? ''),
    twdPaidAmount: String(row[col('換算新臺幣')] ?? ''),
    paymentMethod: text(row[col('付款方式')]),
    isPrepaidCreditOrToken: flag(row[col('預付點數或代幣')]),
    isProxyPaid: flag(row[col('是否由他人代付')]),
    proxyPayerName: text(row[col('代付人姓名')]),
    proxyPayerRelation: text(row[col('代付關係')]),
    receiptBuyer: flag(row[col('收據已註明購買人')]),
    receiptStatement: flag(row[col('帳單可證明購買品項')]),
    receiptCard: flag(row[col('已附信用卡末四碼及姓名證明')]),
    receiptTool: flag(row[col('收據有軟體名稱')]),
    receiptVendor: flag(row[col('收據有公司名稱')]),
    receiptDate: flag(row[col('收據有購買日期')]),
    receiptAmount: flag(row[col('收據有原始費用')]),
    receiptTwd: flag(row[col('收據有新臺幣換算')])
  };
}

const batchSize = 20;
const payload = {
  datasetTotal: 50000,
  batchSize,
  rows: Array.from({ length: batchSize }, (_, index) => youthRow(index))
};

const assetDir = path.join(
  __dirname, '..', '..', 'YouthAISubsidy', 'Assets.xcassets', 'SyntheticAppBatch.dataset'
);
fs.mkdirSync(assetDir, { recursive: true });
fs.writeFileSync(path.join(assetDir, 'Contents.json'), JSON.stringify({
  data: [{
    filename: 'SyntheticAppBatch.json',
    idiom: 'universal',
    'universal-type-identifier': 'public.json'
  }],
  info: { author: 'xcode', version: 1 }
}, null, 2) + '\n');
fs.writeFileSync(path.join(assetDir, 'SyntheticAppBatch.json'), JSON.stringify(payload));

if (payload.rows.length !== batchSize) throw new Error('App 批次筆數不正確');
if (payload.rows[0].caseId !== 'MZT-LOADTEST-000001') throw new Error('第一筆案件編號不正確');
if (payload.rows[0].scenario !== 'pass') throw new Error('第一筆情境應為 pass');
if (payload.rows[5].documentVariant !== 'idMismatch') throw new Error('香山通過案應為身分證不符影像');
if (payload.rows[6].documentVariant !== 'receiptMismatch') throw new Error('合成身分證通過案應為發票不符影像');
if (payload.rows[7].documentVariant !== 'unsignedAffidavit') throw new Error('高額通過案應為未簽切結書');
if (new Set(payload.rows.map(row => row.scenario)).size !== batchSize) {
  throw new Error('前 20 筆應覆蓋 20 種不同情境');
}

console.log(JSON.stringify({
  count: payload.rows.length,
  datasetTotal: payload.datasetTotal,
  scenarios: payload.rows.map(row => row.scenario),
  documentVariants: payload.rows.map(row => row.documentVariant),
  scenarioCatalog: AI_VOLUME_SCENARIOS.length
}, null, 2));

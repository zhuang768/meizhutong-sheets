#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[1] / 'testdata' / 'documents'
FONT = '/System/Library/Fonts/Supplemental/Songti.ttc'


def font(size):
    return ImageFont.truetype(FONT, size=size, index=0)


def card(lines, signed=False):
    image = Image.new('RGB', (1100, 680), (248, 250, 252))
    draw = ImageDraw.Draw(image)
    draw.rectangle((18, 18, 1082, 662), outline=(40, 70, 140), width=6)
    draw.text((48, 40), 'SYNTHETIC DOCUMENT - NOT REAL', font=font(28), fill=(40, 70, 140))
    for index, line in enumerate(lines):
        draw.text((48, 110 + index * 70), line, font=font(36), fill=(20, 20, 20))
    if signed:
        draw.line((80, 560, 220, 520, 340, 580, 480, 530), fill=(20, 20, 80), width=6)
        draw.text((80, 590), '簽名', font=font(28), fill=(20, 20, 80))
    return image


def save(name, image):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    image.save(path, 'PNG')
    return path


def main():
    save('match-id-front.png', card([
        '測試身分證正面',
        '姓名：合成林青禾',
        '出生：1998/06/15',
        '身分證字號：TEST-ID-ONLY',
    ]))
    save('match-id-back.png', card([
        '測試身分證背面',
        '戶籍地址：新竹市東區測試路 1 號',
        '郵遞區號：300',
    ]))
    save('match-receipt.png', card([
        '測試官方收據',
        '購買人：合成林青禾',
        '工具：ChatGPT Plus',
        '公司：OpenAI',
        '日期：2026/08/01',
        '金額：USD 20／TWD 2000',
    ]))
    save('match-affidavit.png', card([
        '測試親簽切結書',
        '申請人：合成林青禾',
        '本人已親簽，合成示範非正式文件。',
    ], signed=True))
    save('mismatch-id-front.png', card([
        '測試身分證正面',
        '姓名：王小明',
        '出生：1990/01/01',
        '身分證字號：A123456789',
    ]))
    save('mismatch-receipt.png', card([
        '測試官方收據',
        '購買人：別人',
        '工具：Poe 集合式方案',
        '公司：錯誤廠商',
        '日期：2025/01/01',
        '金額：USD 1／TWD 30',
    ]))
    save('unsigned-affidavit.png', card([
        '測試親簽切結書',
        '申請人：張三',
        '此件沒有手寫簽名。',
    ], signed=False))
    print(OUT)


if __name__ == '__main__':
    main()

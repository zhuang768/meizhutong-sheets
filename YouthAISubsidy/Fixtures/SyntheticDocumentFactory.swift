import Foundation
import UIKit

enum SyntheticDocumentFactory {
    static func makeImage(type: DocumentType, caseId: String) -> Data {
        if type == .idFront || type == .idBack || type == .officialReceipt {
            return makeScannableSample(type: type)
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 560))
        let image = renderer.image { context in
            UIColor(red: 0.93, green: 0.96, blue: 1.0, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 560))
            UIColor(red: 0.12, green: 0.25, blue: 0.69, alpha: 1).setStroke()
            context.cgContext.setLineWidth(8)
            context.cgContext.stroke(CGRect(x: 16, y: 16, width: 868, height: 528))

            let title = "SYNTHETIC DOCUMENT — NOT REAL"
            let body = """
            合成示範檔，非正式證件或付款資料。
            案件：\(caseId.replacingOccurrences(of: "DEMO-", with: ""))
            類型：\(type.zhTitle)
            \(type.officialNote)
            請勿在此檔放入真實身分證、存摺或信用卡。
            """
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 28),
                .foregroundColor: UIColor(red: 0.12, green: 0.23, blue: 0.54, alpha: 1)
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20),
                .foregroundColor: UIColor(red: 0.28, green: 0.33, blue: 0.41, alpha: 1)
            ]
            title.draw(in: CGRect(x: 40, y: 48, width: 820, height: 80), withAttributes: titleAttrs)
            body.draw(in: CGRect(x: 40, y: 140, width: 820, height: 360), withAttributes: bodyAttrs)
        }
        return image.pngData() ?? Data()
    }

    /// Clearly fictional sample data for exercising on-device text recognition.
    private static func makeScannableSample(type: DocumentType) -> Data {
        let lines: [String] = type == .idFront ? [
            "SYNTHETIC DOCUMENT - NOT REAL",
            "TEST FRONT - NOT AN ID CARD",
            "姓名 Name: 合成林青禾",
            "出生 Birth: 1998/06/15",
            "測試代碼 ID: TEST-ID-ONLY"
        ] : type == .idBack ? [
            "SYNTHETIC DOCUMENT - NOT REAL",
            "TEST BACK - NOT AN ID CARD",
            "戶籍 Address: 新竹市東區合成路0號",
            "郵遞區號 ZIP: 300"
        ] : [
            "SYNTHETIC RECEIPT - NOT REAL",
            "工具 Tool: Cursor",
            "賣方 Vendor: Anysphere",
            "購買日 Date: 2026/08/01",
            "金額 Amount: USD 20",
            "臺幣 TWD: 640"
        ]
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1100, height: 680))
        let image = renderer.image { context in
            UIColor(red: 0.97, green: 0.98, blue: 1, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1100, height: 680))
            UIColor(red: 0.12, green: 0.25, blue: 0.69, alpha: 1).setStroke()
            context.cgContext.setLineWidth(7)
            context.cgContext.stroke(CGRect(x: 18, y: 18, width: 1064, height: 644))
            for (index, line) in lines.enumerated() {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: index == 0 ? UIFont.boldSystemFont(ofSize: 32) : UIFont.systemFont(ofSize: 32),
                    .foregroundColor: UIColor.black
                ]
                line.draw(in: CGRect(x: 55, y: 66 + index * 89, width: 990, height: 70), withAttributes: attributes)
            }
        }
        return image.pngData() ?? Data()
    }
}

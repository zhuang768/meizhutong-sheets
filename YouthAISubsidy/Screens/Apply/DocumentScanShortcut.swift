import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

/// Optional camera/photo shortcut inside the existing form. Recognition runs on the iPhone.
struct DocumentScanShortcut: View {
    let type: DocumentType
    let onApply: (RecognizedSample) -> Void

    @State private var frontData: Data?
    @State private var backData: Data?
    @State private var selectedSide: DocumentType?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var result: RecognizedSample?
    @State private var errorMessage: String?
    @State private var isRecognizing = false

    private var isIdentity: Bool { type == .idFront }

    var body: some View {
        if isIdentity {
            Text("拍攝或選擇證件正反面。文字只在這支 iPhone 辨識，辨識結果不是身分驗證；請先核對再帶入。")
                .font(.footnote)
                .foregroundStyle(AppTheme.muted)
            scanActions(for: .idFront, title: "正面")
            scanActions(for: .idBack, title: "背面")
        } else {
            Text("可拍帳單或從手機相簿選照片。辨識只在這支手機上進行，結果會先讓你核對。")
                .font(.footnote)
                .foregroundStyle(AppTheme.muted)
            scanActions(for: .officialReceipt, title: "帳單")
        }

        Button {
            recognizeGeneratedSample()
        } label: {
            Label(isIdentity ? "使用合成證件測試" : "使用合成帳單測試", systemImage: "doc.text.viewfinder")
        }
        .disabled(isRecognizing)
        .accessibilityIdentifier(isIdentity ? "applicant.scanSyntheticID" : "purchase.scanSyntheticReceipt")

        if isRecognizing { ProgressView("正在裝置端辨識…") }
        if let errorMessage {
            Text(errorMessage).font(.footnote).foregroundStyle(AppTheme.danger)
        }

        Color.clear.frame(height: 0)
            .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, selected in
                guard let selected, let side = selectedSide else { return }
                Task { @MainActor in
                    defer { pickerItem = nil; selectedSide = nil }
                    do {
                        guard let data = try await selected.loadTransferable(type: Data.self) else {
                            throw LocalAttachmentError.unreadable
                        }
                        accept(data, side: side)
                    } catch {
                        errorMessage = "無法讀取這張照片，請重選或改用拍照。"
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraCapture(guide: isIdentity ? .identity : .receipt) { data in
                    let side = selectedSide
                    showCamera = false
                    selectedSide = nil
                    if let data, let side { accept(data, side: side) }
                }
            }
            .sheet(item: $result) { found in
                reviewSheet(found)
            }
    }

    private func scanActions(for side: DocumentType, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isIdentity {
                Label("\(title)\(selectedData(for: side) == nil ? "尚未拍攝" : "已完成拍攝")",
                      systemImage: selectedData(for: side) == nil ? "circle" : "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(selectedData(for: side) == nil ? AppTheme.muted : .green)
                    .accessibilityIdentifier("applicant.scanStatus.\(side.rawValue)")
            }
            HStack(spacing: 12) {
                Button {
                    startCamera(for: side)
                } label: {
                    Label(selectedData(for: side) == nil ? "拍\(title)" : "重拍\(title)", systemImage: "camera")
                }
                .accessibilityIdentifier(isIdentity ? "applicant.camera.\(side.rawValue)" : "purchase.cameraReceipt")

                Button {
                    selectedSide = side
                    errorMessage = nil
                    showPhotoPicker = true
                } label: {
                    Label("相簿選\(title)", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier(isIdentity ? "applicant.album.\(side.rawValue)" : "purchase.albumReceipt")
            }
            .buttonStyle(.bordered)
            .disabled(isRecognizing)
        }
    }

    private func selectedData(for side: DocumentType) -> Data? {
        side == .idFront ? frontData : backData
    }

    private func startCamera(for side: DocumentType) {
        #if targetEnvironment(simulator)
        errorMessage = "模擬器沒有相機；請在 iPhone 拍照，或從相簿選照片。"
        #else
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "這部裝置沒有可用的相機，請改從相簿選照片。"
            return
        }
        let permission = AVCaptureDevice.authorizationStatus(for: .video)
        guard permission != .denied && permission != .restricted else {
            errorMessage = "相機權限未開放，請到 iPhone 設定允許梅竹通使用相機。"
            return
        }
        selectedSide = side
        errorMessage = nil
        showCamera = true
        #endif
    }

    private func accept(_ data: Data, side: DocumentType) {
        guard !data.isEmpty, data.count <= LocalAttachmentStore.maxBytes, UIImage(data: data) != nil else {
            errorMessage = "照片無法開啟或超過 10 MB，請重拍或選較小的檔案。"
            return
        }
        errorMessage = nil
        if isIdentity {
            if side == .idFront { frontData = data } else { backData = data }
            guard let frontData, let backData else { return }
            recognizeIdentity(front: frontData, back: backData)
        } else {
            recognizeReceipt(data)
        }
    }

    private func recognizeIdentity(front: Data, back: Data) {
        isRecognizing = true
        Task {
            defer { isRecognizing = false }
            do {
                result = try await Task.detached(priority: .userInitiated) {
                    try LocalDocumentRecognition.recognizeIdentity(front: front, back: back)
                }.value
            } catch {
                errorMessage = "無法可靠讀取證件正反面。請將完整證件對準框內、避免反光後重拍，或手動填寫。"
            }
        }
    }

    private func recognizeReceipt(_ data: Data) {
        isRecognizing = true
        Task {
            defer { isRecognizing = false }
            do {
                result = try await Task.detached(priority: .userInitiated) {
                    try LocalDocumentRecognition.recognizeLocalReceipt(data)
                }.value
            } catch {
                errorMessage = "沒有辨識到可靠的帳單欄位。請重拍清楚照片，或手動填寫。"
            }
        }
    }

    private func recognizeGeneratedSample() {
        isRecognizing = true
        errorMessage = nil
        let front = SyntheticDocumentFactory.makeImage(type: type, caseId: "DEMO-SCAN")
        let back = isIdentity ? SyntheticDocumentFactory.makeImage(type: .idBack, caseId: "DEMO-SCAN") : nil
        Task {
            defer { isRecognizing = false }
            do {
                var found = try await Task.detached(priority: .userInitiated) {
                    if let back { return try LocalDocumentRecognition.recognizeIdentity(front: front, back: back) }
                    return try LocalDocumentRecognition.recognizeLocalReceipt(front)
                }.value
                found.isGeneratedSample = true
                result = found
            } catch {
                errorMessage = "測試圖辨識失敗，請重試。"
            }
        }
    }

    private func reviewSheet(_ found: RecognizedSample) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("請對照照片核對欄位；只會帶入辨識到的內容，不確定的保持空白。確認後也不會自動送出申請。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                    if let image = UIImage(data: found.imageData) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .accessibilityLabel("文件正面或帳單預覽")
                    }
                    if let data = found.reverseImageData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .accessibilityLabel("文件背面預覽")
                    }
                    if isIdentity {
                        field("姓名", found.name)
                        field("身分證字號", found.documentNumber)
                        field("出生日期", found.birthDate.map { $0.formatted(date: .numeric, time: .omitted) })
                        field("戶籍地址", found.address)
                        field("郵遞區號", found.postalCode)
                    } else {
                        field("AI 工具", found.toolName)
                        field("商家", found.vendorName)
                        field("購買日期", found.purchaseDate.map { $0.formatted(date: .numeric, time: .omitted) })
                        field("原始費用", found.originalAmount.map { "\(found.currency ?? "") \($0)" })
                        field("臺幣金額", found.twdAmount.map(String.init(describing:)))
                    }
                }
                .padding()
            }
            .navigationTitle("核對辨識結果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { result = nil } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("確認帶入") {
                        onApply(found)
                        frontData = nil
                        backData = nil
                        result = nil
                    }
                    .accessibilityIdentifier("scan.confirmApply")
                }
            }
        }
    }

    private func field(_ title: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(AppTheme.muted)
            Spacer()
            Text(value ?? "未辨識").multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

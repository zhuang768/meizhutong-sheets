import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import PDFKit
import AVFoundation

struct DocumentsView: View {
    @Bindable var model: ApplicationFlowModel
    @State private var pickerType: DocumentType?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var previewDocument: CaseDocument?
    @State private var isFileImporterPresented = false
    @State private var isCameraPresented = false
    @State private var showMissingOnly = false
    @State private var recognizedReceipt: RecognizedSample?
    @State private var receiptRecognitionError: String?
    @State private var isRecognizingReceipt = false

    var body: some View {
        Form {
            ErrorSummary(issues: model.issues)
            Section {
                Text("附件只存於這支 iPhone 的受保護儲存空間，尚未上傳；這不是正式市府申請。使用真實證件時請確認是自己的資料，並避免讓他人操作手機。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                Button("一次附上目前身分所需的合成文件") {
                    model.attachAllRequiredSyntheticDocuments()
                }
                .accessibilityIdentifier("documents.attachAllSynthetic")
                .disabled(model.isImportingAttachment)
            }
            Section("應備文件") {
                let required = FormValidator.requiredDocumentTypes(for: model.draft)
                let missing = FormValidator.missingDocumentTypes(for: model.draft)
                Text("已附 \(required.count - missing.count)／\(required.count) 項，尚缺 \(missing.count) 項")
                    .accessibilityIdentifier("documents.completion")
                Toggle("只看尚未附上的文件", isOn: $showMissingOnly)
                ForEach(showMissingOnly ? missing : required, id: \.self) { type in
                    documentRow(type)
                }
            }
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $pickerItem,
            matching: .images
        )
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.image, .pdf]) { result in
            guard let type = pickerType else { return }
            defer { pickerType = nil }
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= LocalAttachmentStore.maxBytes else {
                    model.banner = LocalAttachmentError.tooLarge.localizedDescription
                    return
                }
                model.attachLocalPhoto(type: type, data: try Data(contentsOf: url))
            } catch { model.reportAttachmentFailure() }
        }
        .sheet(isPresented: $isCameraPresented) {
            CameraCapture { data in
                if let data, let type = pickerType { model.attachLocalPhoto(type: type, data: data) }
                pickerType = nil
                isCameraPresented = false
            }
        }
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue, let type = pickerType else { return }
            model.isImportingAttachment = true
            Task { @MainActor in
                defer {
                    model.isImportingAttachment = false
                    pickerItem = nil
                    pickerType = nil
                }
                do {
                    guard let data = try await newValue.loadTransferable(type: Data.self) else {
                        model.reportAttachmentFailure()
                        return
                    }
                    model.attachLocalPhoto(type: type, data: data)
                } catch {
                    model.reportAttachmentFailure()
                }
            }
        }
        .sheet(item: $previewDocument) { document in
            LocalDocumentPreview(document: document)
        }
        .sheet(item: $recognizedReceipt) { found in
            NavigationStack {
                Form {
                    Section("辨識結果，請先核對") {
                        receiptField("AI 產品", found.toolName)
                        receiptField("商家", found.vendorName)
                        receiptField("付款日期", found.purchaseDate.map { $0.formatted(date: .numeric, time: .omitted) })
                        receiptField("原始金額", found.originalAmount.map { "\(found.currency ?? "") \($0)" })
                        receiptField("臺幣金額", found.twdAmount.map(String.init(describing:)))
                    }
                    Section {
                        Text("只帶入可辨識的欄位；不確定的留待手填。請另外預覽原收據並逐項確認，辨識結果不是審核或核准。全程只在本機處理。")
                            .font(.footnote)
                    }
                }
                .navigationTitle("核對帳單資料")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { recognizedReceipt = nil }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("確認帶入") {
                            if let tool = found.toolName { model.draft.purchase.toolName = tool }
                            if let vendor = found.vendorName { model.draft.purchase.vendorName = vendor }
                            if let date = found.purchaseDate { model.draft.purchase.purchaseDate = date }
                            if let amount = found.originalAmount { model.draft.purchase.originalAmount = DecimalString(amount) }
                            if let currency = found.currency { model.draft.purchase.originalCurrency = currency }
                            if let amount = found.twdAmount { model.draft.purchase.twdPaidAmount = DecimalString(amount) }
                            model.banner = "已帶入可辨識的帳單欄位。請核對購買資料，未辨識的請手填。"
                            recognizedReceipt = nil
                            model.step = .purchase
                        }
                        .accessibilityIdentifier("documents.scanReceipt.confirm")
                    }
                }
            }
        }
    }

    private func documentRow(_ type: DocumentType) -> some View {
        let attached = model.draft.documents.first(where: { $0.type == type })
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: attached == nil ? "square" : "checkmark.square.fill")
                    .foregroundStyle(attached == nil ? AppTheme.muted : AppTheme.accent)
                Text(type.zhTitle)
                    .font(.subheadline.weight(.semibold))
            }
            Text(type.officialNote)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
            if let attached {
                Text(YouthPresentation.attachmentStatusText(for: attached))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityIdentifier("documents.localOnly.\(type.rawValue)")
                Text(byteLabel(for: attached))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
                if type == .officialReceipt {
                    Button {
                        recognizeReceipt(attached)
                    } label: {
                        Label("本機辨識收據並帶入", systemImage: "text.viewfinder")
                    }
                    .disabled(isRecognizingReceipt || model.isImportingAttachment)
                    .accessibilityIdentifier("documents.scanReceipt")
                    if isRecognizingReceipt { ProgressView("正在本機辨識…") }
                    if let receiptRecognitionError {
                        Text(receiptRecognitionError).font(.caption).foregroundStyle(AppTheme.danger)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                Button("使用合成檔") {
                    model.attachSynthetic(type)
                }
                .accessibilityIdentifier("documents.synthetic.\(type.rawValue)")
                Button(attached == nil ? "從相簿選（僅存本機）" : "重選照片（僅存本機）") {
                    pickerType = type
                    isPhotoPickerPresented = true
                }
                .accessibilityIdentifier("documents.pickAlbum.\(type.rawValue)")
                Button("選擇檔案／PDF") {
                    pickerType = type
                    isFileImporterPresented = true
                }
                .accessibilityIdentifier("documents.pickFile.\(type.rawValue)")
                Button("拍照") {
                    #if targetEnvironment(simulator)
                    model.banner = "此裝置無法使用相機；模擬器請改用相簿或選擇檔案。"
                    #else
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        model.banner = "此裝置無法使用相機，請改用相簿或選擇檔案。"
                        return
                    }
                    let authorization = AVCaptureDevice.authorizationStatus(for: .video)
                    guard authorization != .denied && authorization != .restricted else {
                        model.banner = "相機權限未開放，請至 iPhone 設定允許梅竹通使用相機，或改用相簿。"
                        return
                    }
                    pickerType = type
                    isCameraPresented = true
                    #endif
                }
                .accessibilityIdentifier("documents.camera.\(type.rawValue)")
                if let attached {
                    Button("預覽") {
                        previewDocument = attached
                    }
                    .accessibilityIdentifier("documents.preview.\(type.rawValue)")
                    Button("移除", role: .destructive) {
                        model.removeDocument(type)
                    }
                    .accessibilityIdentifier("documents.remove.\(type.rawValue)")
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(DocumentActionStyle())
            .disabled(model.isImportingAttachment)
        }
        .padding(.vertical, 4)
    }

    private func byteLabel(for document: CaseDocument) -> String {
        let kb = max(1, document.byteCount / 1_024)
        return "本機檔名由 App 產生，約 \(kb) KB；每檔上限 10 MB，尚未上傳。"
    }

    private func recognizeReceipt(_ document: CaseDocument) {
        isRecognizingReceipt = true
        receiptRecognitionError = nil
        model.isImportingAttachment = true
        let url = LocalAttachmentStore.fileURL(for: document)
        Task {
            defer {
                isRecognizingReceipt = false
                model.isImportingAttachment = false
            }
            do {
                let found = try await Task.detached(priority: .userInitiated) {
                    try LocalDocumentRecognition.recognizeLocalReceipt(Data(contentsOf: url))
                }.value
                recognizedReceipt = found
            } catch {
                receiptRecognitionError = "無法辨識這份收據。請預覽原檔並手動填寫購買資料。"
            }
        }
    }

    private func receiptField(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value ?? "未辨識").foregroundStyle(value == nil ? AppTheme.warning : .primary)
        }
    }
}

private struct DocumentActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .background(AppTheme.primary.opacity(configuration.isPressed ? 0.18 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct LocalDocumentPreview: View {
    @Environment(\.dismiss) private var dismiss
    let document: CaseDocument

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(YouthPresentation.attachmentStatusText(for: document))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.warning)
                    .accessibilityIdentifier("documents.preview.localOnly")
                if document.contentType == "application/pdf", let pdf = PDFDocument(url: LocalAttachmentStore.fileURL(for: document)) {
                    LocalPDFPreview(document: pdf)
                } else if let image = LocalAttachmentStore.loadImage(for: document) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(document.type.zhTitle)
                } else {
                    Text("本機檔案不存在或已清理，請重選或改用合成檔。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.danger)
                        .accessibilityIdentifier("documents.preview.missing")
                }
                Spacer()
            }
            .padding(16)
            .navigationTitle(document.type.zhTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("documents.preview.close")
                }
            }
        }
    }
}

private struct LocalPDFPreview: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) { view.document = document }
}

enum CameraGuide {
    case identity
    case receipt
    case document

    var title: String {
        switch self {
        case .identity: return "將證件完整對準框內"
        case .receipt: return "將帳單文字完整對準框內"
        case .document: return "將文件完整對準框內"
        }
    }
}

struct CameraFrameCrop {
    /// The preview uses resizeAspectFill. Convert its visible guide into pixels of the upright photo.
    static func imageRect(imageSize: CGSize, previewSize: CGSize, guideRect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              previewSize.width > 0, previewSize.height > 0 else { return .zero }
        let scale = max(previewSize.width / imageSize.width, previewSize.height / imageSize.height)
        let drawnSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offset = CGPoint(x: (previewSize.width - drawnSize.width) / 2,
                             y: (previewSize.height - drawnSize.height) / 2)
        let rect = CGRect(x: (guideRect.minX - offset.x) / scale,
                          y: (guideRect.minY - offset.y) / scale,
                          width: guideRect.width / scale,
                          height: guideRect.height / scale)
        return rect.intersection(CGRect(origin: .zero, size: imageSize))
    }

    static func crop(_ image: UIImage, previewSize: CGSize, guideRect: CGRect) -> UIImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        // UIImage.size already reflects imageOrientation, including quarter turns.
        let uprightSize = image.size
        let upright = UIGraphicsImageRenderer(size: uprightSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: uprightSize))
        }
        guard let cgImage = upright.cgImage else { return nil }
        let rect = imageRect(imageSize: CGSize(width: cgImage.width, height: cgImage.height),
                             previewSize: previewSize, guideRect: guideRect).integral
        guard !rect.isNull, !rect.isEmpty, let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}

struct CameraCapture: UIViewControllerRepresentable {
    let guide: CameraGuide
    let completion: (Data?) -> Void

    init(guide: CameraGuide = .document, completion: @escaping (Data?) -> Void) {
        self.guide = guide
        self.completion = completion
    }

    func makeUIViewController(context: Context) -> GuidedCameraViewController {
        GuidedCameraViewController(guide: guide, completion: completion)
    }
    func updateUIViewController(_ controller: GuidedCameraViewController, context: Context) {}
}

final class GuidedCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    private let guide: CameraGuide
    private let completion: (Data?) -> Void
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "meizhoutong.camera.session")
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let frameLayer = CAShapeLayer()
    private let instructionLabel = UILabel()
    private let shutterButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let reviewImageView = UIImageView()
    private let useButton = UIButton(type: .system)
    private let retakeButton = UIButton(type: .system)
    private var guideRect = CGRect.zero
    private var capturedData: Data?

    init(guide: CameraGuide, completion: @escaping (Data?) -> Void) {
        self.guide = guide
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.session = session
        view.layer.addSublayer(previewLayer)
        frameLayer.strokeColor = UIColor.white.cgColor
        frameLayer.fillColor = UIColor.clear.cgColor
        frameLayer.lineWidth = 3
        frameLayer.shadowColor = UIColor.black.cgColor
        frameLayer.shadowOpacity = 0.8
        frameLayer.shadowRadius = 4
        view.layer.addSublayer(frameLayer)

        instructionLabel.text = guide.title
        instructionLabel.textAlignment = .center
        instructionLabel.textColor = .white
        instructionLabel.font = .preferredFont(forTextStyle: .headline)
        instructionLabel.shadowColor = .black
        view.addSubview(instructionLabel)

        shutterButton.setTitle("拍照", for: .normal)
        shutterButton.titleLabel?.font = .boldSystemFont(ofSize: 19)
        shutterButton.backgroundColor = .white
        shutterButton.tintColor = .black
        shutterButton.layer.cornerRadius = 32
        shutterButton.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
        view.addSubview(shutterButton)

        cancelButton.setTitle("取消", for: .normal)
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        view.addSubview(cancelButton)

        reviewImageView.contentMode = .scaleAspectFit
        reviewImageView.backgroundColor = .black
        reviewImageView.isHidden = true
        view.addSubview(reviewImageView)
        useButton.setTitle("使用照片", for: .normal)
        useButton.backgroundColor = .systemBlue
        useButton.tintColor = .white
        useButton.layer.cornerRadius = 12
        useButton.addTarget(self, action: #selector(usePhoto), for: .touchUpInside)
        useButton.isHidden = true
        view.addSubview(useButton)
        retakeButton.setTitle("重拍", for: .normal)
        retakeButton.tintColor = .white
        retakeButton.addTarget(self, action: #selector(retake), for: .touchUpInside)
        retakeButton.isHidden = true
        view.addSubview(retakeButton)

        sessionQueue.async { [weak self] in self?.configureAndStartSession() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        previewLayer.frame = bounds
        let width = bounds.width * 0.82
        let height = guide == .identity ? width * 54.0 / 85.7 : min(bounds.height * 0.48, bounds.height * 0.55)
        guideRect = CGRect(x: (bounds.width - width) / 2,
                           y: bounds.height * 0.42 - height / 2,
                           width: width, height: height)
        frameLayer.path = UIBezierPath(roundedRect: guideRect, cornerRadius: 12).cgPath
        instructionLabel.frame = CGRect(x: 20, y: guideRect.minY - 52, width: bounds.width - 40, height: 40)
        shutterButton.frame = CGRect(x: (bounds.width - 116) / 2, y: bounds.height - view.safeAreaInsets.bottom - 98, width: 116, height: 64)
        cancelButton.frame = CGRect(x: 20, y: shutterButton.frame.minY + 12, width: 72, height: 40)
        reviewImageView.frame = bounds
        useButton.frame = CGRect(x: bounds.midX - 8, y: shutterButton.frame.minY, width: bounds.midX - 28, height: 54)
        retakeButton.frame = CGRect(x: 20, y: shutterButton.frame.minY, width: bounds.midX - 38, height: 54)
        orientPreview()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureAndStartSession() {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                if allowed { self?.sessionQueue.async { self?.configureAndStartSession() } }
            }
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera) else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()
        session.startRunning()
        DispatchQueue.main.async { [weak self] in self?.orientPreview() }
    }

    private func orientPreview() {
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    @objc private func takePhoto() {
        guard session.isRunning else { return }
        shutterButton.isEnabled = false
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.shutterButton.isEnabled = true
            guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data),
                  let cropped = CameraFrameCrop.crop(image, previewSize: self.view.bounds.size, guideRect: self.guideRect),
                  let croppedData = cropped.jpegData(compressionQuality: 0.88) else { return }
            self.capturedData = croppedData
            self.reviewImageView.image = cropped
            self.reviewImageView.isHidden = false
            self.useButton.isHidden = false
            self.retakeButton.isHidden = false
            self.frameLayer.isHidden = true
            self.instructionLabel.isHidden = true
            self.shutterButton.isHidden = true
            self.cancelButton.isHidden = true
        }
    }

    @objc private func retake() {
        capturedData = nil
        reviewImageView.image = nil
        reviewImageView.isHidden = true
        useButton.isHidden = true
        retakeButton.isHidden = true
        frameLayer.isHidden = false
        instructionLabel.isHidden = false
        shutterButton.isHidden = false
        cancelButton.isHidden = false
    }
    @objc private func usePhoto() { completion(capturedData) }
    @objc private func cancel() { completion(nil) }
}

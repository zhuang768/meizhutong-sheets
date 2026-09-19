import SwiftUI

struct ApplicantFormView: View {
    @Bindable var model: ApplicationFlowModel

    var body: some View {
        Form {
            ErrorSummary(issues: model.issues)
            Section("拍照／相簿帶入（選用）") {
                DocumentScanShortcut(type: .idFront) { found in
                    if let name = found.name { model.draft.applicant.fullName = name }
                    if let id = found.documentNumber { model.draft.formFields.nationalID = id }
                    if let birthDate = found.birthDate { model.draft.applicant.birthDate = birthDate }
                    if let address = found.address {
                        model.draft.applicant.householdAddress = address
                        model.draft.applicant.isHsinchuResident = address.contains("新竹市")
                        for district in ["東區", "北區", "香山區"] where address.contains(district) {
                            model.draft.formFields.householdDistrict = district
                        }
                    }
                    if let postalCode = found.postalCode { model.draft.formFields.householdPostalCode = postalCode }
                    if found.isGeneratedSample {
                        model.attachSynthetic(.idFront)
                        model.attachSynthetic(.idBack)
                    } else {
                        model.attachLocalPhoto(type: .idFront, data: found.imageData)
                        if let back = found.reverseImageData {
                            model.attachLocalPhoto(type: .idBack, data: back)
                        }
                    }
                    model.banner = "已帶入辨識到的證件欄位。請逐項核對；附件只存在手機內，尚未上傳或完成身分驗證。"
                }
            }
            Section("申請人") {
                Text("競賽原型只在手機內處理證件資料；辨識不代表身分驗證，也不會送到市府。")
                    .font(.footnote)
                SecureField("身分證字號", text: $model.draft.formFields.nationalID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("applicant.nationalID")
                LabeledField(title: "姓名", hint: "須與收據或帳單可辨識資訊一致。") {
                    TextField("申請人姓名", text: $model.draft.applicant.fullName)
                        .textContentType(.name)
                        .accessibilityIdentifier("applicant.fullName")
                }
                LabeledField(title: "出生日期", hint: "須為民國 74/4/3 至 99/4/2。畫面顯示民國年。") {
                    DatePicker(
                        "出生日期",
                        selection: $model.draft.applicant.birthDate,
                        in: ROCDate.birthMin...ROCDate.birthMax,
                        displayedComponents: .date
                    )
                    .accessibilityIdentifier("applicant.birthDate")
                    Text(ROCDate.display(model.draft.applicant.birthDate))
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                LabeledField(title: "電子郵件", hint: "請填寫申請人電子郵件。") {
                    TextField("name@example.test", text: $model.draft.applicant.contactEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("applicant.email")
                }
                LabeledField(title: "聯絡電話", hint: "請填寫可聯絡的電話。") {
                    TextField("0900-000-000", text: $model.draft.applicant.phone)
                        .keyboardType(.phonePad)
                        .accessibilityIdentifier("applicant.phone")
                }
            }
            Section("設籍與地址") {
                Text("戶籍縣市：新竹市")
                TextField("戶籍郵遞區號", text: $model.draft.formFields.householdPostalCode)
                    .keyboardType(.numberPad)
                Picker("戶籍行政區", selection: $model.draft.formFields.householdDistrict) {
                    Text("請選擇行政區").tag("")
                    ForEach(["東區", "北區", "香山區"], id: \.self) { Text($0).tag($0) }
                }
                Toggle("本人設籍新竹市", isOn: $model.draft.applicant.isHsinchuResident)
                    .accessibilityIdentifier("applicant.resident")
                LabeledField(title: "戶籍地址", hint: "須能與身分證影像辨識之新竹市住址對照。") {
                    TextField("新竹市…", text: $model.draft.applicant.householdAddress, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("applicant.address")
                }
            }
            Section("通訊地址") {
                Toggle("同戶籍地址", isOn: $model.draft.formFields.mailingSameAsHousehold)
                    .accessibilityIdentifier("applicant.sameAddress")
                if model.draft.formFields.mailingSameAsHousehold {
                    Text(model.draft.applicant.householdAddress.isEmpty ? "請先填寫戶籍地址" : model.draft.applicant.householdAddress)
                } else {
                    TextField("通訊郵遞區號", text: $model.draft.formFields.mailingPostalCode).keyboardType(.numberPad)
                    TextField("通訊縣市", text: $model.draft.formFields.mailingCity)
                    TextField("通訊行政區", text: $model.draft.formFields.mailingDistrict)
                    TextField("街道路段名、門牌號、樓層", text: $model.draft.formFields.mailingStreet, axis: .vertical)
                }
            }
            Section("身分類別") {
                Picker("身分類別", selection: $model.draft.applicant.identityCategory) {
                    ForEach(IdentityCategory.allCases, id: \.self) { category in
                        Text(category.zhTitle).tag(category)
                    }
                }
                .accessibilityIdentifier("applicant.category")
                if model.draft.applicant.identityCategory == .specialTarget {
                    ForEach(SpecialIdentityKind.allCases, id: \.self) { kind in
                        Toggle(kind.zhTitle, isOn: binding(for: kind))
                    }
                }
                if model.draft.applicant.identityCategory == .culturalLanguageKeeper {
                    ForEach(CulturalLanguageKind.allCases, id: \.self) { kind in
                        Toggle(kind.zhTitle, isOn: binding(for: kind))
                    }
                }
            }
            Section("帳戶備註（選填，非截圖必填欄位）") {
                TextField("金融機構名稱", text: $model.draft.applicant.bankName)
                    .accessibilityIdentifier("applicant.bankName")
                TextField("合成遮蔽帳號，勿填真實帳號", text: $model.draft.applicant.bankAccountMasked)
                    .accessibilityIdentifier("applicant.bankMasked")
                Text(model.draft.applicant.nationalIdPresenceNote)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func binding(for kind: SpecialIdentityKind) -> Binding<Bool> {
        Binding(
            get: { model.draft.applicant.specialIdentityKinds.contains(kind) },
            set: { isOn in
                if isOn {
                    model.draft.applicant.specialIdentityKinds.append(kind)
                } else {
                    model.draft.applicant.specialIdentityKinds.removeAll { $0 == kind }
                }
            }
        )
    }

    private func binding(for kind: CulturalLanguageKind) -> Binding<Bool> {
        Binding(
            get: { model.draft.applicant.culturalLanguageKinds.contains(kind) },
            set: { isOn in
                if isOn {
                    model.draft.applicant.culturalLanguageKinds.append(kind)
                } else {
                    model.draft.applicant.culturalLanguageKinds.removeAll { $0 == kind }
                }
            }
        )
    }
}

import XCTest
@testable import YouthAISubsidy

final class FormValidatorTests: XCTestCase {
    func testGeneralCaseBecomesValidAfterSyntheticDocuments() {
        var draft = SyntheticFixtures.fillableGeneral()
        XCTAssertFalse(FormValidator.issues(for: draft, step: .documents).isEmpty)
        draft.documents = Self.syntheticDocs(for: draft)
        let issues = FormValidator.issues(for: draft)
        XCTAssertTrue(issues.isEmpty, issues.map(\.message).joined(separator: "; "))
    }

    func testSpecialCaseRequiresIdentityProof() {
        var draft = SyntheticFixtures.fillableSpecial()
        draft.documents = Self.syntheticDocs(for: draft).filter { $0.type != .specialIdentityProof }
        let types = FormValidator.missingDocumentTypes(for: draft)
        XCTAssertTrue(types.contains(.specialIdentityProof))
    }

    func testProxyCaseRequiresExtraProofs() {
        var draft = SyntheticFixtures.fillableProxy()
        draft.documents = Self.syntheticDocs(for: draft).filter {
            $0.type != .kinshipProof && $0.type != .proxyPaymentAffidavit
        }
        let types = FormValidator.missingDocumentTypes(for: draft)
        XCTAssertTrue(types.contains(.kinshipProof))
        XCTAssertTrue(types.contains(.proxyPaymentAffidavit))
        draft.documents = Self.syntheticDocs(for: draft)
        let leftover = FormValidator.issues(for: draft)
        XCTAssertTrue(leftover.isEmpty, leftover.map(\.message).joined(separator: "; "))
    }

    func testAgeOutsideWindowIsRejected() {
        var draft = SyntheticFixtures.fillableGeneral()
        draft.applicant.birthDate = ROCDate.date(year: 1980, month: 1, day: 1)
        draft.documents = Self.syntheticDocs(for: draft)
        XCTAssertTrue(FormValidator.issues(for: draft).contains { $0.field == "applicant.birthDate" })
    }

    func testAggregatorChannelIsRejected() {
        var draft = SyntheticFixtures.fillableGeneral()
        draft.purchase.purchaseChannel = .aggregator
        draft.documents = Self.syntheticDocs(for: draft)
        XCTAssertTrue(FormValidator.issues(for: draft).contains { $0.field == "purchase.purchaseChannel" })
    }

    func testAwarenessStepDoesNotReplaceOfficialFields() {
        let draft = SubsidyCase.blank()
        XCTAssertTrue(FormValidator.issues(for: draft, step: .awareness).isEmpty)
        let reviewFields = Set(FormValidator.issues(for: draft, step: .review).map(\.field))
        XCTAssertTrue(reviewFields.contains("applicant.fullName"))
        XCTAssertTrue(reviewFields.contains("documents.idFront"))
        XCTAssertEqual(WizardStep.allCases.count, 5)
        XCTAssertEqual(WizardStep.allCases.map(\.self), [.applicant, .purchase, .documents, .awareness, .review])
    }

    func testRequiredOfficialFieldsAreNotOptional() {
        let draft = SubsidyCase.blank()
        let fields = Set(FormValidator.issues(for: draft).map(\.field))
        XCTAssertTrue(fields.contains("applicant.fullName"))
        XCTAssertTrue(fields.contains("applicant.isHsinchuResident"))
        XCTAssertTrue(fields.contains("purchase.toolName"))
        XCTAssertTrue(fields.contains("documents.idFront"))
        XCTAssertTrue(fields.contains("documents.signedAffidavit"))
    }

    private static func syntheticDocs(for draft: SubsidyCase) -> [CaseDocument] {
        FormValidator.requiredDocumentTypes(for: draft).map { type in
            CaseDocument(
                id: type.rawValue,
                type: type,
                fileName: "\(type.rawValue).png",
                localRelativePath: "\(type.rawValue).png",
                isSynthetic: true,
                attachedAt: Date()
            )
        }
    }

    func testScreenshotFieldsAreRequiredAndMailingCopyIsAllowed() throws {
        var draft = SyntheticFixtures.fillableGeneral()
        draft.formFields.nationalID = ""
        draft.formFields.mailingSameAsHousehold = false
        let missing = FormValidator.issues(for: draft, step: .applicant)
        XCTAssertTrue(missing.contains { $0.field == "applicant.nationalID" })
        XCTAssertTrue(missing.contains { $0.field == "applicant.mailingAddress" })
        draft.formFields = .synthetic
        XCTAssertTrue(FormValidator.issues(for: draft, step: .applicant).isEmpty)
        let data = try ContractJSON.encoder.encode(draft)
        let restored = try ContractJSON.decoder.decode(SubsidyCase.self, from: data)
        XCTAssertEqual(restored.formFields, draft.formFields)
    }

    func testReceiptChecklistAndMonthlyPeriodValidation() {
        var draft = SyntheticFixtures.fillableGeneral()
        draft.formFields.receiptConfirmations = []
        draft.purchase.subscriptionPlan = .monthly
        draft.formFields.monthlyPeriods = 0
        let issues = FormValidator.issues(for: draft, step: .purchase)
        XCTAssertEqual(issues.filter { $0.field.hasPrefix("purchase.receipt.") }.count, 8)
        XCTAssertTrue(issues.contains { $0.field == "purchase.monthlyPeriods" })
    }
}

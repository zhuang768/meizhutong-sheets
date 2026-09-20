import XCTest
import UIKit
@testable import YouthAISubsidy

final class CameraFrameCropTests: XCTestCase {
    func testGuideMapsToAspectFillImageRegion() {
        let rect = CameraFrameCrop.imageRect(
            imageSize: CGSize(width: 300, height: 400),
            previewSize: CGSize(width: 200, height: 400),
            guideRect: CGRect(x: 50, y: 100, width: 100, height: 200)
        )
        XCTAssertEqual(rect.origin.x, 100, accuracy: 0.01)
        XCTAssertEqual(rect.origin.y, 100, accuracy: 0.01)
        XCTAssertEqual(rect.width, 100, accuracy: 0.01)
        XCTAssertEqual(rect.height, 200, accuracy: 0.01)
    }

    func testGuideClampsToCapturedImage() {
        let rect = CameraFrameCrop.imageRect(
            imageSize: CGSize(width: 300, height: 400),
            previewSize: CGSize(width: 200, height: 400),
            guideRect: CGRect(x: -100, y: -50, width: 400, height: 500)
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 300, height: 400))
    }

    func testCapturedPhotoContainsOnlyVisibleGuide() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 100, y: 100, width: 100, height: 200))
        }
        let cropped = try XCTUnwrap(CameraFrameCrop.crop(image,
            previewSize: CGSize(width: 200, height: 400),
            guideRect: CGRect(x: 50, y: 100, width: 100, height: 200)))
        XCTAssertEqual(cropped.size, CGSize(width: 100, height: 200))
        let pixel = try XCTUnwrap(cropped.cgImage?.dataProvider?.data as Data?)
        XCTAssertGreaterThan(pixel.count, 0)
    }

    func testLandscapeSensorPhotoIsUprightBeforeCropping() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        let rotated = UIImage(cgImage: try XCTUnwrap(source.cgImage), scale: 1, orientation: .right)
        let cropped = try XCTUnwrap(CameraFrameCrop.crop(rotated,
            previewSize: CGSize(width: 300, height: 400),
            guideRect: CGRect(x: 50, y: 100, width: 200, height: 200)))
        XCTAssertEqual(cropped.size, CGSize(width: 200, height: 200))
        XCTAssertEqual(cropped.imageOrientation, .up)
    }
}

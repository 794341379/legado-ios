import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import LegadoCore

struct QRCodeDecoderTests {
    @Test func decodesActualPNGQRCodeAndResolvesImportPayload() throws {
        let payload = "legado://import/bookSource?src=https%3A%2F%2Fexample.test%2Fsources.json"
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        let output = try #require(filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)))
        let image = try #require(CIContext().createCGImage(output, from: output.extent))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let values = try QRCodeDecoder().detect(in: data as Data)
        #expect(values == [payload])
        #expect(try RuleImportInput.parse(values[0]) == .remote(URL(string: "https://example.test/sources.json")!, withoutUserAgent: false))
    }

    @Test func invalidImageReportsDecodeFailure() {
        #expect(throws: (any Error).self) { try QRCodeDecoder().detect(in: Data("invalid image".utf8)) }
    }
}

import UIKit
import WebKit
import XCTest
@testable import Legado

@MainActor
final class WebReaderBridgeTests: XCTestCase {
    func testPageJavaScriptCanStoreVariablesAndEvaluateContentRules() async throws {
        let source = RssSource(sourceUrl: "https://bridge-regression.test/\(UUID().uuidString)", sourceName: "测试")
        let loaded = expectation(description: "HTML loaded")
        let surface = RSSWebReaderView(mode: .html(content: "<p>页面正文</p>", baseURL: source.sourceUrl), source: source,
                                       onTextChange: { _ in loaded.fulfill() })
        let coordinator = surface.makeCoordinator()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(coordinator, name: "legado")
        configuration.userContentController.addUserScript(.init(source: coordinator.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        let window = UIWindow(frame: webView.frame)
        let controller = UIViewController()
        controller.view.addSubview(webView)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            RSSWebReaderView.dismantleUIView(webView, coordinator: coordinator)
            window.isHidden = true
        }
        coordinator.installRulesAndLoad(mode: surface.mode, in: webView)
        await fulfillment(of: [loaded], timeout: 20)

        let result = try await webView.evaluateJavaScript("""
            java.put('key', '已保存');
            java.setContent('<div><p>规则正文</p></div>');
            [java.get('key'), java.getString('tag.p@text')].join('|');
            """)
        XCTAssertEqual(result as? String, "已保存|规则正文")
    }
}

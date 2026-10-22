import UIKit
import WebKit
import XCTest
@testable import Legado

@MainActor
final class WebReaderBridgeTests: XCTestCase {
    func testGeneratedRSSContentFollowsAppearanceWithoutReloading() async throws {
        let source = RssSource(sourceUrl: "https://appearance-regression.test", sourceName: "测试")
        let loaded = expectation(description: "HTML loaded")
        let surface = RSSWebReaderView(
            mode: .html(content: "<body><p>订阅正文</p><a href='#'>链接</a><button>操作</button></body>", baseURL: nil),
            source: source, onTextChange: { _ in loaded.fulfill() }
        )
        let coordinator = surface.makeCoordinator()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        webView.navigationDelegate = coordinator
        let window = UIWindow(frame: webView.frame)
        let controller = UIViewController()
        controller.overrideUserInterfaceStyle = .dark
        controller.view.addSubview(webView)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            RSSWebReaderView.dismantleUIView(webView, coordinator: coordinator)
            window.isHidden = true
        }
        coordinator.installRulesAndLoad(mode: surface.mode, in: webView)
        await fulfillment(of: [loaded], timeout: 20)
        let appearanceScript = """
        [matchMedia('(prefers-color-scheme:dark)').matches,
         getComputedStyle(document.body).backgroundColor,
         getComputedStyle(document.body).color,
         getComputedStyle(document.querySelector('a')).color,
         getComputedStyle(document.documentElement).colorScheme].map(String).join('|')
        """
        let dark = try await webView.evaluateJavaScript(appearanceScript)
        XCTAssertEqual(dark as? String, "true|rgb(17, 17, 19)|rgb(242, 242, 242)|rgb(158, 203, 255)|light dark")
        _ = try await webView.evaluateJavaScript("window.appearanceMarker = 'preserved'")
        controller.overrideUserInterfaceStyle = .light
        window.layoutIfNeeded()
        XCTAssertEqual(webView.traitCollection.userInterfaceStyle, .light)
        var light = try await webView.evaluateJavaScript(appearanceScript)
        for _ in 0..<50 {
            if (light as? String)?.hasPrefix("false|") == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
            light = try await webView.evaluateJavaScript(appearanceScript)
        }
        XCTAssertEqual(light as? String, "false|rgb(252, 252, 252)|rgb(23, 23, 23)|rgb(0, 0, 238)|light dark")
        let marker = try await webView.evaluateJavaScript("window.appearanceMarker")
        XCTAssertEqual(marker as? String, "preserved")
        // A source may intentionally override the generated article palette.
        _ = try await webView.evaluateJavaScript("document.head.insertAdjacentHTML('beforeend', '<style>body{color:rgb(120,30,40)}</style>')")
        let custom = try await webView.evaluateJavaScript("getComputedStyle(document.body).color")
        XCTAssertEqual(custom as? String, "rgb(120, 30, 40)")
    }

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

import XCTest

@MainActor
final class RuleEditorUITests: XCTestCase {
    func testSourceFormJSONSwitchKeepsHighlightedTextAndSaves() throws {
        try exerciseSourceEditor(usesLegacyUI: false)
    }

    func testLegacySourceFormJSONSwitchKeepsHighlightedTextAndSaves() throws {
        try exerciseSourceEditor(usesLegacyUI: true)
    }

    private func exerciseSourceEditor(usesLegacyUI: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiDemo", "-uiDemoTab", "sources"]
        if usesLegacyUI { app.launchArguments.append("-uiLegacyCompatibility") }
        app.launch()
        XCTAssertTrue(app.navigationBars["书源"].waitForExistence(timeout: 20))
        app.buttons["更多"].firstMatch.tap()
        app.buttons["新建书源"].tap()
        XCTAssertTrue(app.navigationBars["新建书源"].waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "书源名称")).firstMatch.tap()
        let editor = app.textViews["syntaxCodeEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText("UI Source")
        attach(app, name: "Typed source name")
        XCTAssertEqual(editor.value as? String, "UI Source")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "书源地址")).firstMatch.tap()
        editor.tap(); editor.typeText("https://ui-editor.test")
        XCTAssertEqual(editor.value as? String, "https://ui-editor.test")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.segmentedControls.buttons["JSON"].tap()
        attach(app, name: "Source JSON editor")
        let json = editor.value as? String ?? ""
        XCTAssertTrue(json.contains("UI Source"), "Actual JSON: \(json)")
        XCTAssertTrue(json.contains("https://ui-editor.test"), "Actual JSON: \(json)")
        app.segmentedControls.buttons["字段编辑"].tap()
        app.buttons["保存"].tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 5) { app.alerts.buttons["好"].tap() }
        XCTAssertTrue(app.staticTexts["UI Source"].waitForExistence(timeout: 10))
    }

    func testPurificationDraftRunsThroughReaderPipeline() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiDemo", "-uiDemoTab", "settings", "-uiDemoRules"]
        app.launch()
        XCTAssertTrue(app.buttons["新建规则"].waitForExistence(timeout: 20))
        app.buttons["新建规则"].tap()
        app.textFields["名称"].tap(); app.textFields["名称"].typeText("UI Rule")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "匹配内容")).firstMatch.tap()
        let editor = app.textViews["syntaxCodeEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText(".")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.segmentedControls.buttons["测试规则"].tap()
        app.buttons["运行当前草稿"].tap()
        XCTAssertTrue(app.staticTexts["规则已生效"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["（正文为空）"].exists)
        attach(app, name: "Purification test result")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["净化规则"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["UI Rule"].exists)
    }

    func testLegacySearchSubmitsAndFiltersSources() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiDemo", "-uiDemoTab", "search", "-uiLegacyCompatibility"]
        app.launch()
        let search = app.textFields["书名或作者"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        app.buttons["搜索选项"].tap()
        app.buttons["分组或书源"].tap()
        XCTAssertTrue(app.navigationBars["分组或书源"].waitForExistence(timeout: 10))
        app.segmentedControls.buttons["书源"].tap()
        let filter = app.textFields["筛选书源"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        filter.typeText("no-match")
        XCTAssertFalse(app.staticTexts["经典文学馆"].exists)
        app.navigationBars["分组或书源"].buttons["取消"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("legacy-probe\n")
        XCTAssertTrue(app.buttons["修改关键词"].waitForExistence(timeout: 30))
        app.buttons["修改关键词"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        attach(app, name: "Legacy search after keyboard submission")
    }

    func testLegacyAboutCanPresentSystemShareSheet() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiDemo", "-uiDemoTab", "settings", "-uiDemoAbout", "-uiLegacyCompatibility"]
        app.launch()
        let share = app.buttons["分享版本信息"]
        XCTAssertTrue(share.waitForExistence(timeout: 20))
        share.tap()
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Copy", "拷贝", "复制"])).firstMatch
        let appeared = copy.waitForExistence(timeout: 10)
        if !appeared { print("[Share sheet hierarchy] \(app.debugDescription)") }
        XCTAssertTrue(appeared)
        attach(app, name: "Legacy system share sheet")
    }

    func testLegacyRuleMenuCanExportThroughSystemShareSheet() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiDemo", "-uiDemoTab", "settings", "-uiDemoRules", "-uiLegacyCompatibility"]
        app.launch()
        XCTAssertTrue(app.navigationBars["净化规则"].waitForExistence(timeout: 20))
        app.buttons["更多"].tap()
        app.buttons["导出全部规则"].tap()
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Copy", "拷贝", "复制"])).firstMatch
        let appeared = copy.waitForExistence(timeout: 10)
        if !appeared { print("[Share sheet hierarchy] \(app.debugDescription)") }
        XCTAssertTrue(appeared)
        attach(app, name: "Legacy rule menu export")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

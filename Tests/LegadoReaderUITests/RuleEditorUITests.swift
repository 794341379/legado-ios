import XCTest

@MainActor
final class RuleEditorUITests: XCTestCase {
    func testJSONFilePickerOffersOpenAndImportsSelectedFiles() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiDemo", "-uiDemoTab", "sources"]
        app.launch()
        XCTAssertTrue(app.navigationBars["书源"].waitForExistence(timeout: 20))
        app.buttons["更多"].firstMatch.tap()
        app.buttons["从文件导入"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        let pickerClosed = expectation(for: NSPredicate { _, _ in
            !cancel.exists && app.navigationBars["书源"].buttons["更多"].isHittable
        }, evaluatedWith: nil)
        wait(for: [pickerClosed], timeout: 10)
        app.buttons["更多"].firstMatch.tap()
        app.buttons["从文件导入"].tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))

        let json = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "JSON-Source")).firstMatch
        let fixtures = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "书源导入测试")).firstMatch
        if !json.waitForExistence(timeout: 3) {
            if !fixtures.exists {
                let browse = app.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "浏览", "Locations", "位置"])).firstMatch
                if browse.exists { browse.tap() }
                if !fixtures.waitForExistence(timeout: 2) {
                    let local = app.descendants(matching: .any).matching(NSPredicate(
                        format: "label CONTAINS %@ OR label CONTAINS %@ OR label == %@", "我的 iPhone", "我的iPhone", "On My iPhone"
                    )).firstMatch
                    if !local.waitForExistence(timeout: 5) { print("[SourceFilePicker] \(app.debugDescription)") }
                    XCTAssertTrue(local.exists)
                    local.tap()
                }
            }
            XCTAssertTrue(fixtures.waitForExistence(timeout: 10), "Run sh scripts/prepare-source-import-fixture.sh <simulator-UUID> before this test")
            fixtures.tap()
        }
        XCTAssertTrue(json.waitForExistence(timeout: 10))
        json.tap()
        let uppercase = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "JSON-Uppercase")).firstMatch
        XCTAssertTrue(uppercase.waitForExistence(timeout: 5))
        uppercase.tap()
        let open = app.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "打开", "Import", "导入"])).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(open.isEnabled)
        attach(app, name: "JSON files selected with Open available")
        open.tap()

        let reviewAppeared = app.navigationBars["书源导入预检"].waitForExistence(timeout: 15)
        if !reviewAppeared {
            print("[SourceFilePickerAfterOpen] \(app.debugDescription)")
            attach(app, name: "File picker after Open")
        }
        XCTAssertTrue(reviewAppeared)
        XCTAssertTrue(app.buttons["导入"].isEnabled)
        attach(app, name: "JSON import review after file picker dismissal")
        app.buttons["导入"].tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 5) { app.alerts.buttons["好"].tap() }
        XCTAssertTrue(app.staticTexts["文件导入 JSON 测试"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["文件导入大写扩展名测试"].exists)
    }

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

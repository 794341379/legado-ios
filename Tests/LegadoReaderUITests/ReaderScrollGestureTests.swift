import XCTest

@MainActor
final class ReaderScrollGestureTests: XCTestCase {
    func testFailedChaptersAllowRetryMenuAndSourceSwitchInBothReadingModes() throws {
        continueAfterFailure = false
        for mode in ["3", "0"] {
            let app = XCUIApplication()
            app.launchArguments = ["-uiDemo", "-uiDemoReader", "-uiReaderFailure", "-pageAnim", mode, "-themeMode", "0"]
            app.launch()
            let retry = app.buttons["reader.retryChapter"]
            XCTAssertTrue(retry.waitForExistence(timeout: 20))
            retry.tap()
            XCTAssertTrue(app.buttons["reader.failureChangeSource"].waitForExistence(timeout: 10))
            app.buttons["reader.failureChangeSource"].tap()
            XCTAssertTrue(app.navigationBars["为《长夜里的灯》换源"].waitForExistence(timeout: 10))
            app.buttons["取消"].tap()
            XCTAssertTrue(retry.waitForExistence(timeout: 10))
            if mode == "3" {
                app.collectionViews["reader.continuous"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
            } else {
                app.buttons["reader.failureMenu"].tap()
            }
            let changeSource = app.buttons["reader.changeSource"]
            XCTAssertTrue(changeSource.waitForExistence(timeout: 5))
            changeSource.tap()
            XCTAssertTrue(app.navigationBars["为《长夜里的灯》换源"].waitForExistence(timeout: 10))
            attachScreenshot(app)
            app.terminate()
        }
    }

    func testPagedReadingReportsPageCountAndTurnsWithinTheSameChapter() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiDemo", "-uiDemoReader", "-uiScrollRegression", "-uiPagingDiagnostics", "-pageAnim", "4", "-themeMode", "1", "-tipFooterRight", "6", "-textSize", "28"]
        app.launch()
        let body = app.textViews["reader.text"]
        XCTAssertTrue(body.waitForExistence(timeout: 20))
        let page = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+/[0-9]+.*")).firstMatch
        let ready = expectation(for: NSPredicate { _, _ in
            print("[PagedReader] \(body.label) footer=\(page.label)")
            let total = page.label.split(separator: "/").last?.split(separator: " ").first.flatMap { Int($0) } ?? 0
            return page.exists && page.label.hasPrefix("1/") && total > 1
        }, evaluatedWith: nil)
        wait(for: [ready], timeout: 10)
        let chapter = body.value as? String
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        let next = expectation(for: NSPredicate { _, _ in page.label.hasPrefix("2/") }, evaluatedWith: nil)
        wait(for: [next], timeout: 5)
        XCTAssertEqual(body.value as? String, chapter)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        let previous = expectation(for: NSPredicate { _, _ in page.label.hasPrefix("1/") }, evaluatedWith: nil)
        wait(for: [previous], timeout: 5)
        XCTAssertEqual(body.value as? String, chapter)
        attachScreenshot(app)
    }

    func testPagedReadingChapterNavigationDirectorySearchAndSettings() throws {
        try exerciseChapterNavigationAndSettings(usesLegacyUI: false)
    }

    func testLegacyReadingChapterNavigationDirectorySearchAndPhotoPicker() throws {
        try exerciseChapterNavigationAndSettings(usesLegacyUI: true)
    }

    private func exerciseChapterNavigationAndSettings(usesLegacyUI: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiDemo", "-uiDemoReader", "-pageAnim", "0", "-themeMode", "1"]
        if usesLegacyUI { app.launchArguments.append("-uiLegacyCompatibility") }
        app.launch()
        let body = app.textViews["reader.text"]
        XCTAssertTrue(body.waitForExistence(timeout: 20))
        func waitForChapter(_ title: String) {
            let ready = expectation(for: NSPredicate { _, _ in
                (body.value as? String ?? "").contains(title)
            }, evaluatedWith: nil)
            wait(for: [ready], timeout: 15)
        }
        func showMenu() {
            if !app.buttons["目录"].exists {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            XCTAssertTrue(app.buttons["目录"].waitForExistence(timeout: 5))
        }
        waitForChapter("第一章 · 雨夜")
        showMenu()
        XCTAssertFalse(app.buttons["上一章"].isEnabled)
        app.buttons["下一章"].tap()
        waitForChapter("第二章 · 灯塔")
        showMenu()
        app.buttons["上一章"].tap()
        waitForChapter("第一章 · 雨夜")

        showMenu()
        app.buttons["目录"].tap()
        XCTAssertTrue(app.navigationBars["目录"].waitForExistence(timeout: 5))
        let chapterSearch = app.searchFields["搜索章节"]
        chapterSearch.tap()
        chapterSearch.typeText("天明")
        app.staticTexts["第五章 · 天明"].tap()
        waitForChapter("第五章 · 天明")
        showMenu()
        XCTAssertFalse(app.buttons["下一章"].isEnabled)

        app.buttons["更多"].tap()
        app.buttons["搜索正文"].tap()
        XCTAssertTrue(app.navigationBars["正文搜索"].waitForExistence(timeout: 5))
        let contentSearch = app.searchFields["搜索本章"]
        contentSearch.tap()
        contentSearch.typeText("灯塔")
        let match = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "林深推开阁楼的窗")).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 5))
        match.tap()
        XCTAssertFalse(app.navigationBars["正文搜索"].exists)

        showMenu()
        app.buttons["书签"].tap()
        app.buttons["更多"].tap()
        app.buttons["书签列表"].tap()
        XCTAssertTrue(app.navigationBars["书签"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["第五章 · 天明"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()

        showMenu()
        app.buttons["外观"].tap()
        XCTAssertTrue(app.navigationBars["阅读样式"].waitForExistence(timeout: 5))
        if usesLegacyUI {
            app.buttons["选择背景图片"].tap()
            let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            cancel.tap()
            XCTAssertTrue(app.navigationBars["阅读样式"].waitForExistence(timeout: 5))
        }
        app.buttons["完成"].tap()
        showMenu()
        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["阅读设置"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        waitForChapter("第五章 · 天明")
        attachScreenshot(app)
    }

    func testForwardAndReverseFlicksKeepMomentumAcrossChapterInsertion() throws {
        let (app, reader) = launchReader(shortChapters: false)
        let initial = try value("chapter", in: reader)
        for _ in 0..<6 { flick(reader, forward: true) }
        let forward = try value("chapter", in: reader)
        XCTAssertGreaterThan(forward, initial + 2)
        for _ in 0..<6 { flick(reader, forward: false) }
        XCTAssertLessThan(try value("chapter", in: reader), forward)
        XCTAssertGreaterThan(try value("decelInsertions", in: reader), 0)
        XCTAssertGreaterThan(try value("continued", in: reader), 0)
        XCTAssertEqual(try value("interrupted", in: reader), 0)
        attachScreenshot(app)
    }

    func testManyShortChaptersFlowPastTheInitialWindow() throws {
        let (app, reader) = launchReader(shortChapters: true)
        let initial = try value("chapter", in: reader)
        for _ in 0..<4 { flick(reader, forward: true) }
        let forward = try value("chapter", in: reader)
        XCTAssertGreaterThan(forward, initial + 5)
        for _ in 0..<4 { flick(reader, forward: false) }
        XCTAssertLessThan(try value("chapter", in: reader), forward)
        XCTAssertEqual(try value("interrupted", in: reader), 0)
        attachScreenshot(app)
    }

    private func launchReader(shortChapters: Bool) -> (XCUIApplication, XCUIElement) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiDemo", "-uiDemoReader", "-uiScrollRegression", "-pageAnim", "3", "-themeMode", "0"]
        if shortChapters { app.launchArguments.append("-uiShortChapters") }
        app.launch()
        let reader = app.collectionViews["reader.continuous"]
        XCTAssertTrue(reader.waitForExistence(timeout: 20))
        let ready = expectation(for: NSPredicate { _, _ in
            let text = reader.value as? String ?? ""
            return text.contains("chapter=20 ") && !text.contains("chapters=1 ")
        }, evaluatedWith: nil)
        wait(for: [ready], timeout: 20)
        return (app, reader)
    }

    private func flick(_ reader: XCUIElement, forward: Bool) {
        let start = reader.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: forward ? 0.8 : 0.2))
        let end = reader.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: forward ? 0.2 : 0.8))
        start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func value(_ name: String, in reader: XCUIElement) throws -> Int {
        let fields = (reader.value as? String ?? "").split(separator: " ")
        let field = try XCTUnwrap(fields.first { $0.hasPrefix(name + "=") })
        let value = try XCTUnwrap(Int(field.dropFirst(name.count + 1)))
        print("[ContinuousReader] \(reader.value ?? "")")
        return value
    }

    private func attachScreenshot(_ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

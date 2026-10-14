import SwiftUI
import UIKit
import XCTest
@testable import Legado

@MainActor
final class ReaderScrollGeometryTests: XCTestCase {
    func testPrependingAndRecyclingStayWithinOnePhysicalPixel() async throws {
        let chapters = (4...6).map { chapter($0) }
        let fixture = host(chapters: chapters, active: 5)
        defer { fixture.coordinator.displayLink?.invalidate(); fixture.window.isHidden = true }
        let coordinator = fixture.coordinator, view = fixture.view
        let layout = view.collectionViewLayout as! ReaderContinuousLayout
        let row = try XCTUnwrap(coordinator.blocks.firstIndex { $0.chapter.chapter.id == 5 })
        let id = coordinator.blocks[row].id
        view.setContentOffset(CGPoint(x: 0, y: layout.frames[row].minY + 71.25), animated: false)
        let screenY = layout.frames[row].minY - view.contentOffset.y
        let chapterLayout = coordinator.blocks[row].chapter

        coordinator.parent = surface(chapters: [chapter(2), chapter(3)] + chapters, active: 5)
        coordinator.update(view)
        let insertedRow = try XCTUnwrap(coordinator.blocks.firstIndex { $0.id == id })
        XCTAssertEqual(layout.frames[insertedRow].minY - view.contentOffset.y, screenY, accuracy: 1 / fixture.window.screen.scale)
        XCTAssertTrue(coordinator.blocks[insertedRow].chapter === chapterLayout)

        coordinator.parent = surface(chapters: [chapter(5), chapter(6), chapter(7)], active: 5)
        coordinator.update(view)
        let recycledRow = try XCTUnwrap(coordinator.blocks.firstIndex { $0.id == id })
        XCTAssertEqual(layout.frames[recycledRow].minY - view.contentOffset.y, screenY, accuracy: 1 / fixture.window.screen.scale)
        XCTAssertTrue(coordinator.blocks[recycledRow].chapter === chapterLayout)
    }

    func testAppendingAndNaturalChapterChangesDoNotRebuildVisibleText() async throws {
        let chapters = (0...2).map { chapter($0) }
        let fixture = host(chapters: chapters, active: 0)
        defer { fixture.coordinator.displayLink?.invalidate(); fixture.window.isHidden = true }
        let coordinator = fixture.coordinator, view = fixture.view
        let original = try XCTUnwrap(coordinator.blocks.first?.chapter)
        view.setContentOffset(CGPoint(x: 0, y: 123.75), animated: false)
        let offset = view.contentOffset
        coordinator.parent = surface(chapters: chapters + [chapter(3), chapter(4)], active: 1)
        coordinator.update(view)
        XCTAssertEqual(view.contentOffset.y, offset.y, accuracy: 0.01)
        XCTAssertTrue(coordinator.blocks[0].chapter === original)
        XCTAssertEqual(Set(coordinator.blocks.map { $0.chapter.chapter.id }), Set(0...4))
    }

    func testReflowKeepsTheSameTextLineAtTheSameScreenPosition() async throws {
        let fixture = host(chapters: [chapter(0), chapter(1)], active: 0)
        defer { fixture.coordinator.displayLink?.invalidate(); fixture.window.isHidden = true }
        let coordinator = fixture.coordinator, view = fixture.view
        let old = try XCTUnwrap(coordinator.blocks.first?.chapter)
        let glyph = old.manager.glyphIndexForCharacter(at: old.bodyStart + 200)
        let lineY = old.manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        let startOfLine = old.manager.characterIndexForGlyph(at: old.manager.glyphIndex(
            for: CGPoint(x: 0, y: lineY + 0.5), in: old.container))
        let layout = view.collectionViewLayout as! ReaderContinuousLayout
        let chapterY = layout.frames[0].minY
        view.setContentOffset(CGPoint(x: 0, y: chapterY + lineY + 3.25), animated: false)
        let previousScreenY = chapterY + lineY - view.contentOffset.y
        coordinator.parent = surface(chapters: [chapter(0), chapter(1)], active: 0, fontSize: 25)
        coordinator.update(view)
        let new = try XCTUnwrap(coordinator.blocks.first?.chapter)
        let newGlyph = new.manager.glyphIndexForCharacter(at: startOfLine)
        let newLineY = new.manager.lineFragmentRect(forGlyphAt: newGlyph, effectiveRange: nil).minY
        XCTAssertEqual(layout.frames[0].minY + newLineY - view.contentOffset.y, previousScreenY, accuracy: 1 / fixture.window.screen.scale)
    }

    func testChunksCoverAllGlyphsAndDoNotRetainTheirChapter() async {
        weak var released: ReaderScrollChapterLayout?
        autoreleasepool {
            let layout = ReaderScrollChapterLayout(chapter: chapter(0), configuration: configuration(), width: 390)
            released = layout
            XCTAssertGreaterThan(layout.blocks.count, 2)
            var nextGlyph = 0
            for block in layout.blocks {
                XCTAssertEqual(block.glyphRange.location, nextGlyph)
                XCTAssertGreaterThan(block.height, 0)
                nextGlyph = NSMaxRange(block.glyphRange)
            }
            XCTAssertEqual(nextGlyph, layout.manager.numberOfGlyphs)
            XCTAssertTrue(layout.storage.string.contains("👨‍👩‍👧‍👦"))
        }
        XCTAssertNil(released, "Recycled TextKit chapter layouts must be released")
    }

    func testShortLastChapterCanReachTheTopWithoutChangingTheRequestedChapter() async throws {
        let short = ReaderScrollChapter(id: 8, title: "短章", content: "仅一行正文")
        let fixture = host(chapters: [chapter(7), short], active: 8)
        defer { fixture.coordinator.displayLink?.invalidate(); fixture.window.isHidden = true }
        let layout = fixture.view.collectionViewLayout as! ReaderContinuousLayout
        let row = try XCTUnwrap(fixture.coordinator.blocks.firstIndex { $0.chapter.chapter.id == 8 })
        XCTAssertEqual(fixture.view.contentOffset.y, layout.frames[row].minY, accuracy: 1 / fixture.window.screen.scale)
    }

    private func chapter(_ index: Int) -> ReaderScrollChapter {
        .init(id: index, title: "第\(index)章", content: String(repeating: "正文包含中文、英文 words 与家庭表情👨‍👩‍👧‍👦，用于验证连续阅读的排版和位置。\n", count: 100))
    }

    private func host(chapters: [ReaderScrollChapter], active: Int) -> (window: UIWindow, view: ReaderScrollCollectionView, coordinator: ReaderScrollView.Coordinator) {
        let parent = surface(chapters: chapters, active: active)
        let coordinator = parent.makeCoordinator()
        let view = coordinator.makeView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        controller.view.addSubview(view)
        view.frame = window.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        coordinator.update(view)
        view.layoutIfNeeded()
        return (window, view, coordinator)
    }

    private func surface(chapters: [ReaderScrollChapter], active: Int, fontSize: Double = 20) -> ReaderScrollView {
        .init(configuration: configuration(fontSize: fontSize), chapters: chapters,
              resetID: 0, activeIndex: active, loadingAhead: false, loadingBehind: false,
              onNeedChapters: { _ in }, onPositionChanged: { _, _ in },
              onRetainChapters: { _ in }, onRetry: { _ in })
    }

    private func configuration(fontSize: Double = 20) -> ReaderTextView {
        .init(text: "", title: "", previousTitle: nil, previousText: "", isPreviousReady: false,
              continuationTitle: nil, continuationText: "", isContinuationReady: false, isVolume: false,
              fontSize: fontSize, fontPath: "", letterSpacing: 0, lineSpacing: 8, paragraphSpacing: 12,
              paragraphIndent: "　　", paddingLeft: 20, paddingRight: 20, paddingTop: 16, paddingBottom: 16,
              headerInset: 0, footerInset: 0, fontWeight: 0, titleMode: 0, titleSize: 4,
              titleTopSpacing: 16, titleBottomSpacing: 24, underlineMode: 0, isSelectable: false,
              fullJustify: true, pageAnimation: 3, isEInkMode: false, clickActions: Array(repeating: 0, count: 9),
              backgroundColor: .white, foregroundColor: .black, requestedPosition: 0, jumpPosition: nil,
              renderRevision: 0, readerPosition: .constant(0), pageRanges: .constant([]),
              currentPage: .constant(1), totalPages: .constant(1), isAutoReading: false,
              isAutoReadPaused: false, isLoadingNextChapter: false, secondsPerScreen: 10,
              onReachedEnd: { _ in }, onReachedStart: { _ in }, onEnteredPrevious: { _ in },
              onEnteredContinuation: { _ in }, onDeferredRender: {}, onCancelNextLoading: {},
              onPageChanged: {}, onTapAction: { _ in })
    }
}

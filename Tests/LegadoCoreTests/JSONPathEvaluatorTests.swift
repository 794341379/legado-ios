import Foundation
import Testing
@testable import LegadoCore

struct JSONPathEvaluatorTests {
    private let evaluator = JSONPathEvaluator()

    private var fixture: JSONValue {
        get throws {
            try JSONValue.decode(data: Data(
                """
                {
                  "store": {
                    "books": [
                      {"title":"A","price":10,"tags":["x","y"]},
                      {"title":"B","price":20,"tags":["z"]},
                      {"title":"C","price":30,"tags":[]}
                    ]
                  },
                  "title":"Root"
                }
                """.utf8
            ))
        }
    }

    @Test func evaluatesChildrenWildcardsAndNegativeIndex() throws {
        #expect(try evaluator.evaluate(path: "$.store.books[*].title", in: fixture).map(\.stringValue) == ["A", "B", "C"])
        #expect(try evaluator.evaluate(path: "$.store.books[-1].title", in: fixture).map(\.stringValue) == ["C"])
    }

    @Test func evaluatesUnionSliceAndRecursiveDescent() throws {
        #expect(try evaluator.evaluate(path: "$.store.books[0,2].title", in: fixture).map(\.stringValue) == ["A", "C"])
        #expect(try evaluator.evaluate(path: "$.store.books[0:3:2].title", in: fixture).map(\.stringValue) == ["A", "C"])
        #expect(try evaluator.evaluate(path: "$..title", in: fixture).map(\.stringValue) == ["Root", "A", "B", "C"])
    }

    @Test func filtersByComparisonExistenceAndBooleanLogic() throws {
        #expect(try evaluator.evaluate(path: "$.store.books[?(@.price > 10)].title", in: fixture).map(\.stringValue) == ["B", "C"])
        #expect(try evaluator.evaluate(path: "$.store.books[?(@.price >= 20 && @.price < 30)].title", in: fixture).map(\.stringValue) == ["B"])
        #expect(try evaluator.evaluate(path: "$.store.books[?(@.tags[0])].title", in: fixture).map(\.stringValue) == ["A", "B"])
    }

    @Test func filtersByRegexRootReferenceAndNestedBrackets() throws {
        #expect(try evaluator.evaluate(path: "$.store.books[?(@.title =~ /a|b/i)].title", in: fixture).map(\.stringValue) == ["A", "B"])
        #expect(try evaluator.evaluate(path: "$.store.books[?(@.title != $.title && (@.price == 10 || @.price == 30))].title", in: fixture).map(\.stringValue) == ["A", "C"])
    }
}

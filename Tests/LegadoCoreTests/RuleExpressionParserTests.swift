import Testing
@testable import LegadoCore

struct RuleExpressionParserTests {
    private let parser = RuleExpressionParser()

    @Test func detectsModesAndReplacement() throws {
        let plan = try parser.parse("@Json:$.book.name##\\s+## ")

        #expect(plan.combination == .single)
        #expect(plan.branches.count == 1)
        #expect(plan.branches[0].mode == .jsonPath)
        #expect(plan.branches[0].expression == "$.book.name")
        #expect(plan.branches[0].replacePattern == "\\s+")
        #expect(plan.branches[0].replacement == " ")
    }

    @Test func doesNotSplitOperatorsInsideJSONPathFilter() throws {
        let plan = try parser.parse("$.books[?(@.enabled && @.score > 1)]||$.fallback")

        #expect(plan.combination == .fallback)
        #expect(plan.branches.count == 2)
        #expect(plan.branches[0].expression.contains("&&"))
    }

    @Test func rejectsUnbalancedRules() {
        #expect(throws: RuleEngineError.self) {
            try parser.parse("$.books[0")
        }
    }
}


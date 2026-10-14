import Foundation

public struct RegexLimits: Sendable {
    public var maximumInputLength: Int
    public var maximumPatternLength: Int
    public var maximumMatches: Int

    public init(
        maximumInputLength: Int = 2_000_000,
        maximumPatternLength: Int = 8_192,
        maximumMatches: Int = 10_000
    ) {
        self.maximumInputLength = maximumInputLength
        self.maximumPatternLength = maximumPatternLength
        self.maximumMatches = maximumMatches
    }
}

public struct RegexEvaluator: Sendable {
    public var limits: RegexLimits

    public init(limits: RegexLimits = .init()) {
        self.limits = limits
    }

    public func captureGroups(pattern: String, input: String) throws -> [[String]] {
        guard pattern.count <= limits.maximumPatternLength else {
            throw RuleEngineError.resourceLimit(rule: pattern, detail: "正则表达式超过长度限制")
        }
        guard input.utf16.count <= limits.maximumInputLength else {
            throw RuleEngineError.resourceLimit(rule: pattern, detail: "正则输入超过长度限制")
        }
        guard !hasObviousNestedQuantifier(pattern) else {
            throw RuleEngineError.resourceLimit(rule: pattern, detail: "正则包含高风险嵌套量词")
        }
        let expression: NSRegularExpression
        do {
            expression = try NSRegularExpression(pattern: pattern)
        } catch {
            throw RuleEngineError.malformedRule(rule: pattern, detail: error.localizedDescription)
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        var captures: [[String]] = []
        let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
        var timedOut = false
        expression.enumerateMatches(in: input, options: .reportProgress, range: range) { match, _, stop in
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                timedOut = true
                stop.pointee = true
                return
            }
            guard let match else { return }
            if captures.count >= limits.maximumMatches {
                stop.pointee = true
                return
            }
            captures.append((0 ..< match.numberOfRanges).map { group in
                let range = match.range(at: group)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: input) else { return "" }
                return String(input[swiftRange])
            })
        }
        if timedOut { throw RuleEngineError.resourceLimit(rule: pattern, detail: "正则匹配超时（3000 ms）") }
        if captures.count >= limits.maximumMatches {
            throw RuleEngineError.resourceLimit(rule: pattern, detail: "正则匹配数量超过限制")
        }
        return captures
    }

    public func replacing(
        pattern: String,
        in input: String,
        with replacement: String,
        firstOnly: Bool
    ) throws -> String {
        guard pattern.count <= limits.maximumPatternLength else {
            throw RuleEngineError.resourceLimit(rule: pattern, detail: "正则表达式超过长度限制")
        }
        guard input.utf16.count <= limits.maximumInputLength else {
            throw RuleEngineError.resourceLimit(rule: pattern, detail: "正则输入超过长度限制")
        }
        guard !hasObviousNestedQuantifier(pattern) else {
            throw RuleEngineError.resourceLimit(rule: pattern, detail: "正则包含高风险嵌套量词")
        }
        let expression: NSRegularExpression
        do {
            expression = try NSRegularExpression(pattern: pattern)
        } catch {
            if firstOnly { return replacement }
            return input.replacingOccurrences(of: pattern, with: replacement)
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        if firstOnly {
            let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
            var first: NSTextCheckingResult?
            var timedOut = false
            expression.enumerateMatches(in: input, options: .reportProgress, range: range) { match, _, stop in
                if DispatchTime.now().uptimeNanoseconds >= deadline {
                    timedOut = true
                    stop.pointee = true
                } else if let match {
                    first = match
                    stop.pointee = true
                }
            }
            if timedOut { throw RuleEngineError.resourceLimit(rule: pattern, detail: "正则匹配超时（3000 ms）") }
            guard let first else { return "" }
            return expression.replacementString(for: first, in: input, offset: 0, template: replacement)
        }
        return try replacingStrict(pattern: pattern, in: input, with: replacement)
    }

    public func replacingStrict(pattern: String, in input: String, with replacement: String,
                                timeoutMilliseconds: Int64 = 3_000) throws -> String {
        guard pattern.count <= limits.maximumPatternLength, input.utf16.count <= limits.maximumInputLength,
              !hasObviousNestedQuantifier(pattern) else {
            throw RuleEngineError.resourceLimit(rule: pattern, detail: "正则超过资源限制或包含高风险嵌套量词")
        }
        let expression: NSRegularExpression
        do { expression = try NSRegularExpression(pattern: pattern) }
        catch { throw RuleEngineError.malformedRule(rule: pattern, detail: error.localizedDescription) }
        let milliseconds = timeoutMilliseconds <= 0 ? 3_000 : min(timeoutMilliseconds, 60_000)
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(milliseconds) * 1_000_000
        let range = NSRange(location: 0, length: input.utf16.count)
        var matches: [NSTextCheckingResult] = []
        var timedOut = false
        var exceeded = false
        expression.enumerateMatches(in: input, options: .reportProgress, range: range) { match, _, stop in
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                timedOut = true
                stop.pointee = true
            } else if let match {
                if matches.count >= limits.maximumMatches { exceeded = true; stop.pointee = true }
                else { matches.append(match) }
            }
        }
        guard !timedOut else { throw RuleEngineError.resourceLimit(rule: pattern, detail: "正则替换超时（\(milliseconds) ms）") }
        guard !exceeded else { throw RuleEngineError.resourceLimit(rule: pattern, detail: "正则匹配数量超过限制") }
        let original = input as NSString
        var output = ""
        var offset = 0
        var outputLength = 0
        for match in matches {
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                throw RuleEngineError.resourceLimit(rule: pattern, detail: "正则替换超时（\(milliseconds) ms）")
            }
            let untouched = original.substring(with: NSRange(location: offset, length: match.range.location - offset))
            let replaced = expression.replacementString(for: match, in: input, offset: 0, template: replacement)
            output += untouched + replaced
            outputLength += untouched.utf16.count + replaced.utf16.count
            offset = NSMaxRange(match.range)
            guard outputLength <= limits.maximumInputLength * 2 else {
                throw RuleEngineError.resourceLimit(rule: pattern, detail: "替换结果超过长度限制")
            }
        }
        output += original.substring(from: offset)
        return output
    }

    private func hasObviousNestedQuantifier(_ pattern: String) -> Bool {
        let risky = #"\(((?:[^()\\]|\\.)*[+*](?:[^()\\]|\\.)*)\)([+*]|\{[^}]+\})"#
        guard let expression = try? NSRegularExpression(pattern: risky) else { return false }
        return expression.matches(in: pattern, range: NSRange(pattern.startIndex..., in: pattern)).contains { match in
            guard let innerRange = Range(match.range(at: 1), in: pattern),
                  let outerRange = Range(match.range(at: 2), in: pattern) else { return true }
            let inner = String(pattern[innerRange])
            let outer = String(pattern[outerRange])
            if outer.range(of: #"^\{[1-9]\}$"#, options: .regularExpression) != nil { return false }
            if !pattern.contains("(?s"),
               inner.range(of: #"^(?:\\n[^\[\]()*+?\\]*\.\*|\.\+\\n)$"#, options: .regularExpression) != nil { return false }
            return true
        }
    }
}

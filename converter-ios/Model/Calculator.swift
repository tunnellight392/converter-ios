import Foundation

/// Reads the arithmetic people type into a value field: "12*3", "(2+3)/4", "1 1/2", "1½".
///
/// Numbers inside an expression are read the same locale-aware way as a plain number, so
/// "1,5*2" is 3 in Germany. The evaluator is forgiving about half-typed input — a trailing
/// operator or unclosed parenthesis is ignored — so the other rows don't blank out mid-typing.
enum Calculator {

    /// The value of `text` as an arithmetic expression, or nil if it isn't one that works out to
    /// a finite number.
    static func evaluate(_ text: String, locale: Locale = .autoupdatingCurrent) -> Double? {
        var parser = Parser(tokens: tokenize(normalize(text), locale: locale))
        guard let tokens = parser.tokens, !tokens.isEmpty,
              let value = parser.expression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    // MARK: Normalizing

    private static let vulgarFractions: [Character: String] = [
        "½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4", "⅕": "1/5", "⅖": "2/5",
        "⅗": "3/5", "⅘": "4/5", "⅙": "1/6", "⅚": "5/6", "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8"
    ]

    /// Rewrite the shorthand into plain arithmetic: typographic operators to ASCII, "1½" and
    /// "1 1/2" (mixed numbers) to "(1+1/2)", and a half-typed ending trimmed off.
    private static func normalize(_ text: String) -> String {
        var s = ""
        for character in text {
            switch character {
            case "×", "·": s.append("*")
            case "÷": s.append("/")
            case "−", "–": s.append("-")
            default:
                if let fraction = vulgarFractions[character] {
                    // Directly after a digit (or a digit and a space) it's a mixed number.
                    let trimmed = s.trimmingCharacters(in: .whitespaces)
                    s = trimmed.last?.isNumber == true ? "\(trimmed)+(\(fraction))" : "\(s)(\(fraction))"
                } else {
                    s.append(character)
                }
            }
        }
        // "1 1/2" → "(1+1/2)": a whole number, a space, then a simple fraction.
        s = s.replacing(/(\d+)\s+(\d+)\s*\/\s*(\d+)/) { match in
            "(\(match.output.1)+\(match.output.2)/\(match.output.3))"
        }
        // Drop a trailing operator left while typing ("12*", "3+").
        while let last = s.last, "+-*/ ".contains(last) { s.removeLast() }
        return s
    }

    // MARK: Tokens

    private enum Token: Equatable {
        case number(Double)
        case op(Character)
        case open, close
    }

    /// Split into numbers, operators and parentheses, or nil if anything else turns up.
    private static func tokenize(_ s: String, locale: Locale) -> [Token]? {
        var tokens: [Token] = []
        var index = s.startIndex
        while index < s.endIndex {
            let character = s[index]
            if character.isWhitespace {
                index = s.index(after: index)
            } else if "+-*/".contains(character) {
                tokens.append(.op(character))
                index = s.index(after: index)
            } else if character == "(" {
                tokens.append(.open)
                index = s.index(after: index)
            } else if character == ")" {
                tokens.append(.close)
                index = s.index(after: index)
            } else if character.isNumber || character == "." || character == "," {
                // A number: digits and separators, plus an exponent ("1.5e-3").
                var end = index
                while end < s.endIndex, s[end].isNumber || s[end] == "." || s[end] == "," {
                    end = s.index(after: end)
                }
                if end < s.endIndex, s[end] == "e" || s[end] == "E" {
                    var exponentEnd = s.index(after: end)
                    if exponentEnd < s.endIndex, s[exponentEnd] == "+" || s[exponentEnd] == "-" {
                        exponentEnd = s.index(after: exponentEnd)
                    }
                    if exponentEnd < s.endIndex, s[exponentEnd].isNumber {
                        end = exponentEnd
                        while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
                    }
                }
                guard let value = UnitsRepository.parse(String(s[index..<end]), locale: locale) else { return nil }
                tokens.append(.number(value))
                index = end
            } else {
                return nil
            }
        }
        return tokens
    }

    // MARK: Parsing

    /// Recursive descent: expression = term (± term)*, term = factor (×÷ factor)*,
    /// factor = ±factor | number | (expression).
    private struct Parser {
        let tokens: [Token]?
        private var position = 0

        init(tokens: [Token]?) {
            self.tokens = tokens
        }

        var isAtEnd: Bool { position >= (tokens?.count ?? 0) }

        private var current: Token? {
            guard let tokens, position < tokens.count else { return nil }
            return tokens[position]
        }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while case .op(let op) = current, op == "+" || op == "-" {
                position += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        private mutating func term() -> Double? {
            guard var value = factor() else { return nil }
            while case .op(let op) = current, op == "*" || op == "/" {
                position += 1
                guard let rhs = factor() else { return nil }
                value = op == "*" ? value * rhs : value / rhs
            }
            return value
        }

        private mutating func factor() -> Double? {
            switch current {
            case .op("-"):
                position += 1
                return factor().map { -$0 }
            case .op("+"):
                position += 1
                return factor()
            case .number(let value):
                position += 1
                return value
            case .open:
                position += 1
                guard let value = expression() else { return nil }
                // An unclosed parenthesis at the very end is forgiven while typing.
                if current == .close {
                    position += 1
                } else if !isAtEnd {
                    return nil
                }
                return value
            default:
                return nil
            }
        }
    }
}

/// Reads heights and lengths written in feet and inches: 5'11", 5' 11", 5 ft 11 in, 6', 11".
/// Typographic marks (’ ” ′ ″), which iOS substitutes as you type, are accepted too.
enum FeetAndInches {

    /// The feet and inches in `text`, or nil if it isn't written that way. Either part may be
    /// missing, but not both.
    static func parse(_ text: String, locale: Locale = .autoupdatingCurrent) -> (feet: Double, inches: Double)? {
        let pattern = /^\s*(?:(?<feet>[0-9]+(?:[.,][0-9]*)?)\s*(?:feet|foot|ft|['’′])(?!['’′]))?\s*(?:(?<inches>[0-9]+(?:[.,][0-9]*)?)\s*(?:inches|inch|in|["”″“]|''|’’|′′))?\s*$/
            .ignoresCase()
        guard let match = text.wholeMatch(of: pattern) else { return nil }
        let feetText = match.output.feet.map(String.init)
        let inchesText = match.output.inches.map(String.init)
        guard feetText != nil || inchesText != nil else { return nil }
        guard let feet = feetText.map({ UnitsRepository.parse($0, locale: locale) }) ?? 0,
              let inches = inchesText.map({ UnitsRepository.parse($0, locale: locale) }) ?? 0 else { return nil }
        return (feet, inches)
    }
}

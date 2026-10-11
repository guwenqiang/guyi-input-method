import Foundation

/// Exact, bounded rational arithmetic. Unsupported or overflowing operations fail
/// instead of returning a rounded estimate. No code evaluation or network calls.
public enum Calculator {
    public enum Failure: Error, Equatable {
        case syntax, divisionByZero, overflow, exponent, tooLong
    }

    public static func evaluate(_ expression: String) throws -> String {
        guard expression.count <= 256 else { throw Failure.tooLong }
        var parser = Parser(expression)
        let result = try parser.sum()
        guard parser.index == parser.input.count else { throw Failure.syntax }
        let value = result.formatted
        return expression.contains(",") ? grouped(value) : value
    }

    public static func accepts(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { "0123456789.,+-*/^()×÷−".contains($0) }
    }

    public static func trailingExpression(in text: String) -> String {
        String(text.reversed().prefix { accepts(String($0)) }.reversed())
    }

    private static func grouped(_ value: String) -> String {
        value.split(separator: "/").map { part in
            let pieces = part.split(separator: ".", omittingEmptySubsequences: false)
            let negative = pieces[0].first == "-"
            let digits = Array(negative ? pieces[0].dropFirst() : pieces[0])
            var integer = negative ? "-" : ""
            for (index, digit) in digits.enumerated() {
                if index > 0, (digits.count - index) % 3 == 0 { integer += "," }
                integer.append(digit)
            }
            return integer + (pieces.count == 2 ? "." + pieces[1] : "")
        }.joined(separator: "/")
    }

    private static func checked(_ operation: (partialValue: Int64, overflow: Bool)) throws -> Int64 {
        guard !operation.overflow, operation.partialValue != .min else { throw Failure.overflow }
        return operation.partialValue
    }

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var a = abs(a), b = abs(b)
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }

    private struct Rational {
        let n: Int64
        let d: Int64
        init(_ numerator: Int64, _ denominator: Int64 = 1) throws {
            guard denominator != 0 else { throw Failure.divisionByZero }
            guard numerator != .min, denominator != .min else { throw Failure.overflow }
            let divisor = gcd(numerator, denominator)
            n = (denominator < 0 ? -numerator : numerator) / divisor
            d = abs(denominator) / divisor
        }
        func negated() throws -> Self { try Self(-n, d) }
        func adding(_ other: Self) throws -> Self {
            let divisor = gcd(d, other.d)
            let a = try checked(n.multipliedReportingOverflow(by: other.d / divisor))
            let b = try checked(other.n.multipliedReportingOverflow(by: d / divisor))
            let numerator = try checked(a.addingReportingOverflow(b))
            let cancellation = gcd(numerator, divisor)
            return try Self(numerator / cancellation,
                            checked((d / divisor).multipliedReportingOverflow(by: other.d / cancellation)))
        }
        func multiplied(_ other: Self) throws -> Self {
            let a = gcd(n, other.d), b = gcd(other.n, d)
            return try Self(checked((n / a).multipliedReportingOverflow(by: other.n / b)),
                            checked((d / b).multipliedReportingOverflow(by: other.d / a)))
        }
        func divided(_ other: Self) throws -> Self {
            guard other.n != 0 else { throw Failure.divisionByZero }
            return try multiplied(Self(other.d, other.n))
        }
        func power(_ exponent: Self) throws -> Self {
            guard exponent.d == 1, abs(exponent.n) <= 12 else { throw Failure.exponent }
            guard n != 0 || exponent.n != 0 else { throw Failure.syntax }
            var base = try exponent.n < 0 ? Self(d, n) : self
            var count = abs(exponent.n)
            var result = try Self(1)
            while count > 0 {
                if count % 2 == 1 { result = try result.multiplied(base) }
                count /= 2
                if count > 0 { base = try base.multiplied(base) }
            }
            return result
        }
        var formatted: String {
            guard d != 1 else { return String(n) }
            var factor = d
            for prime: Int64 in [2, 5] { while factor % prime == 0 { factor /= prime } }
            guard factor == 1 else { return "\(n)/\(d)" }
            let magnitude = UInt64(abs(n)), divisor = UInt64(d)
            var result = (n < 0 ? "-" : "") + String(magnitude / divisor)
            var remainder = magnitude % divisor
            if remainder != 0 { result += "." }
            while remainder != 0 {
                let step = divisor.dividingFullWidth(remainder.multipliedFullWidth(by: 10))
                result += String(step.quotient)
                remainder = step.remainder
            }
            return result
        }
    }

    private struct Parser {
        let input: [Character]
        var index = 0
        var depth = 0
        init(_ text: String) {
            input = Array(text.replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "−", with: "-"))
        }
        mutating func take(_ character: Character) -> Bool {
            guard index < input.count, input[index] == character else { return false }
            index += 1
            return true
        }
        mutating func sum() throws -> Rational {
            var value = try product()
            while index < input.count {
                if take("+") { value = try value.adding(product()) }
                else if take("-") { value = try value.adding(product().negated()) }
                else { break }
            }
            return value
        }
        mutating func product() throws -> Rational {
            var value = try unary()
            while index < input.count {
                if take("*") { value = try value.multiplied(unary()) }
                else if take("/") { value = try value.divided(unary()) }
                else { break }
            }
            return value
        }
        mutating func unary() throws -> Rational {
            depth += 1
            defer { depth -= 1 }
            guard depth <= 32 else { throw Failure.tooLong }
            if take("+") { return try unary() }
            if take("-") { return try unary().negated() }
            var value = try primary()
            if take("^") { value = try value.power(unary()) }
            return value
        }
        mutating func primary() throws -> Rational {
            if take("(") {
                let value = try sum()
                guard take(")") else { throw Failure.syntax }
                return value
            }
            let start = index
            var dot = false, digits = 0
            while index < input.count {
                let c = input[index]
                if ("0"..."9").contains(c) { digits += 1; index += 1 }
                else if c == ".", !dot { dot = true; index += 1 }
                else if c == ",", !dot { index += 1 }
                else { break }
            }
            guard digits > 0 else { throw Failure.syntax }
            var token = String(input[start..<index])
            if token.contains(",") {
                let integer = token.split(separator: ".", omittingEmptySubsequences: false)[0]
                let groups = integer.split(separator: ",", omittingEmptySubsequences: false)
                guard (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }) else { throw Failure.syntax }
                token.removeAll { $0 == "," }
            }
            if dot { while token.last == "0" { token.removeLast() } }
            let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
            var numerator: Int64 = 0, denominator: Int64 = 1
            for c in token where c != "." {
                numerator = try checked(checked(numerator.multipliedReportingOverflow(by: 10)).addingReportingOverflow(Int64(c.wholeNumberValue!)))
            }
            if pieces.count == 2 {
                for _ in pieces[1] { denominator = try checked(denominator.multipliedReportingOverflow(by: 10)) }
            }
            return try Rational(numerator, denominator)
        }
    }
}

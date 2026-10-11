import Foundation
import GuyiCore

func runCalculatorTests() throws {
    let examples = [
        "5/5": "1", "0.1+0.2": "0.3", "1/3": "1/3", "2/6": "1/3",
        "(2+3)*4": "20", "2+3*4": "14", "10-3-2": "5", "12/3/2": "2",
        "-2^2": "-4", "(-2)^2": "4", "2^3^2": "512", "2^-3": "0.125",
        "1/8": "0.125", "1/40": "0.025", "-1/2": "-0.5", "5/(-5)": "-1",
        "1/3+1/6": "0.5", "0.10+0.20": "0.3", "0/5": "0", "1.000": "1",
        "3,444+1": "3,445", "3,444.50/2": "1,722.25", "1,000,000-1": "999,999",
        "9007199254740993+1": "9007199254740994", "9223372036854775807/9223372036854775807": "1",
        "1/1000000000000000000": "0.000000000000000001", "3×4÷2": "6",
        "1.2": "1.2", "1/3-1/3": "0", "1--2": "3", "0.0000": "0"
    ]
    for (expression, expected) in examples {
        let actual = try Calculator.evaluate(expression)
        try check(actual == expected, "Exact calculator: " + expression)
    }
    try check(Calculator.trailingExpression(in: "5+5+5=15+5") == "15+5", "Chained calculations start at the last result")
    try check(Calculator.trailingExpression(in: "答案是5+5+5") == "5+5+5", "Calculation can recover the text before the caret")
    for expression in ["", ".", "5/0", "0/0", "0^0", "0^-1", "2^13", "2^0.5", "2**3", "1+", "(1+2", "1+2)", "3,44", "3.444,50", "1,,000", "1234,567", "1/2abc", "sqrt(4)", "1.2.3", "9223372036854775807+1", "9223372036854775807*2", "1/0.0000000000000000001", String(repeating: "(", count: 40) + "1" + String(repeating: ")", count: 40)] {
        do { _ = try Calculator.evaluate(expression); throw Failure.check("Calculator accepted invalid expression: " + expression) }
        catch is Calculator.Failure { print("PASS · Calculator rejects invalid, ambiguous or overflowing expression") }
    }
    // Compare a broad integer arithmetic range to Swift's independently evaluated values.
    for a in -20...20 {
        for b in -20...20 {
            for (op, result) in [("+", a+b), ("-", a-b), ("*", a*b)] {
                guard try Calculator.evaluate("(\(a))\(op)(\(b))") == String(result) else { throw Failure.check("Calculator integer grid") }
            }
        }
    }
    print("PASS · Calculator integer grid: 5,043 exact results")
}

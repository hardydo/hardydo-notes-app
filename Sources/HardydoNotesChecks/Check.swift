import Foundation

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var passes = 0

func check(_ condition: Bool, _ name: String, file: StaticString = #fileID, line: UInt = #line) {
    if condition {
        passes += 1
    } else {
        failures += 1
        print("FAIL \(name) (\(file):\(line))")
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String, file: StaticString = #fileID, line: UInt = #line) {
    check(actual == expected, "\(name): expected \(expected), got \(actual)", file: file, line: line)
}

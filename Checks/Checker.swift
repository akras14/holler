import AppKit
@testable import HollerKit

/// Minimal test runner: groups of named checks, failures reported with file and line.
@MainActor
final class Checker {
    private(set) var failures = 0
    private(set) var count = 0
    private var group = ""

    func group(_ name: String, _ body: @MainActor () -> Void) {
        group = name
        body()
    }

    func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String = "",
                              file: StaticString = #fileID, line: UInt = #line) {
        count += 1
        guard actual != expected else { return }
        failures += 1
        print("✘ \(group)\(label.isEmpty ? "" : " — \(label)") (\(file):\(line))")
        print("    got:      \(String(reflecting: actual))")
        print("    expected: \(String(reflecting: expected))")
    }
}

/// Spins the run loop until `condition` holds or the timeout passes.
@MainActor
@discardableResult
func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    return condition()
}

/// Runs async work to completion from a check, spinning the run loop meanwhile.
@MainActor
/// Returns nil, and prints why, if the work throws or times out.
func finish<T>(timeout: TimeInterval = 60, _ work: @escaping () async throws -> T) -> T? {
    var result: Result<T, Error>?
    Task { @MainActor in
        do { result = .success(try await work()) } catch { result = .failure(error) }
    }
    guard waitUntil(timeout: timeout, { result != nil }) else {
        print("    timed out after \(timeout)s")
        return nil
    }
    switch result! {
    case .success(let value): return value
    case .failure(let error): print("    threw: \(error)"); return nil
    }
}

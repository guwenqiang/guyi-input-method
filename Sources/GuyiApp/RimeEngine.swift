import Foundation
import CRimeBridge

final class RimeEngine {
    static let ready: Bool = {
        guard let shared = Bundle.main.resourceURL?.appendingPathComponent("Rime") else { return false }
        let user: URL
        if CommandLine.arguments.contains("--self-test") {
            user = FileManager.default.temporaryDirectory.appendingPathComponent("guyi-rime-test-" + UUID().uuidString)
        } else {
            user = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("guyi/Rime")
        }
        do { try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true) }
        catch { return false }
        return guyi_rime_start(shared.path, user.path) != 0
    }()
    let session: UInt
    init() { session = Self.ready ? guyi_rime_session() : 0 }
    deinit { guyi_rime_destroy(session) }
    var available: Bool { session != 0 }
    var page: Int { Int(guyi_rime_page(session)) }
    var lastPage: Bool { guyi_rime_last_page(session) != 0 }
    func highlight(_ index: Int) { guyi_rime_highlight(session, Int32(index)) }
    func key(_ key: Int32) -> Bool { guyi_rime_key(session, key) != 0 }
    func select(_ index: Int) { _ = guyi_rime_select(session, Int32(index)) }
    func clear() { guyi_rime_clear(session) }
    func learning(_ enabled: Bool) { guyi_rime_learning(session, enabled ? 1 : 0) }
    func finish() -> String { guyi_rime_finish(session); return commit() }
    func commit() -> String { take(guyi_rime_commit(session)) }
    var rawInput: String { take(guyi_rime_raw(session)) }
    func cursor(in preedit: String) -> Int {
        let byteOffset = max(0, min(Int(guyi_rime_cursor(session)), preedit.utf8.count))
        return String(decoding: preedit.utf8.prefix(byteOffset), as: UTF8.self).utf16.count
    }
    func state() -> (preedit: String, preview: String, selected: Int, candidates: [String]) {
        let parts = take(guyi_rime_state(session)).components(separatedBy: "\n")
        guard parts.count >= 3 else { return ("", "", 0, []) }
        return (parts[0], parts[1], Int(parts[2]) ?? 0, Array(parts.dropFirst(3)).filter { !$0.isEmpty })
    }
    private func take(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        defer { guyi_rime_free(pointer) }
        return String(cString: pointer)
    }
}

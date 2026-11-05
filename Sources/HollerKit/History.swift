import Foundation

/// The last few transcripts, newest first, kept between launches.
public final class History {
    public static let limit = 5
    static let key = "History"

    private let defaults: UserDefaults
    public private(set) var items: [String]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        items = Array((defaults.stringArray(forKey: Self.key) ?? []).prefix(Self.limit))
    }

    public func add(_ text: String) {
        guard !text.isEmpty else { return }
        items = Array(([text] + items).prefix(Self.limit))
        defaults.set(items, forKey: Self.key)
    }

    public func clear() {
        items = []
        defaults.removeObject(forKey: Self.key)
    }
}

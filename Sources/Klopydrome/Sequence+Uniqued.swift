import Foundation

extension Sequence where Element: Identifiable {
    /// Returns elements with duplicate IDs removed, preserving original relative order.
    func uniqued() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}

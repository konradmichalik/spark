import Foundation

extension URL {
    /// For URLs written as literals in the source. A malformed literal is a programming error that
    /// any launch would hit, so it stops with a message instead of a bare force-unwrap.
    init(staticString: StaticString) {
        guard let url = URL(string: "\(staticString)") else {
            preconditionFailure("Invalid URL literal: \(staticString)")
        }
        self = url
    }
}

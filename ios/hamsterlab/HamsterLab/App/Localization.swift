import Foundation

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
func LF(_ key: String, _ values: [String: String]) -> String {
    values.reduce(L(key)) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
}

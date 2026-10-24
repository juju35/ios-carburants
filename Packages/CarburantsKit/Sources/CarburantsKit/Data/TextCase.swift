import Foundation

/// The feed and the names file write many things in capitals: "RELAIS LES TROIS MARCHES" -> "Relais les Trois Marches".
public enum TextCase {
    // Left in lower case when an all-caps name is put in title case, except first.
    private static let smallWords: Set<String> = ["de", "du", "des", "la", "le", "les", "et", "sur", "sous", "en", "aux", "au", "d", "l"]

    // Kept as written: road numbers, "SARL", "ZA"…
    private static let upperWords = try? NSRegularExpression(
        pattern: #"^(?:[A-Z]{1,3}\d+[A-Z]?|RN|RD|ZA|ZI|ZAC|SA|SAS|SARL|SNC|EURL|BP|E\.?\s?LECLERC)$"#
    )
    private static let separators: Set<Character> = ["-", "'", "’"]

    /// Names not in capitals are kept.
    public static func name(_ input: String) -> String {
        let name = words(input).joined(separator: " ")
        guard !name.isEmpty, isCapitals(name) else { return name }
        return words(name).enumerated().map { prettyWord($1, index: $0) }.joined(separator: " ")
    }

    /// Only the words in capitals: "21 avenue CHARLES TILLON" -> "21 avenue Charles Tillon".
    public static func address(_ input: String) -> String {
        words(input).enumerated().map { index, word in
            isCapitals(word) && word.filter(\.isLetter).count > 1 ? prettyWord(word, index: index) : word
        }.joined(separator: " ")
    }

    /// The feed mixes "Rennes" and "RENNES".
    public static func city(_ city: String) -> String {
        guard !city.isEmpty, city == city.uppercased() else { return city }
        return city.lowercased().split(separator: " ").map { word in
            word.split(separator: "-", omittingEmptySubsequences: false).map { capitalizeFirst(String($0)) }.joined(separator: "-")
        }.joined(separator: " ")
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func isCapitals(_ text: String) -> Bool {
        text == text.uppercased() && text.contains(where: \.isLetter)
    }

    private static func prettyWord(_ word: String, index: Int) -> String {
        let range = NSRange(word.startIndex..., in: word)
        if upperWords?.firstMatch(in: word, range: range) != nil { return word }
        return splitKeepingSeparators(word.lowercased()).enumerated().map { n, part in
            if part.isEmpty || (part.count == 1 && separators.contains(part.first!)) { return part }
            if smallWords.contains(part) && (index > 0 || n > 0) { return part }
            return capitalizeFirst(part)
        }.joined()
    }

    private static func splitKeepingSeparators(_ word: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for ch in word {
            if separators.contains(ch) {
                parts.append(current)
                current = ""
                parts.append(String(ch))
            } else {
                current.append(ch)
            }
        }
        parts.append(current)
        return parts
    }

    private static func capitalizeFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "E. Leclerc", "E.LECLERC", "e-leclerc" -> "eleclerc"; accents dropped.
    public static func key(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

import UIKit

enum KeyboardPage {
    case letters, symbols, moreSymbols
}

enum KeyAction: Equatable {
    case character(String)
    case shift, backspace, space, enter, globe, dictation
    case page(KeyboardPage)
}

struct Key {
    let action: KeyAction
    var label: String?
    var symbolName: String?
    /// Szerokość w jednostkach (1 jednostka = 1/10 szerokości klawiatury).
    var weight: CGFloat = 1
    /// Klawisz elastyczny zajmuje resztę wiersza (spacja).
    var flexible = false
    /// Znaki dostępne po przytrzymaniu klawisza.
    var alternates: [String] = []
    var isSpecial = false

    static func char(_ c: String, alternates: [String] = []) -> Key {
        Key(action: .character(c), label: c, alternates: alternates)
    }

    static func special(_ action: KeyAction, label: String? = nil, symbol: String? = nil,
                        weight: CGFloat = 1) -> Key {
        Key(action: action, label: label, symbolName: symbol, weight: weight, isSpecial: true)
    }
}

enum KeyboardLayout {
    /// Polskie znaki i cyfry pod przytrzymaniem (jak w SwiftKey).
    private static let letterAlternates: [String: [String]] = [
        "q": ["1"], "w": ["2"], "e": ["ę", "3"], "r": ["4"], "t": ["5"],
        "y": ["6"], "u": ["7"], "i": ["8"], "o": ["ó", "9"], "p": ["0"],
        "a": ["ą", "@"], "s": ["ś", "#"], "d": ["&"], "f": ["%"], "g": ["+"],
        "h": ["-"], "j": ["="], "k": ["("], "l": ["ł", ")"],
        "z": ["ż", "ź"], "x": ["ź"], "c": ["ć"], "v": ["\""], "b": ["!"],
        "n": ["ń"], "m": ["?"],
    ]

    private static func letters(_ s: String) -> [Key] {
        s.map { Key.char(String($0), alternates: letterAlternates[String($0)] ?? []) }
    }

    private static func chars(_ list: [String]) -> [Key] {
        list.map { Key.char($0) }
    }

    private static func bottomRow(pageSwitch: Key, showGlobe: Bool) -> [Key] {
        var row = [pageSwitch]
        if showGlobe {
            row.append(.special(.globe, symbol: "globe"))
        }
        row.append(Key.char(",", alternates: [";", ":", "-", "'"]))
        row.append(Key(action: .space, label: "polski", flexible: true))
        row.append(Key.char(".", alternates: ["?", "!", "…", "@"]))
        row.append(.special(.enter, symbol: "return", weight: 1.5))
        // Mikrofon w prawym dolnym rogu.
        row.append(.special(.dictation, symbol: "mic.fill"))
        return row
    }

    static func rows(page: KeyboardPage, showGlobe: Bool) -> [[Key]] {
        let backspace = Key.special(.backspace, symbol: "delete.left", weight: 1.5)
        switch page {
        case .letters:
            return [
                letters("qwertyuiop"),
                letters("asdfghjkl"),
                [Key.special(.shift, symbol: "shift", weight: 1.5)] + letters("zxcvbnm") + [backspace],
                bottomRow(pageSwitch: .special(.page(.symbols), label: "123", weight: 1.25),
                          showGlobe: showGlobe),
            ]
        case .symbols:
            return [
                chars(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]),
                chars(["-", "/", ":", ";", "(", ")", "zł", "&", "@", "\""]),
                [Key.special(.page(.moreSymbols), label: "#+=", weight: 1.5)]
                    + chars([".", ",", "?", "!", "'", "„", "”"]) + [backspace],
                bottomRow(pageSwitch: .special(.page(.letters), label: "ABC", weight: 1.25),
                          showGlobe: showGlobe),
            ]
        case .moreSymbols:
            return [
                chars(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]),
                chars(["_", "\\", "|", "~", "<", ">", "€", "$", "£", "•"]),
                [Key.special(.page(.symbols), label: "123", weight: 1.5)]
                    + chars([".", ",", "?", "!", "'", "§", "°"]) + [backspace],
                bottomRow(pageSwitch: .special(.page(.letters), label: "ABC", weight: 1.25),
                          showGlobe: showGlobe),
            ]
        }
    }
}

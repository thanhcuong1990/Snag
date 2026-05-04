import Foundation

/// POSIX-ish shell tokenizer scoped to what `curl` invocations contain.
/// Not a full Bourne shell — no $VAR expansion, no subshells, no globbing.
enum CurlTokenizer {

    private enum QuoteState {
        case none, single, double, ansi
    }

    static func tokenize(_ input: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasCurrent = false
        var state: QuoteState = .none

        let chars = Array(input)
        var i = 0

        func flush() {
            if hasCurrent {
                tokens.append(current)
                current = ""
                hasCurrent = false
            }
        }

        while i < chars.count {
            let c = chars[i]

            switch state {
            case .none:
                if c == " " || c == "\t" || c == "\n" || c == "\r" {
                    flush()
                    i += 1
                } else if c == "\\" {
                    guard i + 1 < chars.count else {
                        throw CurlParseError.unterminatedQuote
                    }
                    let next = chars[i + 1]
                    if next == "\n" {
                        i += 2
                    } else if next == "\r" {
                        if i + 2 < chars.count && chars[i + 2] == "\n" {
                            i += 3
                        } else {
                            i += 2
                        }
                    } else {
                        current.append(next)
                        hasCurrent = true
                        i += 2
                    }
                } else if c == "'" {
                    state = .single
                    hasCurrent = true
                    i += 1
                } else if c == "\"" {
                    state = .double
                    hasCurrent = true
                    i += 1
                } else if c == "$", i + 1 < chars.count, chars[i + 1] == "'" {
                    state = .ansi
                    hasCurrent = true
                    i += 2
                } else {
                    current.append(c)
                    hasCurrent = true
                    i += 1
                }

            case .single:
                if c == "'" {
                    state = .none
                    i += 1
                } else {
                    current.append(c)
                    i += 1
                }

            case .double:
                if c == "\"" {
                    state = .none
                    i += 1
                } else if c == "\\" {
                    guard i + 1 < chars.count else {
                        throw CurlParseError.unterminatedQuote
                    }
                    let next = chars[i + 1]
                    switch next {
                    case "\"", "\\", "$", "`":
                        current.append(next)
                        i += 2
                    case "\n":
                        i += 2
                    default:
                        // bash preserves backslash + char for unknown escapes inside ""
                        current.append("\\")
                        current.append(next)
                        i += 2
                    }
                } else {
                    current.append(c)
                    i += 1
                }

            case .ansi:
                if c == "'" {
                    state = .none
                    i += 1
                } else if c == "\\" {
                    guard i + 1 < chars.count else {
                        throw CurlParseError.unterminatedQuote
                    }
                    let next = chars[i + 1]
                    switch next {
                    case "n": current.append("\n"); i += 2
                    case "r": current.append("\r"); i += 2
                    case "t": current.append("\t"); i += 2
                    case "\\": current.append("\\"); i += 2
                    case "'": current.append("'"); i += 2
                    case "\"": current.append("\""); i += 2
                    case "a": current.append("\u{07}"); i += 2
                    case "b": current.append("\u{08}"); i += 2
                    case "f": current.append("\u{0C}"); i += 2
                    case "v": current.append("\u{0B}"); i += 2
                    case "0": current.append("\u{00}"); i += 2
                    case "x":
                        if i + 3 < chars.count,
                           let byte = UInt8(String([chars[i + 2], chars[i + 3]]), radix: 16),
                           let scalar = Unicode.Scalar(UInt32(byte)) {
                            current.unicodeScalars.append(scalar)
                            i += 4
                        } else {
                            current.append("\\")
                            current.append(next)
                            i += 2
                        }
                    default:
                        current.append(next)
                        i += 2
                    }
                } else {
                    current.append(c)
                    i += 1
                }
            }
        }

        if state != .none {
            throw CurlParseError.unterminatedQuote
        }
        flush()
        return tokens
    }
}

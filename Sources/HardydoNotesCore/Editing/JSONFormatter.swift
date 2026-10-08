import Foundation

public enum JSONFormatError: LocalizedError, Equatable {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let detail): "This note is not valid JSON, so it cannot be formatted.\(detail.isEmpty ? "" : "\n\n" + detail)"
        }
    }
}

public enum JSONFormatter {
    /// Re-indents valid JSON with two spaces. Keys keep their order and values keep their exact text, unlike re-encoding.
    public static func format(_ text: String) throws -> String {
        let original: Any
        do {
            original = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        } catch {
            throw JSONFormatError.invalid((error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? "")
        }
        // Scalars, not Characters: a combining mark after a closing quote would merge with it into one Character.
        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()
        output.reserveCapacity(scalars.count + scalars.count / 4)
        var depth = 0
        var inString = false
        var escaped = false
        var index = 0

        func newline() {
            output.append("\n")
            output.append(contentsOf: String(repeating: "  ", count: depth).unicodeScalars)
        }

        func isSpace(_ scalar: Unicode.Scalar) -> Bool {
            scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
        }

        func nextSignificant(after position: Int) -> Int? {
            var next = position + 1
            while next < scalars.count, isSpace(scalars[next]) { next += 1 }
            return next < scalars.count ? next : nil
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if inString {
                output.append(scalar)
                if escaped {
                    escaped = false
                } else if scalar == "\\" {
                    escaped = true
                } else if scalar == "\"" {
                    inString = false
                }
                index += 1
                continue
            }
            switch scalar {
            case "\"":
                inString = true
                output.append(scalar)
            case "{", "[":
                output.append(scalar)
                let closer: Unicode.Scalar = scalar == "{" ? "}" : "]"
                if let next = nextSignificant(after: index), scalars[next] == closer {
                    output.append(closer)
                    index = next
                } else {
                    depth += 1
                    newline()
                }
            case "}", "]":
                depth -= 1
                newline()
                output.append(scalar)
            case ",":
                output.append(scalar)
                newline()
            case ":":
                output.append(contentsOf: ": ".unicodeScalars)
            default:
                if !isSpace(scalar) { output.append(scalar) }
            }
            index += 1
        }
        if let last = scalars.last, last == "\n" || last == "\r" { output.append("\n") }
        let formatted = String(output)
        guard let reparsed = try? JSONSerialization.jsonObject(with: Data(formatted.utf8), options: [.fragmentsAllowed]),
              (reparsed as AnyObject).isEqual(original) else {
            throw JSONFormatError.invalid("")
        }
        return formatted
    }
}

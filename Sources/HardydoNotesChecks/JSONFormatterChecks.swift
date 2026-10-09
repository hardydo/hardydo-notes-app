import Foundation
import HardydoNotesCore

func runJSONFormatterChecks() {
    checkEqual(try? JSONFormatter.format(#"{"b":1,"a":[1,2,{"x":"y, z: {"}],"e":{},"f":[]}"#), """
    {
      "b": 1,
      "a": [
        1,
        2,
        {
          "x": "y, z: {"
        }
      ],
      "e": {},
      "f": []
    }
    """, "JSON is indented with keys in their original order")
    checkEqual(try? JSONFormatter.format("{\n\"q\": \"say \\\"hi\\\"\", \"n\": 1.50e3}\n"), "{\n  \"q\": \"say \\\"hi\\\"\",\n  \"n\": 1.50e3\n}\n", "escaped quotes and number text are kept")
    checkEqual(try? JSONFormatter.format("  [ ]  "), "[]", "empty array")
    checkEqual(try? JSONFormatter.format("{\"a\":\"x\",\"b\u{301}\":\"e\u{301}\"}"), "{\n  \"a\": \"x\",\n  \"b\u{301}\": \"e\u{301}\"\n}", "a combining mark after a quote keeps strings intact")
    checkEqual(try? JSONFormatter.format("[\"👨‍👩‍👧\",\"\u{301}\"]"), "[\n  \"👨‍👩‍👧\",\n  \"\u{301}\"\n]", "a string starting with a combining mark")
    do {
        _ = try JSONFormatter.format("{\"a\": }")
        check(false, "invalid JSON is refused")
    } catch {
        check(error is JSONFormatError, "invalid JSON is refused")
    }
}

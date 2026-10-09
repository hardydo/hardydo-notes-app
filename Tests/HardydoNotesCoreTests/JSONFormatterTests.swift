import Foundation
import HardydoNotesCore
import Testing

@Suite struct JSONFormatterTests {
    @Test func indentsNestedJSONKeepingKeyOrder() {
        #expect((try? JSONFormatter.format(#"{"b":1,"a":[1,2,{"x":"y, z: {"}],"e":{},"f":[]}"#)) == """
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
    }

    @Test func escapesNumbersAndEmptyContainersAreKept() {
        #expect((try? JSONFormatter.format("{\n\"q\": \"say \\\"hi\\\"\", \"n\": 1.50e3}\n")) == "{\n  \"q\": \"say \\\"hi\\\"\",\n  \"n\": 1.50e3\n}\n", "escaped quotes and number text are kept")
        #expect((try? JSONFormatter.format("  [ ]  ")) == "[]", "empty array")
    }

    @Test func combiningMarksKeepStringsIntact() {
        #expect((try? JSONFormatter.format("{\"a\":\"x\",\"b\u{301}\":\"e\u{301}\"}")) == "{\n  \"a\": \"x\",\n  \"b\u{301}\": \"e\u{301}\"\n}", "a combining mark after a quote keeps strings intact")
        #expect((try? JSONFormatter.format("[\"👨‍👩‍👧\",\"\u{301}\"]")) == "[\n  \"👨‍👩‍👧\",\n  \"\u{301}\"\n]", "a string starting with a combining mark")
    }

    @Test func invalidJSONIsRefused() {
        #expect(throws: JSONFormatError.self, "invalid JSON is refused") { try JSONFormatter.format("{\"a\": }") }
    }
}

import Foundation

@main
@MainActor
struct DeveloperUtilityTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func result(_ name: String, _ input: String) -> String? {
        guard let utility = DeveloperUtility(rawValue: name) else {
            expect(false, "missing utility: \(name)")
            return nil
        }
        do { return try utility.transform(input) } catch {
            expect(false, "\(name) rejected valid input: \(error)"); return nil
        }
    }

    static func rejects(_ name: String, _ input: String) {
        guard let utility = DeveloperUtility(rawValue: name) else {
            expect(false, "missing utility: \(name)")
            return
        }
        do {
            _ = try utility.transform(input)
            expect(false, "\(name) accepted invalid input: \(input)")
        } catch { passes += 1 }
    }

    static func main() {
        for utility in DeveloperUtility.allCases {
            expect(
                BuiltInQuickAction(rawValue: utility.rawValue)?.requiresAI == false,
                "\(utility) has a local Quick Action route")
        }
        expect(!DeveloperUtility.generateUUID.requiresSelection, "UUID generation needs no selection")
        expect(!DeveloperUtility.generateLoremIpsum.requiresSelection, "Lorem Ipsum needs no selection")
        expect(DeveloperUtility.hexEncode.requiresSelection, "text transformations require input")
        expect(result("hexEncode", "Hello") == "48656c6c6f", "hex uses UTF-8 bytes")
        expect(result("hexDecode", "d09fd180d0b8d0b2d0b5d182") == "Привет", "hex decodes UTF-8")
        for value in ["0", "gg", "ff"] { rejects("hexDecode", value) }

        expect(
            result("urlEncode", "a+b /?&é") == "a%2Bb%20%2F%3F%26%C3%A9",
            "URL encoding escapes every reserved character and UTF-8 byte")
        expect(result("urlEncode", "AZaz09-._~") == "AZaz09-._~", "URL unreserved text stays literal")
        expect(result("urlDecode", "a%2Bb%20%2F%3F%26%C3%A9") == "a+b /?&é", "URL decoding restores UTF-8")
        expect(result("urlDecode", "a+b") == "a+b", "URL decoding preserves plus")
        for value in ["%", "%0G", "%FF"] { rejects("urlDecode", value) }

        let uuid = result("generateUUID", "ignored")
        expect(uuid.flatMap(UUID.init(uuidString:)) != nil, "UUID generation returns a UUID")
        expect(uuid == uuid?.lowercased(), "UUID generation uses lowercase")
        expect(uuid != result("generateUUID", ""), "UUID generation makes a new value")
        expect(result("timestampToDate", "0") == "1970-01-01T00:00:00.000Z", "Unix epoch uses UTC")
        expect(
            result("timestampToDate", "0.125") == "1970-01-01T00:00:00.125Z", "timestamps retain fractions")
        expect(
            result("timestampToDate", "-1") == "1969-12-31T23:59:59.000Z",
            "timestamps support pre-epoch dates")
        for value in ["NaN", "inf", "1e100", "tomorrow"] { rejects("timestampToDate", value) }

        expect(
            result("convertColor", "#f00") == "#ff0000\nrgb(255, 0, 0)\nhsl(0, 100%, 50%)",
            "short hex converts to full CSS color forms")
        expect(
            result("convertColor", "rgb(0, 255, 0)") == "#00ff00\nrgb(0, 255, 0)\nhsl(120, 100%, 50%)",
            "RGB converts to hex and HSL")
        expect(
            result("convertColor", "hsl(240, 100%, 50%)") == "#0000ff\nrgb(0, 0, 255)\nhsl(240, 100%, 50%)",
            "HSL converts to RGB and hex")
        expect(
            result("convertColor", "#808080") == "#808080\nrgb(128, 128, 128)\nhsl(0, 0%, 50.2%)",
            "achromatic colors do not divide by zero")
        for value in ["#abcd", "rgb(256,0,0)", "rgb(-1,0,0)", "hsl(361,100%,50%)", "hsl(0,101%,50%)"] {
            rejects("convertColor", value)
        }

        let lorem = result("generateLoremIpsum", "ignored")
        expect(lorem?.hasPrefix("Lorem ipsum dolor sit amet,") == true, "Lorem Ipsum returns readable text")
        expect(lorem == result("generateLoremIpsum", ""), "Lorem Ipsum generation is deterministic")
        expect(
            result("convertCase", "hello_world XMLParser foo-bar")
                == "camelCase: helloWorldXmlParserFooBar\nsnake_case: hello_world_xml_parser_foo_bar\nkebab-case: hello-world-xml-parser-foo-bar",
            "case conversion splits separators, camel case, and acronyms")
        expect(
            result("convertCase", "déjà vu")
                == "camelCase: déjàVu\nsnake_case: déjà_vu\nkebab-case: déjà-vu",
            "case conversion preserves non-ASCII words")
        rejects("convertCase", " --- ")

        expect(result("base64Encode", "Hello") == "SGVsbG8=", "existing Base64 encode stays available")
        expect(result("base64Decode", "SGVsbG8=") == "Hello", "existing Base64 decode stays available")
        expect(result("minifyJSON", "{ \"a\" : 1 }") == "{\"a\":1}", "existing JSON minify stays available")
        expect(
            result("formatJSON", "{\"a\":1}")?.contains("\n") == true,
            "existing JSON formatting stays available")
        for fragment in ["null", "true", "42", "\"text\""] {
            expect(result("minifyJSON", fragment) == fragment, "JSON minify accepts scalar fragments")
            expect(result("formatJSON", fragment) == fragment, "JSON formatting accepts scalar fragments")
        }
        expect(
            result("hashMD5", "hello") == "5d41402abc4b2a76b9719d911017c592", "existing MD5 stays available")
        expect(
            result("hashSHA256", "hello")
                == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
            "existing SHA-256 stays available")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}

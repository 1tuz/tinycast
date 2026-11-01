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
        jwtDecoding()
        cidrCalculation()
        secretDecoding()
        yamlJSONConversion()
        cronExplanation()
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
    static func yamlJSONConversion() {
        let sample = "name: tinycast\nitems:\n  - one\n  - two"
        let output = result("convertYAMLJSON", sample) ?? ""
        let object = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [String: Any]
        expect(object?["name"] as? String == "tinycast", "YAML parses nested mapping")
        expect(object?["items"] as? [String] == ["one", "two"], "YAML parses nested array")
        expect(
            output.range(of: "items")?.lowerBound ?? output.endIndex
                < output.range(of: "name")?.lowerBound ?? output.startIndex, "JSON keys are sorted")
        expect(result("convertYAMLJSON", "hello") == "\"hello\"", "plain YAML scalar becomes JSON")
        let json =
            "{\"apiVersion\":\"v1\",\"data\":{\"password\":\"SGVsbG8=\"},\"items\":[true,null,3,{},[]]}"
        if let yaml = result("convertYAMLJSON", json),
            let parsed = try? BlockYAMLParser.parse(yaml),
            let canonical = try? JSONSerialization.data(withJSONObject: parsed, options: [.sortedKeys]),
            let original = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
            let expected = try? JSONSerialization.data(withJSONObject: original, options: [.sortedKeys])
        {
            expect(canonical == expected, "emitted YAML preserves JSON values")
        } else {
            expect(false, "JSON emits parseable YAML")
        }
        for fragment in ["null", "true", "42", "\"text\""] {
            if let yaml = result("convertYAMLJSON", fragment),
                let parsed = try? BlockYAMLParser.parse(yaml),
                let original = try? JSONSerialization.jsonObject(
                    with: Data(fragment.utf8), options: [.fragmentsAllowed]),
                let actual = try? JSONSerialization.data(
                    withJSONObject: parsed, options: [.fragmentsAllowed]),
                let expected = try? JSONSerialization.data(
                    withJSONObject: original, options: [.fragmentsAllowed])
            {
                expect(actual == expected, "JSON scalar survives YAML round trip")
            } else {
                expect(false, "JSON scalar emits valid YAML")
            }
        }
        let secret = """
            apiVersion: v1
            kind: Secret
            metadata:
              name: demo
              labels:
                app: 'it''s a demo' # comment
              finalizers:
              - example.com/finalizer
            data:
              password: SGVsbG8=
            type: Opaque
            """
        let secretJSON = result("convertYAMLJSON", secret) ?? ""
        let secretValue = (try? JSONSerialization.jsonObject(with: Data(secretJSON.utf8))) as? [String: Any]
        expect(
            (secretValue?["data"] as? [String: String])?["password"] == "SGVsbG8=",
            "kubectl Secret data stays text")
        expect(
            ((secretValue?["metadata"] as? [String: Any])?["finalizers"] as? [String]) == [
                "example.com/finalizer"
            ], "indentless YAML sequences parse")
        let sequence =
            result(
                "convertYAMLJSON", "- name: first\n  enabled: true\n- name: second\n  nested:\n    value: 2")
            ?? ""
        let array = (try? JSONSerialization.jsonObject(with: Data(sequence.utf8))) as? [[String: Any]]
        expect(
            array?.count == 2 && array?[0]["enabled"] as? Bool == true,
            "sequence mappings preserve sibling fields")
        let flow =
            result(
                "convertYAMLJSON",
                "value: [1, true, null, \"# text\"]\nquoted: \"a: b # c\"\nurl: https://example.test/path#fragment"
            ) ?? ""
        let flowValue = (try? JSONSerialization.jsonObject(with: Data(flow.utf8))) as? [String: Any]
        expect((flowValue?["value"] as? [Any])?.count == 4, "JSON flow collections parse")
        expect(flowValue?["quoted"] as? String == "a: b # c", "quoted punctuation stays literal")
        expect(
            flowValue?["url"] as? String == "https://example.test/path#fragment",
            "plain hash without whitespace stays literal")
        for input in [
            "", "  \n", "a: [", "---\na: 1\n---\nb: 2", "1: value", ".inf", ".nan",
            "value: !!binary SGVsbG8=", "!!set {a: null}", "key: &anchor value", "key: *anchor",
            "key: |\n  content", "key: >\n  content", "[a, b]", "{a: 1}", "? [a,b]\n: value",
            "a: 1\na: 2", "a:\n   b: 1\n  c: 2", "a:\n\tb: 1", "a: value\n  nested: invalid",
            "a: \"unterminated", "a: 'unterminated", "a: b: c", "%YAML 1.2\na: 1"
        ] {
            rejects("convertYAMLJSON", input)
        }
        expect(DeveloperUtility.convertYAMLJSON.requiresSelection, "YAML conversion needs input")
    }

    static func cronExplanation() {
        expect(
            result("explainCron", "*/5 * * * *") == "Every 5 minutes", "minute step has a short explanation")
        let fixed = result("explainCron", "15 9 * * 1-5") ?? ""
        for text in ["Minute: 15", "Hour: 9", "Day of month:", "Month:", "Day of week: 1, 2, 3, 4, 5"] {
            expect(fixed.contains(text), "cron explanation identifies every field")
        }
        for (input, text) in [
            ("1,3,8 2 * * *", "Minute: 1, 3, 8"), ("1-3 2 * * *", "Minute: 1, 2, 3"),
            ("55/2 2 * * *", "Minute: 55, 57, 59"), ("1-8/3 2 * * *", "Minute: 1, 4, 7"),
            ("1 2 * * 7", "Day of week: 0"), ("1 2 3 * 4", "either day condition (OR)")
        ] {
            expect(
                result("explainCron", input)?.contains(text) == true,
                "cron lists, ranges, steps and OR semantics")
        }
        for input in [
            "", "* * * *", "* * * * * *", "@daily", "0 0 * JAN MON", "1,,2 * * * *",
            "1- * * * *", "-2 * * * *", "4-2 * * * *", "*/0 * * * *", "*/-2 * * * *",
            "*/x * * * *", "*/999 * * * *", "1/999 * * * *", "60 * * * *", "* 24 * * *", "* * 0 * *",
            "* * 32 * *",
            "* * * 0 *", "* * * 13 *", "* * * * 8", "1//2 * * * *", "1/ * * * *",
            ", * * * *", "1-2-3 * * * *", "+1 * * * *", "1.5 * * * *"
        ] {
            rejects("explainCron", input)
        }
        expect(DeveloperUtility.explainCron.requiresSelection, "cron explanation needs input")
    }

    static func jwtDecoding() {
        func segment(_ json: String) -> String {
            Data(json.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let header = segment("{\"alg\":\"HS256\",\"typ\":\"JWT\"}")
        let payload = segment("{\"sub\":\"demo\",\"iat\":0,\"nbf\":1,\"exp\":2}")
        let token = header + "." + payload + ".c2ln"
        let output = result("decodeJWT", token) ?? ""
        for text in [
            "Header:", "Payload:", "HS256", "demo", "iat: 1970-01-01T00:00:00.000Z",
            "nbf: 1970-01-01T00:00:01.000Z", "exp: 1970-01-01T00:00:02.000Z",
            "Signature not verified"
        ] {
            expect(output.contains(text), "JWT includes decoded values, UTC dates and signature warning")
        }
        expect(result("decodeJWT", "Bearer " + token) == output, "JWT accepts Bearer prefix")
        expect(result("decodeJWT", "bearer " + token) == output, "Bearer prefix is case insensitive")
        let unsigned = header + "." + segment("{\"sub\":\"demo\"}") + "."
        expect(
            result("decodeJWT", unsigned)?.contains("Signature not verified") == true,
            "unsigned token never claims verification")
        let none = segment("{\"alg\":\"none\"}") + "." + segment("{\"sub\":\"demo\"}") + "."
        expect(
            result("decodeJWT", none)?.contains("Signature not verified") == true,
            "alg none still reports no verification")
        rejects("decodeJWT", String(repeating: "a", count: 1_048_577))
        for input in [
            "", "a.b", "a.b.c.d", "..", "Bearer a b", "Bearer ", "x." + payload + ".sig",
            segment("[]") + "." + payload + ".sig", header + "." + segment("null") + ".sig",
            header + "." + segment("{\"exp\":true}") + ".sig",
            header + "." + segment("{\"exp\":1e99}") + ".sig", token + "!"
        ] {
            rejects("decodeJWT", input)
        }
    }

    static func cidrCalculation() {
        let output = result("calculateCIDR", "192.168.1.10/24") ?? ""
        for text in [
            "Network: 192.168.1.0", "Netmask: 255.255.255.0", "Wildcard: 0.0.0.255",
            "Broadcast: 192.168.1.255", "Host range: 192.168.1.1 – 192.168.1.254", "Hosts: 254"
        ] {
            expect(output.contains(text), "CIDR computes every IPv4 field")
        }
        let zero = result("calculateCIDR", "255.255.255.255/0") ?? ""
        expect(
            zero.contains("Network: 0.0.0.0") && zero.contains("Hosts: 4294967294"),
            "/0 uses wide counters: \(zero)")
        let pair = result("calculateCIDR", "10.0.0.3/31") ?? ""
        expect(
            pair.contains("Host range: 10.0.0.2 – 10.0.0.3") && pair.contains("Hosts: 2"),
            "/31 keeps both RFC 3021 hosts")
        let host = result("calculateCIDR", "255.255.255.255/32") ?? ""
        expect(
            host.contains("Host range: 255.255.255.255 – 255.255.255.255") && host.contains("Hosts: 1"),
            "/32 keeps one host")
        for input in [
            "", "192.168.1.1", "192.168.1/24", "256.0.0.1/24", "1.2.3.4/33", "1.2.3.4/-1",
            "1.2.3.4/+1", "1.2.3.4/1/2", "01.2.3.4/24", "::1/64", "1.2.x.4/24"
        ] {
            rejects("calculateCIDR", input)
        }
    }

    static func secretDecoding() {
        let multiline = Data("first\nsecond\n".utf8).base64EncodedString()
        let binary = Data([0xff, 0, 0xfe]).base64EncodedString()
        let json =
            "{\"kind\":\"Secret\",\"data\":{\"text\":\"SGVsbG8=\",\"lines\":\"\(multiline)\",\"binary\":\"\(binary)\"}}"
        let output = result("decodeKubernetesSecret", json) ?? ""
        expect(output.contains("\"text\": \"Hello\""), "Secret decodes Base64 text")
        expect(
            output.contains("\"lines\": |2+\n  first\n  second\n"),
            "Secret preserves multiline UTF-8 as block")
        expect(output.contains("<3 bytes binary>"), "Secret labels binary bytes")
        let yaml = "apiVersion: v1\nkind: Secret\ndata:\n  password: SGVsbG8=\n"
        expect(
            result("decodeKubernetesSecret", yaml)?.contains("\"password\": \"Hello\"") == true,
            "Secret accepts kubectl block YAML")
        expect(
            result("decodeKubernetesSecret", "kind: Secret") == "The Secret contains no data.",
            "empty Secret reports no data")
        for (text, block) in [
            ("  first\nsecond", "|2-\n    first\n  second\n"),
            ("first\n\n", "|2+\n  first\n  \n"), ("\n", "|2+\n  \n")
        ] {
            let encoded = Data(text.utf8).base64EncodedString()
            let input = "{\"kind\":\"Secret\",\"data\":{\"value\":\"\(encoded)\"}}"
            expect(
                result("decodeKubernetesSecret", input) == "\"value\": " + block,
                "Secret block preserves leading spaces and trailing lines")
        }
        let utf8 = Data("Привет 👋".utf8).base64EncodedString()
        let utf8Input = "{\"kind\":\"Secret\",\"data\":{\"a\":\"\(utf8)\",\"control\":\"AA==\"}}"
        let utf8Output = result("decodeKubernetesSecret", utf8Input) ?? ""
        expect(utf8Output.contains("Привет 👋"), "Secret preserves UTF-8 text")
        expect(utf8Output.contains("<1 bytes binary>"), "Secret treats null byte as binary")
        rejects("decodeKubernetesSecret", String(repeating: "a", count: 1_048_577))
        for input in [
            "", "kind: ConfigMap\ndata: {}", "{\"kind\":\"Secret\",\"data\":{\"a\":42}}",
            "kind: Secret\ndata:\n  a: not-base64", "kind: Secret\ndata: []", "data: {}"
        ] {
            rejects("decodeKubernetesSecret", input)
        }
    }

}

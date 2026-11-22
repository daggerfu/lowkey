import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("BUNDLE_CHECK_FAILED: \(message)\n".utf8))
    exit(1)
}
guard CommandLine.arguments.count == 2 else { fail("Expected a lowkey.app path") }
let app = URL(fileURLWithPath: CommandLine.arguments[1])
guard app.lastPathComponent == "lowkey.app", let bundle = Bundle(url: app), let info = bundle.infoDictionary else {
    fail("The public bundle must be named lowkey.app")
}
for (key, expected) in ["CFBundleName": "lowkey", "CFBundleDisplayName": "lowkey",
                        "CFBundleIdentifier": "io.bobuk.lowkey", "CFBundleExecutable": "Lowkey",
                        "LSMinimumSystemVersion": "10.15"] {
    guard info[key] as? String == expected else { fail("Unexpected \(key)") }
}
guard FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/Helpers/lowkeyctl").path) else {
    fail("Missing lowkeyctl executable")
}
let types = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
guard types.contains(where: { ($0["CFBundleURLSchemes"] as? [String])?.contains("lowkey") == true }) else {
    fail("Missing lowkey deep-link scheme")
}
for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription"] {
    guard let text = info[key] as? String, text.contains("lowkey"), !text.contains("Lowkey") else {
        fail("Missing or incorrectly branded \(key)")
    }
}
print("BUNDLE_CHECK_PASSED: lowkey")

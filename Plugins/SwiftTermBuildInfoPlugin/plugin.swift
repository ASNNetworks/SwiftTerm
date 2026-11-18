import Foundation
import PackagePlugin
#if canImport(Darwin)
import Darwin
#endif

@main
struct SwiftTermBuildInfoPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let generator = try context.tool(named: "SwiftTermBuildInfoGenerator")
        let outputDirectory = context.pluginWorkDirectoryURL.appendingPathComponent("Generated")
        let outputFile = outputDirectory.appendingPathComponent("SwiftTermBuildInfo.swift")
        let triggerFile = context.pluginWorkDirectoryURL.appendingPathComponent("build-info-trigger")
        let fallbackVariableNames = [
            "SWIFTTERM_BUILD_BRANCH",
            "SWIFTTERM_BUILD_TAG",
            "SWIFTTERM_BUILD_COMMIT",
            "SWIFTTERM_BUILD_DIRTY"
        ]
        let processEnvironment = ProcessInfo.processInfo.environment
        let fallbackEnvironment = fallbackVariableNames.reduce(into: [String: String]()) { result, name in
            if let value = processEnvironment[name] {
                result[name] = value
            }
        }

        try writeTrigger(to: triggerFile)

        return [
            .buildCommand(
                displayName: "Generate SwiftTerm build information",
                executable: generator.url,
                arguments: [
                    context.package.directoryURL.path,
                    outputFile.path
                ],
                environment: fallbackEnvironment,
                inputFiles: [triggerFile],
                outputFiles: [outputFile]
            )
        ]
    }

    private func writeTrigger(to url: URL) throws {
        let trigger = UUID().uuidString
#if canImport(Darwin)
        // SwiftPM creates the work directory. Foundation writes query volume
        // services that the macOS plugin sandbox denies.
        let path = url.path
        func fileError(_ code: Int32) -> NSError {
            NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: path])
        }

        let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0o666)
        guard descriptor >= 0 else { throw fileError(errno) }

        let writeError = Array(trigger.utf8).withUnsafeBytes { buffer -> Int32? in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress?.advanced(by: offset), buffer.count - offset)
                if count > 0 {
                    offset += count
                } else if count == 0 || errno != EINTR {
                    return count == 0 ? EIO : errno
                }
            }
            return nil
        }
        let closeError = Darwin.close(descriptor) == 0 ? nil : errno
        if let code = writeError ?? closeError { throw fileError(code) }
#else
        try trigger.write(to: url, atomically: true, encoding: .utf8)
#endif
    }
}

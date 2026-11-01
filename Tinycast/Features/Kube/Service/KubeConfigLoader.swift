import Foundation

enum KubeConfigLoader {
    @concurrent
    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = FileManager.default.homeDirectoryForCurrentUser.path
    ) async throws -> KubeConfiguration {
        try Task.checkCancellation()
        return try KubeConfigReader.load(
            environment: environment, homeDirectory: homeDirectory
        ) { path in
            let manager = FileManager.default
            guard manager.fileExists(atPath: path) else { return nil }
            let target = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            let attributes = try manager.attributesOfItem(atPath: target.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                let size = attributes[.size] as? NSNumber,
                size.intValue <= KubeConfigReader.maximumBytes
            else { throw KubeConfigReaderError.unreadableFile(path) }
            try Task.checkCancellation()
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            var data = Data()
            while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
                try Task.checkCancellation()
                guard data.count + chunk.count <= KubeConfigReader.maximumBytes else {
                    throw KubeConfigReaderError.unreadableFile(path)
                }
                data.append(chunk)
            }
            return data
        }
    }
}

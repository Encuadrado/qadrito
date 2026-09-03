import Foundation

class CacheManager {
    static let shared = CacheManager()
    
    private let fileManager = FileManager.default
    private var cacheDirectoryURL: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Qadrito")
    }
    
    private init() {
        if let cacheDirectoryURL {
            try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        }
    }
    
    func saveCache(_ data: CachedData, scope: PRScope) {
        guard let fileURL = fileURL(for: scope) else { return }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let encoded = try? encoder.encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }
    
    func loadCache(scope: PRScope) -> CachedData? {
        guard let fileURL = fileURL(for: scope),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedData.self, from: data)
    }
    
    /// Legacy single-file cache (pre per-scope). Used once for migration.
    func loadLegacyCache() -> CachedData? {
        guard let cacheDirectoryURL else { return nil }
        let fileURL = cacheDirectoryURL.appendingPathComponent("cache.json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedData.self, from: data)
    }
    
    func clearCache() {
        guard let cacheDirectoryURL else { return }
        
        for scope in PRScope.allCases {
            if let url = fileURL(for: scope) {
                try? fileManager.removeItem(at: url)
            }
        }
        
        let legacyURL = cacheDirectoryURL.appendingPathComponent("cache.json")
        try? fileManager.removeItem(at: legacyURL)
        
        // Also remove any other cache-*.json leftovers.
        if let contents = try? fileManager.contentsOfDirectory(at: cacheDirectoryURL, includingPropertiesForKeys: nil) {
            for url in contents where url.lastPathComponent.hasPrefix("cache-") && url.pathExtension == "json" {
                try? fileManager.removeItem(at: url)
            }
        }
    }
    
    private func fileURL(for scope: PRScope) -> URL? {
        guard let cacheDirectoryURL else { return nil }
        let safeName = sanitize(scope.cacheFileId)
        return cacheDirectoryURL.appendingPathComponent("cache-\(safeName).json")
    }
    
    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("_") }
        let cleaned = String(scalars)
        return cleaned.isEmpty ? "scope" : cleaned
    }
}

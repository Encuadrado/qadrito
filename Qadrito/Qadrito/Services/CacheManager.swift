import Foundation

class CacheManager {
    static let shared = CacheManager()
    
    private let fileManager = FileManager.default
    private var cacheURL: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Qadrito")
    }
    
    private init() {
        if let cacheURL = cacheURL {
            try? fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        }
    }
    
    func saveCache(_ data: CachedData) {
        guard let cacheURL = cacheURL else { return }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let encoded = try? encoder.encode(data) else { return }
        
        let fileURL = cacheURL.appendingPathComponent("cache.json")
        try? encoded.write(to: fileURL)
    }
    
    func loadCache() -> CachedData? {
        guard let cacheURL = cacheURL else { return nil }
        
        let fileURL = cacheURL.appendingPathComponent("cache.json")
        
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try? decoder.decode(CachedData.self, from: data)
    }
    
    func clearCache() {
        guard let cacheURL = cacheURL else { return }
        let fileURL = cacheURL.appendingPathComponent("cache.json")
        try? fileManager.removeItem(at: fileURL)
    }
}

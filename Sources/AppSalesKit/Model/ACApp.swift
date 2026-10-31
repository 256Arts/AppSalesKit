import Foundation

public struct ACApp: Codable, Identifiable {
    public var id: String { return sku }
    public let appleID: String
    public let name: String
    public let sku: String
    public let version: String
    public let price: Double
    public let currentVersionReleaseDate: String
    /// Nil only in a cache written before apps off the App Store were left out.
    public let iconURL100: URL?
    public let iconURL512: URL?
    
    public var url: URL {
        URL(string: "https://apps.apple.com/app/id" + appleID)!
    }
    public var cachedIconURL: URL? {
        guard let groupURL = AppSalesKit.containerURL else { return nil }
        
        return groupURL.appending(path: appleID).appendingPathExtension("jpg")
    }
    
    public func saveIcon() async {
        guard let cachedIconURL, let iconURL512 else { return }
        
        let imageData: Data? = await {
            if let data = try? Data(contentsOf: iconURL512) {
                return data
            } else if let data = try? await URLSession.shared.data(from: iconURL512).0 {
                return data
            }
            return nil
        }()
        
        if let imageData {
            FileManager.default.createFile(atPath: cachedIconURL.path(percentEncoded: false), contents: imageData)
        }
    }

    public static func == (lhs: ACApp, rhs: ACApp) -> Bool {
        return lhs.id == rhs.id
    }
    
    public static let demo1 = ACApp(
        appleID: "1",
        name: "Forest Explorer",
        sku: "1",
        version: "1.0",
        price: 1.49,
        currentVersionReleaseDate: "",
        iconURL100: Bundle.module.url(forResource: "Demo Icon 1", withExtension: "png")!,
        iconURL512: Bundle.module.url(forResource: "Demo Icon 1", withExtension: "png")!)
    
    public static let demo2 = ACApp(
        appleID: "2",
        name: "Ocean Journal",
        sku: "2",
        version: "1.0",
        price: 1.29,
        currentVersionReleaseDate: "",
        iconURL100: Bundle.module.url(forResource: "Demo Icon 2", withExtension: "png")!,
        iconURL512: Bundle.module.url(forResource: "Demo Icon 2", withExtension: "png")!)
    
    public static let demo3 = ACApp(
        appleID: "3",
        name: "Mountain Climber",
        sku: "3",
        version: "1.0",
        price: 0.99,
        currentVersionReleaseDate: "",
        iconURL100: Bundle.module.url(forResource: "Demo Icon 3", withExtension: "png")!,
        iconURL512: Bundle.module.url(forResource: "Demo Icon 3", withExtension: "png")!)
    
    public static let demo4 = ACApp(
        appleID: "4",
        name: "Sunset Seeker",
        sku: "4",
        version: "1.0",
        price: 0.49,
        currentVersionReleaseDate: "",
        iconURL100: Bundle.module.url(forResource: "Demo Icon 4", withExtension: "png")!,
        iconURL512: Bundle.module.url(forResource: "Demo Icon 4", withExtension: "png")!)
}

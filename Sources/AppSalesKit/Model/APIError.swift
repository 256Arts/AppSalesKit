import Foundation

public enum APIError: LocalizedError, Equatable {
    case invalidCredentials
    case wrongPermissions
    case exceededLimit
    case noDataAvailable
    case unknown
    /// A failure none of the cases above describe, carrying its own explanation so it can be diagnosed.
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return String(localized: "The credentials you entered are incorrect.", bundle: #bundle)
        case .wrongPermissions:
            return String(localized: "Your API-key does not have the right permissions.", bundle: #bundle)
        case .exceededLimit:
            return String(localized: "You have exceeded the daily limit of API requests.", bundle: #bundle)
        case .noDataAvailable:
            return String(localized: "Data is not yet available.", bundle: #bundle)
        case .unknown:
            return String(localized: "An unknown error occurred. Please file a bug report.", bundle: #bundle)
        case .failed(let reason):
            return reason
        }
    }
}

/// Lets an `APIError` surface in Shortcuts with the same wording the app shows.
extension APIError: CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource {
        "\(errorDescription ?? String(localized: "An unknown error occurred.", bundle: #bundle))"
    }
}

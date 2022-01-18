import Foundation

public enum DownloadingError: Error {
    case network(cause: Error)
    case response(URLResponse)
    case io(cause: Error)
}

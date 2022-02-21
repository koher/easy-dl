import Foundation

public enum DownloadingError: Error {
    case timeout(cause: Error)
    case network(cause: Error)
    case response(URLResponse)
    case io(cause: Error)
}

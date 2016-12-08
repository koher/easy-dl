import Foundation

extension Downloader {
    public convenience init(items: [(URL, String)], needsPreciseProgress: Bool = true, commonRequestHeaders: [String: String]? = nil) {
        self.init(items: items.map { Item(url: $0.0, destination: $0.1) }, needsPreciseProgress: needsPreciseProgress, commonRequestHeaders: commonRequestHeaders)
    }

    public func handleProgress(_ handler: @escaping (Float?) -> ()) {
        handleProgress { done, whole in
            handler(whole.map { whole in Float(Double(done) / Double(whole)) })
        }
    }
}

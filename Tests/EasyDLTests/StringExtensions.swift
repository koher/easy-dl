import Foundation

extension String {
    internal var deletingLastPathComponent: String {
        return (self as NSString).deletingLastPathComponent
    }
    
    internal func appendingPathComponent(_ pathComponent: String) -> String {
        return (self as NSString).appendingPathComponent(pathComponent)
    }
}

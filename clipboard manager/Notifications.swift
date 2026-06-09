import Foundation

extension Notification.Name {
    // Hotkey
    static let hotkeyDidChange = Notification.Name("hotkeyDidChange")
    
    // Overlay Navigation
    static let overlaySelectNext = Notification.Name("overlaySelectNext")
    static let overlaySelectPrevious = Notification.Name("overlaySelectPrevious")
    static let overlayConfirmSelection = Notification.Name("overlayConfirmSelection")
}

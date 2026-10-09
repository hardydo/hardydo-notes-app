import Foundation

// Every pattern in this module is a literal, so one that fails to compile is a programming error.
func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern, options: options)
}

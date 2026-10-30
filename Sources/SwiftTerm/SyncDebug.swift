#if !SWIFTTERM_EMBEDDED
enum SyncDebug {
    static func log(_ message: @autoclosure () -> String) {
    }
}

#endif // !SWIFTTERM_EMBEDDED

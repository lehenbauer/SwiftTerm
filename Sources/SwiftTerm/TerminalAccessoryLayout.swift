enum TerminalAccessoryLayout {
    static func shrinkableTail<T>(of values: [T], useSmall: Bool) -> ArraySlice<T> {
        let preservedCount = min(useSmall ? 2 : 4, values.count)
        return values.dropFirst(preservedCount)
    }
}

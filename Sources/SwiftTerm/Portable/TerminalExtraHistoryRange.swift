/// Additional presentation rows for a fixed-grid viewport. This never changes
/// the emulator's grid, display anchor, scroll region, or cursor coordinates.
func terminalExtraHistoryRange(
    enabled: Bool, alternate: Bool, displayRow: Int, gridRows: Int,
    lineCount: Int, viewportFirstRow: Int, viewportRows: Int
) -> Range<Int>? {
    guard enabled, !alternate, gridRows > 0, lineCount > 0,
          viewportRows > gridRows else { return nil }
    let first = min(max(0, displayRow), max(0, viewportFirstRow), lineCount)
    let count = min(viewportRows, lineCount - first)
    return first..<(first + count)
}

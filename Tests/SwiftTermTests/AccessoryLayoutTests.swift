import Testing
@testable import SwiftTerm

struct AccessoryLayoutTests {
    @Test func regularWidthWithOnlyPhoneFloatKeysHasNoShrinkableTail() {
        let tail = Array(TerminalAccessoryLayout.shrinkableTail(of: [1, 2, 3], useSmall: false))
        #expect(tail.isEmpty)
    }

    @Test func smallLayoutPreservesFirstTwoFloatKeys() {
        let tail = Array(TerminalAccessoryLayout.shrinkableTail(of: [1, 2, 3, 4], useSmall: true))
        #expect(tail == [3, 4])
    }

    @Test func regularLayoutPreservesFirstFourFloatKeys() {
        let tail = Array(TerminalAccessoryLayout.shrinkableTail(of: [1, 2, 3, 4, 5, 6], useSmall: false))
        #expect(tail == [5, 6])
    }
}

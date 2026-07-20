//
//  TerminalInspection.swift
//  SwiftTerm
//
//  Core-engine inspection snapshots for client third-witness diagnostics.
//  See untracked/DESIGN-terminal-inspection.md (PR1).
//

import Foundation

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - FNV-1a 64

/// FNV-1a 64-bit non-cryptographic hash used as a triage content token.
public enum TerminalInspectionHash {
    public static let offsetBasis: UInt64 = 14_695_981_039_346_656_037
    public static let prime: UInt64 = 1_099_511_628_211

    public static func fnv1a64(bytes: [UInt8]) -> UInt64 {
        var hash = offsetBasis
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }

    public static func fnv1a64(data: Data) -> UInt64 {
        var hash = offsetBasis
        data.withUnsafeBytes { raw in
            let buffer = raw.bindMemory(to: UInt8.self)
            for byte in buffer {
                hash ^= UInt64(byte)
                hash = hash &* prime
            }
        }
        return hash
    }
}

// MARK: - Snapshots

/// Core-engine inspection of a `Terminal` at a single point in time.
///
/// Product contract: **engine belief**, not last-presented pixels. Threading:
/// call on the same serial executor that owns feed/resize for this terminal.
public struct TerminalInspectionSnapshot: Sendable, Equatable {
    public var cols: Int
    public var rows: Int

    public var cursorEngineCol: Int
    public var cursorEngineRow: Int
    public var cursorPendingWrap: Bool
    public var cursorHidden: Bool
    public var cursorOnScreen: Bool
    public var cursorViewportCol: Int?
    public var cursorViewportRow: Int?

    /// `"normal"` or `"alt"`.
    public var bufferKind: String
    public var isAlternateScreen: Bool
    /// `buffer.yBase - buffer.yDisp` (0 at live bottom).
    public var scrolledRows: Int

    public var trimRight: Bool
    public var viewportText: [String]
    public var contentHash: UInt64

    public var modes: TerminalModeSummary
    public var kittyKeyboard: KittyKeyboardInspection
}

public struct TerminalModeSummary: Sendable, Equatable {
    public var applicationCursor: Bool
    public var applicationKeypad: Bool
    public var bracketedPaste: Bool
    public var originMode: Bool
    public var marginMode: Bool
    public var wraparound: Bool
    public var insertMode: Bool
    public var synchronizedOutputActive: Bool
    /// `off` | `x10` | `vt200` | `buttonEvent` | `anyEvent`
    public var mouseMode: String
    /// `x10` | `utf8` | `sgr` | `urxvt` | `sgrPixel`
    public var mouseProtocol: String
    public var mouseShiftCapture: Bool
}

public struct KittyKeyboardInspection: Sendable, Equatable {
    public var active: Bool
    public var flagsRaw: Int
    public var flags: [String]
    public var stackDepth: Int
    /// `"normal"` or `"alt"` — which buffer slot is active for this inspection.
    public var buffer: String
    public var otherBufferFlagsRaw: Int
    public var otherBufferStackDepth: Int
}

// MARK: - Codable (snake_case wire; content_hash as decimal string)

extension TerminalInspectionSnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case cols, rows
        case cursorEngineCol = "cursor_engine_col"
        case cursorEngineRow = "cursor_engine_row"
        case cursorPendingWrap = "cursor_pending_wrap"
        case cursorHidden = "cursor_hidden"
        case cursorOnScreen = "cursor_on_screen"
        case cursorViewportCol = "cursor_viewport_col"
        case cursorViewportRow = "cursor_viewport_row"
        case bufferKind = "buffer_kind"
        case isAlternateScreen = "is_alternate_screen"
        case scrolledRows = "scrolled_rows"
        case trimRight = "trim_right"
        case viewportText = "viewport_text"
        case contentHash = "content_hash"
        case modes
        case kittyKeyboard = "kitty_keyboard"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cols, forKey: .cols)
        try c.encode(rows, forKey: .rows)
        try c.encode(cursorEngineCol, forKey: .cursorEngineCol)
        try c.encode(cursorEngineRow, forKey: .cursorEngineRow)
        try c.encode(cursorPendingWrap, forKey: .cursorPendingWrap)
        try c.encode(cursorHidden, forKey: .cursorHidden)
        try c.encode(cursorOnScreen, forKey: .cursorOnScreen)
        try c.encodeIfPresent(cursorViewportCol, forKey: .cursorViewportCol)
        try c.encodeIfPresent(cursorViewportRow, forKey: .cursorViewportRow)
        try c.encode(bufferKind, forKey: .bufferKind)
        try c.encode(isAlternateScreen, forKey: .isAlternateScreen)
        try c.encode(scrolledRows, forKey: .scrolledRows)
        try c.encode(trimRight, forKey: .trimRight)
        try c.encode(viewportText, forKey: .viewportText)
        try c.encode(String(contentHash), forKey: .contentHash)
        try c.encode(modes, forKey: .modes)
        try c.encode(kittyKeyboard, forKey: .kittyKeyboard)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cols = try c.decode(Int.self, forKey: .cols)
        rows = try c.decode(Int.self, forKey: .rows)
        cursorEngineCol = try c.decode(Int.self, forKey: .cursorEngineCol)
        cursorEngineRow = try c.decode(Int.self, forKey: .cursorEngineRow)
        cursorPendingWrap = try c.decode(Bool.self, forKey: .cursorPendingWrap)
        cursorHidden = try c.decode(Bool.self, forKey: .cursorHidden)
        cursorOnScreen = try c.decode(Bool.self, forKey: .cursorOnScreen)
        cursorViewportCol = try c.decodeIfPresent(Int.self, forKey: .cursorViewportCol)
        cursorViewportRow = try c.decodeIfPresent(Int.self, forKey: .cursorViewportRow)
        bufferKind = try c.decode(String.self, forKey: .bufferKind)
        isAlternateScreen = try c.decode(Bool.self, forKey: .isAlternateScreen)
        scrolledRows = try c.decode(Int.self, forKey: .scrolledRows)
        trimRight = try c.decode(Bool.self, forKey: .trimRight)
        viewportText = try c.decode([String].self, forKey: .viewportText)
        let hashString = try c.decode(String.self, forKey: .contentHash)
        guard let parsed = UInt64(hashString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .contentHash,
                in: c,
                debugDescription: "content_hash must be a decimal string of UInt64"
            )
        }
        contentHash = parsed
        modes = try c.decode(TerminalModeSummary.self, forKey: .modes)
        kittyKeyboard = try c.decode(KittyKeyboardInspection.self, forKey: .kittyKeyboard)
    }
}

extension TerminalModeSummary: Codable {
    enum CodingKeys: String, CodingKey {
        case applicationCursor = "application_cursor"
        case applicationKeypad = "application_keypad"
        case bracketedPaste = "bracketed_paste"
        case originMode = "origin_mode"
        case marginMode = "margin_mode"
        case wraparound
        case insertMode = "insert_mode"
        case synchronizedOutputActive = "synchronized_output_active"
        case mouseMode = "mouse_mode"
        case mouseProtocol = "mouse_protocol"
        case mouseShiftCapture = "mouse_shift_capture"
    }
}

extension KittyKeyboardInspection: Codable {
    enum CodingKeys: String, CodingKey {
        case active
        case flagsRaw = "flags_raw"
        case flags
        case stackDepth = "stack_depth"
        case buffer
        case otherBufferFlagsRaw = "other_buffer_flags_raw"
        case otherBufferStackDepth = "other_buffer_stack_depth"
    }
}

// MARK: - Terminal.inspect

extension Terminal {
    /// Captures a point-in-time **core engine** inspection snapshot.
    ///
    /// Must run on the same serial executor that owns feed/resize/timer mutations
    /// for this terminal. Concurrent use with feed/resize is undefined behavior.
    ///
    /// - Parameter trimRight: when true (default), trailing empty cells are trimmed
    ///   per `BufferLine.getTrimmedLength` (nonzero codes including U+0020 stop trim).
    public func inspect(trimRight: Bool = true) -> TerminalInspectionSnapshot {
        let b = buffer
        let isAlt = isCurrentBufferAlternate
        let bufferKind = isAlt ? "alt" : "normal"

        var viewportText: [String] = []
        viewportText.reserveCapacity(rows)
        for r in 0..<rows {
            viewportText.append(inspectViewportRowText(row: r, trimRight: trimRight))
        }
        let contentHash = Self.computeInspectionContentHash(
            trimRight: trimRight,
            viewportText: viewportText
        )

        let pendingWrap = b.x >= cols
        // Paint projection (CoreGraphics clamps pending wrap to last column).
        let projectedCol: Int = pendingWrap ? max(cols - 1, 0) : b.x
        let projectedRow: Int = b.yBase + b.y - b.yDisp
        let rowOnScreen = projectedRow >= 0 && projectedRow < rows
        let colOnScreen = projectedCol >= 0 && projectedCol < cols
        let onScreen = !cursorHidden && rowOnScreen && colOnScreen
        let viewportCol: Int? = colOnScreen ? projectedCol : nil
        let viewportRow: Int? = rowOnScreen ? projectedRow : nil

        let activeMode = isAlt ? keyboardModeAlt : keyboardModeNormal
        let otherMode = isAlt ? keyboardModeNormal : keyboardModeAlt

        return TerminalInspectionSnapshot(
            cols: cols,
            rows: rows,
            cursorEngineCol: b.x,
            cursorEngineRow: b.y,
            cursorPendingWrap: pendingWrap,
            cursorHidden: cursorHidden,
            cursorOnScreen: onScreen,
            cursorViewportCol: onScreen ? viewportCol : (viewportCol.flatMap { $0 >= 0 && $0 < cols ? $0 : nil }),
            cursorViewportRow: viewportRow,
            bufferKind: bufferKind,
            isAlternateScreen: isAlt,
            scrolledRows: b.yBase - b.yDisp,
            trimRight: trimRight,
            viewportText: viewportText,
            contentHash: contentHash,
            modes: TerminalModeSummary(
                applicationCursor: applicationCursor,
                applicationKeypad: applicationKeypad,
                bracketedPaste: bracketedPasteMode,
                originMode: originMode,
                marginMode: marginMode,
                wraparound: wraparound,
                insertMode: insertMode,
                synchronizedOutputActive: synchronizedOutputActive,
                mouseMode: Self.mouseModeWireName(mouseMode),
                mouseProtocol: Self.mouseProtocolWireName(mouseProtocol),
                mouseShiftCapture: mouseShiftCapture
            ),
            kittyKeyboard: KittyKeyboardInspection(
                active: !activeMode.flags.isEmpty,
                flagsRaw: activeMode.flags.rawValue,
                flags: Self.kittyFlagNames(activeMode.flags),
                stackDepth: activeMode.stack.count,
                buffer: bufferKind,
                otherBufferFlagsRaw: otherMode.flags.rawValue,
                otherBufferStackDepth: otherMode.stack.count
            )
        )
    }

    /// Frozen viewport row extraction (design PR1).
    func inspectViewportRowText(row: Int, trimRight: Bool) -> String {
        guard row >= 0, row < rows else { return "" }
        let lineIndex = buffer.yDisp + row
        guard lineIndex >= 0, lineIndex < buffer.lines.count else { return "" }
        let line = buffer.lines[lineIndex]
        return line.translateToString(
            trimRight: trimRight,
            startCol: 0,
            endCol: -1,
            skipNullCellsFollowingWide: true,
            characterProvider: { [weak self] charData in
                guard let self else { return charData.getCharacter() }
                return self.getCharacter(for: charData)
            }
        )
    }

    static func computeInspectionContentHash(trimRight: Bool, viewportText: [String]) -> UInt64 {
        var data = Data()
        let header = "trimRight=\(trimRight ? "1" : "0")\n"
        data.append(contentsOf: header.utf8)
        for row in viewportText {
            data.append(contentsOf: row.utf8)
            data.append(0x0A)
        }
        return TerminalInspectionHash.fnv1a64(data: data)
    }

    static func mouseModeWireName(_ mode: MouseMode) -> String {
        switch mode {
        case .off: return "off"
        case .x10: return "x10"
        case .vt200: return "vt200"
        case .buttonEventTracking: return "buttonEvent"
        case .anyEvent: return "anyEvent"
        }
    }

    static func mouseProtocolWireName(_ protocol: MouseProtocolEncoding) -> String {
        switch `protocol` {
        case .x10: return "x10"
        case .utf8: return "utf8"
        case .sgr: return "sgr"
        case .urxvt: return "urxvt"
        case .sgrPixel: return "sgrPixel"
        }
    }

    static func kittyFlagNames(_ flags: KittyKeyboardFlags) -> [String] {
        var names: [String] = []
        if flags.contains(.disambiguate) { names.append("disambiguate") }
        if flags.contains(.reportEvents) { names.append("reportEvents") }
        if flags.contains(.reportAlternates) { names.append("reportAlternates") }
        if flags.contains(.reportAllKeys) { names.append("reportAllKeys") }
        if flags.contains(.reportText) { names.append("reportText") }
        return names
    }
}

// MARK: - View geometry + input policy (PR2)

#if canImport(AppKit) || canImport(UIKit)

/// View-side grid fit geometry (points). Core-engine grid is still in ``TerminalInspectionSnapshot``.
public struct TerminalViewGeometrySnapshot: Sendable, Equatable {
    public var cellWidthPoints: Double
    public var cellHeightPoints: Double
    public var boundsWidthPoints: Double
    public var boundsHeightPoints: Double
    /// Result of `getEffectiveWidth` — width used for cols = floor(effective / cellWidth).
    public var effectiveGridWidthPoints: Double
    /// `boundsWidth - effectiveGridWidth` (scroller reservation on macOS legacy scrollers; 0 on iOS).
    public var scrollerReservedWidthPoints: Double
    public var scaleFactor: Double
    public var autoResizeGrid: Bool
    public var engineCols: Int
    public var engineRows: Int
}

/// View-level input policy that is not pure engine state.
public struct TerminalViewInputPolicySnapshot: Sendable, Equatable {
    public var allowMouseReporting: Bool
}

/// Combined engine + view inspection for a live `TerminalView`.
public struct TerminalViewInspectionSnapshot: Sendable, Equatable {
    public var terminal: TerminalInspectionSnapshot
    public var geometry: TerminalViewGeometrySnapshot
    public var inputPolicy: TerminalViewInputPolicySnapshot
}

extension TerminalViewGeometrySnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case cellWidthPoints = "cell_width_points"
        case cellHeightPoints = "cell_height_points"
        case boundsWidthPoints = "bounds_width_points"
        case boundsHeightPoints = "bounds_height_points"
        case effectiveGridWidthPoints = "effective_grid_width_points"
        case scrollerReservedWidthPoints = "scroller_reserved_width_points"
        case scaleFactor = "scale_factor"
        case autoResizeGrid = "auto_resize_grid"
        case engineCols = "engine_cols"
        case engineRows = "engine_rows"
    }
}

extension TerminalViewInputPolicySnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case allowMouseReporting = "allow_mouse_reporting"
    }
}

extension TerminalViewInspectionSnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case terminal
        case geometry
        case inputPolicy = "input_policy"
    }
}

extension TerminalView {
    /// Capture grid-fit geometry. Call on the main actor / view mutation queue.
    public func inspectGeometry() -> TerminalViewGeometrySnapshot {
        let cell = cellDimension ?? .zero
        let boundsSize = bounds.size
        let effective = getEffectiveWidth(size: boundsSize)
        let reserved = max(0, boundsSize.width - effective)
        let scale = inspectionScaleFactor()
        let engine = terminal
        return TerminalViewGeometrySnapshot(
            cellWidthPoints: Double(cell.width),
            cellHeightPoints: Double(cell.height),
            boundsWidthPoints: Double(boundsSize.width),
            boundsHeightPoints: Double(boundsSize.height),
            effectiveGridWidthPoints: Double(effective),
            scrollerReservedWidthPoints: Double(reserved),
            scaleFactor: Double(scale),
            autoResizeGrid: autoResizeGrid,
            engineCols: engine?.cols ?? 0,
            engineRows: engine?.rows ?? 0
        )
    }

    /// Capture view input policy (mouse forwarding gate).
    public func inspectInputPolicy() -> TerminalViewInputPolicySnapshot {
        TerminalViewInputPolicySnapshot(allowMouseReporting: allowMouseReporting)
    }

    /// Engine + geometry + input policy in one capture on the view's mutation context.
    public func inspectAll(trimRight: Bool = true) -> TerminalViewInspectionSnapshot {
        let term = terminal!
        return TerminalViewInspectionSnapshot(
            terminal: term.inspect(trimRight: trimRight),
            geometry: inspectGeometry(),
            inputPolicy: inspectInputPolicy()
        )
    }

    private func inspectionScaleFactor() -> CGFloat {
        #if os(macOS)
        if let windowScale = window?.backingScaleFactor, windowScale > 0 {
            return windowScale
        }
        if let screenScale = NSScreen.main?.backingScaleFactor, screenScale > 0 {
            return screenScale
        }
        return 1
        #else
        if let windowScale = window?.contentScaleFactor, windowScale > 0 {
            return windowScale
        }
        return traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        #endif
    }
}

#endif

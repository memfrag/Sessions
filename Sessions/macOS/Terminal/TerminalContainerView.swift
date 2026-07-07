//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit

/// Layer-backed container that provides the terminal's inner margin and
/// paints it in the terminal's background color.
///
/// The hosted terminal view is laid out in `layout()` rather than with
/// autoresizing: the container is created with a zero frame, and insetting
/// a zero rect yields a negative-size frame that autoresizing would then
/// propagate garbage from.
///
/// Uses `updateLayer` so dynamic colors (the system theme's
/// `textBackgroundColor`) re-resolve when the effective appearance changes.
final class TerminalContainerView: NSView {

    /// Inner margin between the container edge and the terminal content.
    static let inset: CGFloat = 2

    /// The terminal view to keep inset within the container.
    weak var hostedView: NSView? {
        didSet {
            needsLayout = true
        }
    }

    var backgroundColor: NSColor = .textBackgroundColor {
        didSet {
            needsDisplay = true
        }
    }

    override var wantsUpdateLayer: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        guard let hostedView else { return }
        let inset = Self.inset
        guard bounds.width > inset * 2, bounds.height > inset * 2 else {
            hostedView.frame = bounds
            return
        }
        hostedView.frame = bounds.insetBy(dx: inset, dy: inset)
    }

    override func updateLayer() {
        layer?.backgroundColor = backgroundColor.cgColor
    }
}

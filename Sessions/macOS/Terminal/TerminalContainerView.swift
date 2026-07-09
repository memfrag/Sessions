//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit

/// Layer-backed container that provides the terminal's inner margin and
/// paints it in the terminal's background color.
///
/// The hosted terminal view is positioned in `setFrameSize` (reliably
/// called on every resize, unlike `layout()` for a non-Auto-Layout view)
/// rather than with autoresizing, which would misbehave from the initial
/// zero frame.
///
/// Uses `updateLayer` so dynamic colors (the system theme's
/// `textBackgroundColor`) re-resolve when the effective appearance changes.
final class TerminalContainerView: NSView {

    /// Inner margin between the container edge and the terminal content.
    static let inset: CGFloat = 4

    /// The terminal view to keep inset within the container.
    weak var hostedView: NSView? {
        didSet {
            layoutHostedView()
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

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutHostedView()
    }

    override func layout() {
        super.layout()
        layoutHostedView()
    }

    private func layoutHostedView() {
        guard let hostedView else { return }
        let inset = Self.inset
        if bounds.width > inset * 2, bounds.height > inset * 2 {
            hostedView.frame = bounds.insetBy(dx: inset, dy: inset)
        } else {
            hostedView.frame = bounds
        }
    }

    override func updateLayer() {
        layer?.backgroundColor = backgroundColor.cgColor
    }
}

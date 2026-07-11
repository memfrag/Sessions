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

    /// Inner margins between the container edges and the terminal content.
    /// Zero for the Ghostty backend — the terminal fills the container and
    /// its inner margin comes from ghostty's `window-padding-*` config.
    static let leadingInset: CGFloat = 0
    static let trailingInset: CGFloat = 0
    static let topInset: CGFloat = 0
    static let bottomInset: CGFloat = 0

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
        let horizontal = Self.leadingInset + Self.trailingInset
        let vertical = Self.topInset + Self.bottomInset
        guard bounds.width > horizontal, bounds.height > vertical else {
            hostedView.frame = bounds
            return
        }
        // Non-flipped view: y origin is the bottom edge.
        hostedView.frame = NSRect(
            x: Self.leadingInset,
            y: Self.bottomInset,
            width: bounds.width - horizontal,
            height: bounds.height - vertical
        )
    }

    override func updateLayer() {
        layer?.backgroundColor = backgroundColor.cgColor
    }
}

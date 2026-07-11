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

    /// Handles file URLs dropped onto the terminal. Returns whether the drop
    /// was accepted. Set by the hosting representable.
    ///
    /// The drop is handled here in AppKit rather than with a SwiftUI
    /// `.dropDestination` because the terminal engine's Metal view fills the
    /// container and shadows SwiftUI's drop target. The Metal view doesn't
    /// register for dragged types, so the drag falls through to this
    /// registered superview.
    var onDropFileURLs: (([URL]) -> Bool)?

    override var wantsUpdateLayer: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    /// Registers/unregisters as a file-drop destination. Only the selected
    /// tab enables drops: every tab in a workspace stays mounted and stacked
    /// in the same place, so if they all registered, AppKit would route a
    /// drop to whichever it hit first rather than the visible tab. An
    /// unregistered sibling is transparent to drag hit-testing, so the
    /// selected (registered) container receives the drop even when stacked.
    func setDropEnabled(_ enabled: Bool) {
        if enabled {
            registerForDraggedTypes([.fileURL])
        } else {
            unregisterDraggedTypes()
        }
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

    // MARK: - Drag & drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFileURLs(sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFileURLs(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedFileURLs(sender)
        guard !urls.isEmpty else { return false }
        return onDropFileURLs?(urls) ?? false
    }

    private func droppedFileURLs(_ sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }
}

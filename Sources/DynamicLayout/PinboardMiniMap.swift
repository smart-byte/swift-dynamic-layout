//
//  PinboardMiniMap.swift
//
//
//  Created by Mario Heubach on 29.04.26.
//

import AppKit
import SwiftUI

// MARK: - Corner anchor for snap-to-corner docking

/// The four corners a mini-map can be docked to.
public enum MiniMapCorner: CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    /// The SwiftUI alignment corresponding to this corner.
    public var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }
}

/// What a drag inside the mini-map does. Toggled by the host via the
/// pinboard inline-toolbar so the user can choose between aiming the
/// canvas viewport (`.pan`) and repositioning the widget (`.move`).
public enum MiniMapDragMode: CaseIterable {
    case pan
    case move
}

// MARK: - PinboardMiniMap

/// Floating 140×140 thumbnail of the 4 000×4 000 pinboard canvas.
///
/// Renders every item as a proportional filled rectangle and overlays a
/// viewport rectangle (accent-coloured stroke + semi-transparent fill).
/// The widget is draggable; on release it snaps to the nearest corner with
/// a spring animation. Tapping scrolls the canvas to centre on that point;
/// dragging pans it continuously. The host side decides the corner via the
/// `corner` binding so the state survives SwiftUI re-renders inside the pane.
public struct PinboardMiniMap: View {
    // MARK: Inputs

    /// Full canvas dimensions — always 4 000×4 000 for now.
    public let canvasSize: CGSize
    /// Current items on the canvas.
    public let items: [PinboardCanvasItemData]
    /// Top-left of the visible region in canvas coordinates.
    public let viewportOrigin: CGPoint
    /// Visible area in canvas coordinates (clip-view size / magnification).
    public let viewportSize: CGSize
    /// Called when the user taps or drags; argument is the new desired
    /// *top-left* of the viewport in canvas coordinates.
    public let onScrollTo: (CGPoint) -> Void
    /// Binding that lets the host persist the docked corner across re-renders.
    @Binding public var corner: MiniMapCorner
    /// What a drag does — pan the canvas or reposition the widget.
    public let dragMode: MiniMapDragMode
    /// Size of the host area the mini-map floats in. Used to compute the
    /// geometric centre of each corner slot so `.move`-mode releases snap
    /// to the corner whose centre is closest to where the user let go,
    /// rather than to a corner picked from drag direction alone.
    public let hostSize: CGSize

    // MARK: - Init

    public init(
        canvasSize: CGSize,
        items: [PinboardCanvasItemData],
        viewportOrigin: CGPoint,
        viewportSize: CGSize,
        onScrollTo: @escaping (CGPoint) -> Void,
        corner: Binding<MiniMapCorner>,
        dragMode: MiniMapDragMode = .pan,
        hostSize: CGSize = .zero
    ) {
        self.canvasSize = canvasSize
        self.items = items
        self.viewportOrigin = viewportOrigin
        self.viewportSize = viewportSize
        self.onScrollTo = onScrollTo
        _corner = corner
        self.dragMode = dragMode
        self.hostSize = hostSize
    }

    // MARK: Private state (view-session only)

    /// Whether the cursor is hovering (drives open/closed hand).
    @State private var isHovering: Bool = false
    /// Whether the user is currently panning via mouse-drag.
    @State private var isPanning: Bool = false
    /// Live drag offset while the user repositions the widget in `.move` mode.
    @State private var dragOffset: CGSize = .zero

    // MARK: Layout constants

    private static let size: CGFloat = 140
    private static let cornerRadius: CGFloat = 8
    /// Inset between the mini-map's edge and the host's corner. Must
    /// match the `.padding(16)` on the call site so the corner-centre
    /// math agrees with the actual rendered position.
    private static let edgeInset: CGFloat = 16

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Background material + border
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(.separator, lineWidth: 0.5)

            // Canvas thumbnail
            Canvas { context, size in
                drawItems(context: context, size: size)
                drawViewport(context: context, size: size)
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .frame(width: Self.size, height: Self.size)
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
        .offset(dragOffset)
        // Cursor feedback — pan mode aims, move mode grabs.
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovering = true
                setHoverCursor()
            case .ended:
                isHovering = false
                NSCursor.arrow.set()
            }
        }
        // Single gesture branches on `dragMode`:
        // `.pan`  — drag aims the canvas viewport at the cursor.
        // `.move` — drag offsets the widget; on release it springs to
        //          the corner matching the drag direction.
        .gesture(unifiedGesture())
        // Right-click → corner-dock submenu (always available regardless
        // of mode, complements the move-drag flow).
        .contextMenu {
            Picker("Dock to", selection: $corner) {
                Text("Top Left").tag(MiniMapCorner.topLeading)
                Text("Top Right").tag(MiniMapCorner.topTrailing)
                Text("Bottom Left").tag(MiniMapCorner.bottomLeading)
                Text("Bottom Right").tag(MiniMapCorner.bottomTrailing)
            }
        }
    }

    private func setHoverCursor() {
        switch dragMode {
        case .pan: NSCursor.crosshair.set()
        case .move: NSCursor.openHand.set()
        }
    }

    // MARK: - Drawing helpers

    /// Converts a point in canvas coordinates to mini-map coordinates.
    private func canvasToMap(_ point: CGPoint, mapSize: CGSize) -> CGPoint {
        CGPoint(
            x: point.x / canvasSize.width * mapSize.width,
            y: point.y / canvasSize.height * mapSize.height
        )
    }

    /// Converts a size in canvas coordinates to mini-map coordinates.
    private func canvasToMapSize(_ size: CGSize, mapSize: CGSize) -> CGSize {
        CGSize(
            width: size.width / canvasSize.width * mapSize.width,
            height: size.height / canvasSize.height * mapSize.height
        )
    }

    private func drawItems(context: GraphicsContext, size: CGSize) {
        for item in items {
            let origin = canvasToMap(
                CGPoint(x: item.positionX, y: item.positionY),
                mapSize: size
            )
            let itemSize = canvasToMapSize(
                CGSize(width: item.width, height: item.height),
                mapSize: size
            )
            let rect = CGRect(origin: origin, size: itemSize)
            // Clamp to at least 2×2 so even tiny items remain visible.
            let clampedRect = CGRect(
                x: rect.origin.x,
                y: rect.origin.y,
                width: max(rect.width, 2),
                height: max(rect.height, 2)
            )
            context.fill(
                Path(roundedRect: clampedRect, cornerRadius: 1),
                with: .foreground
            )
        }
    }

    private func drawViewport(context: GraphicsContext, size: CGSize) {
        let origin = canvasToMap(viewportOrigin, mapSize: size)
        let vpSize = canvasToMapSize(viewportSize, mapSize: size)
        let rawRect = CGRect(origin: origin, size: vpSize)
        // Clamp the viewport visualisation to the mini-map's drawable
        // area. When the user scrolls to a canvas edge or zooms out so
        // that the viewport exceeds the canvas, the raw rect would
        // otherwise spill past the rounded glass frame and look
        // truncated rather than bounded.
        let bounds = CGRect(origin: .zero, size: size)
        let rect = rawRect.intersection(bounds)
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }

        // Semi-transparent fill
        context.fill(
            Path(rect),
            with: .color(.accentColor.opacity(0.15))
        )
        // Accent stroke. Inset by half the line width so the stroke sits
        // fully inside the clamped rect — otherwise a 1.5pt-wide line
        // centred on the edge has 0.75pt rendered outside the glass.
        let strokeWidth: CGFloat = 1.5
        let inset = strokeWidth / 2
        let strokeRect = rect.insetBy(dx: inset, dy: inset)
        guard strokeRect.width > 0, strokeRect.height > 0 else { return }
        context.stroke(
            Path(strokeRect),
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: strokeWidth)
        )
    }

    // MARK: - Gesture

    private func unifiedGesture() -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                switch dragMode {
                case .pan:
                    if !isPanning {
                        isPanning = true
                        if isHovering { NSCursor.closedHand.set() }
                    }
                    scrollCanvas(toCenterOn: value.location)
                case .move:
                    if isHovering { NSCursor.closedHand.set() }
                    dragOffset = value.translation
                }
            }
            .onEnded { value in
                switch dragMode {
                case .pan:
                    // Single tap (no drag motion) still routes through the
                    // pan path — `onChanged` may not fire for a 0-distance
                    // click.
                    if !isPanning {
                        scrollCanvas(toCenterOn: value.location)
                    }
                    isPanning = false
                case .move:
                    snapToNearestCorner(after: value)
                }
                if isHovering { setHoverCursor() }
            }
    }

    /// Picks the corner whose centre is closest to where the user let go
    /// of the mini-map. Position-based (not direction-based) so a small
    /// nudge keeps the current corner instead of jumping diagonally on a
    /// stray pixel of negative translation.
    private func nearestCorner(for value: DragGesture.Value) -> MiniMapCorner {
        guard hostSize.width > 0, hostSize.height > 0 else { return corner }
        let releasedCentre = releasedCentre(for: value)
        return MiniMapCorner.allCases.min { lhs, rhs in
            let dl = distance(from: cornerCentre(for: lhs), to: releasedCentre)
            let dr = distance(from: cornerCentre(for: rhs), to: releasedCentre)
            return dl < dr
        } ?? corner
    }

    /// Geometric centre of the mini-map when docked to `corner`, in host
    /// coordinates. Driven by `Self.edgeInset` (= padding on the call site)
    /// + half the widget size.
    private func cornerCentre(for corner: MiniMapCorner) -> CGPoint {
        let inset = Self.edgeInset + Self.size / 2
        switch corner {
        case .topLeading: return CGPoint(x: inset, y: inset)
        case .topTrailing: return CGPoint(x: hostSize.width - inset, y: inset)
        case .bottomLeading: return CGPoint(x: inset, y: hostSize.height - inset)
        case .bottomTrailing: return CGPoint(
                x: hostSize.width - inset,
                y: hostSize.height - inset
            )
        }
    }

    /// Where the mini-map's centre actually sits at the moment the drag
    /// ends — current corner's centre plus the live drag translation.
    private func releasedCentre(for value: DragGesture.Value) -> CGPoint {
        let base = cornerCentre(for: corner)
        return CGPoint(
            x: base.x + value.translation.width,
            y: base.y + value.translation.height
        )
    }

    private func distance(from a: CGPoint, to b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Animates the mini-map from its **released position** to the target
    /// corner. We pick the new corner geometrically (`nearestCorner`),
    /// then set `corner` and a *compensating* `dragOffset` in lock-step
    /// so the widget visually stays at the release position despite the
    /// alignment switch — finally springing the offset back to zero
    /// produces the natural "fly to corner" motion.
    private func snapToNearestCorner(after value: DragGesture.Value) {
        let target = nearestCorner(for: value)
        let released = releasedCentre(for: value)
        let newCentre = cornerCentre(for: target)
        let compensation = CGSize(
            width: released.x - newCentre.x,
            height: released.y - newCentre.y
        )
        corner = target
        dragOffset = compensation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = .zero
        }
    }

    /// Scrolls the canvas so `localPoint` (within the mini-map's bounds)
    /// becomes the centre of the visible viewport.
    private func scrollCanvas(toCenterOn localPoint: CGPoint) {
        let canvasPoint = mapPointToCanvas(localPoint)
        let newOrigin = CGPoint(
            x: canvasPoint.x - viewportSize.width / 2,
            y: canvasPoint.y - viewportSize.height / 2
        )
        onScrollTo(newOrigin)
    }

    /// Converts a point in the mini-map's local coordinate space (0…140)
    /// into canvas coordinates (0…canvasSize).
    private func mapPointToCanvas(_ localPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (localPoint.x / Self.size) * canvasSize.width,
            y: (localPoint.y / Self.size) * canvasSize.height
        )
    }
}

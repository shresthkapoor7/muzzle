import AppKit

enum MuzzleIcon {
    static func statusImage(isActive: Bool, fillFraction: CGFloat = 1) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let mask = maskPath()
            NSColor.black.setStroke()
            NSColor.black.setFill()

            if isActive {
                let fraction = min(max(fillFraction, 0), 1)
                mask.lineWidth = 1.65
                mask.stroke()
                NSGraphicsContext.saveGraphicsState()
                mask.addClip()
                let maskBounds = mask.bounds
                NSBezierPath(
                    rect: NSRect(
                        x: maskBounds.minX,
                        y: maskBounds.minY,
                        width: maskBounds.width,
                        height: maskBounds.height * fraction
                    )
                ).fill()
                NSGraphicsContext.current?.compositingOperation = .clear
                drawGrille()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                mask.lineWidth = 1.65
                mask.stroke()
                drawGrille()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func alertImage() -> NSImage {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size, flipped: false) { _ in
            let background = NSBezierPath(
                roundedRect: NSRect(x: 1, y: 1, width: 62, height: 62),
                xRadius: 14,
                yRadius: 14
            )
            NSColor.black.setFill()
            background.fill()

            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: 8, yBy: 8)
            transform.scale(by: 2.6667)
            transform.concat()

            NSColor.white.setFill()
            maskPath().fill()
            NSColor.black.setStroke()
            drawGrille()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        return image
    }

    private static func maskPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 4.1, y: 15.2))
        path.line(to: NSPoint(x: 13.9, y: 15.2))
        path.line(to: NSPoint(x: 16.4, y: 11.3))
        path.line(to: NSPoint(x: 14.5, y: 2.5))
        path.line(to: NSPoint(x: 3.5, y: 2.5))
        path.line(to: NSPoint(x: 1.6, y: 11.3))
        path.close()
        return path
    }

    private static func drawGrille() {
        for y in [6.0, 9.0, 12.0] {
            let grille = NSBezierPath()
            grille.move(to: NSPoint(x: 5.1, y: y))
            grille.line(to: NSPoint(x: 12.9, y: y))
            grille.lineWidth = 1.2
            grille.stroke()
        }
    }
}

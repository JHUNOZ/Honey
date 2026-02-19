import Cocoa

// ══════════════════════════════════════════════════════════════
//  HONEYCOMB VIEW — decorative background (replaces pictureBox1)
//  Drawn with CoreGraphics — no assets needed
// ══════════════════════════════════════════════════════════════

final class HoneycombView: NSView {

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Gradient background
        let colors = [
            NSColor(red: 0.00, green: 0.00, blue: 0.30, alpha: 1.0).cgColor,
            NSColor(red: 0.05, green: 0.05, blue: 0.50, alpha: 1.0).cgColor,
            NSColor(red: 0.10, green: 0.10, blue: 0.70, alpha: 0.8).cgColor
        ] as CFArray

        let locations: [CGFloat] = [0.0, 0.5, 1.0]
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors, locations: locations) {
            ctx.drawLinearGradient(grad,
                                   start: CGPoint(x: 0, y: 0),
                                   end:   CGPoint(x: bounds.width, y: bounds.height),
                                   options: [])
        }

        // Draw honeycomb hexagons
        let hexR: CGFloat = 18.0
        let hexW   = hexR * 2.0
        let hexH   = hexR * sqrt(3.0)
        let colSep = hexW * 0.75
        let rowSep = hexH

        ctx.setLineWidth(0.8)

        var col = 0
        var xPos: CGFloat = -hexR

        while xPos < bounds.width + hexR {
            let yOff: CGFloat = col % 2 == 0 ? 0 : hexH / 2.0
            var yPos: CGFloat = -hexH / 2.0 + yOff

            while yPos < bounds.height + hexH {
                let alpha = CGFloat.random(in: 0.04...0.14)
                ctx.setStrokeColor(NSColor(red: 0.9, green: 0.8, blue: 0.2, alpha: alpha).cgColor)
                ctx.setFillColor(NSColor(red: 0.9, green: 0.8, blue: 0.1, alpha: alpha * 0.3).cgColor)

                let path = hexagonPath(center: CGPoint(x: xPos, y: yPos), radius: hexR)
                ctx.addPath(path)
                ctx.drawPath(using: .fillStroke)

                yPos += rowSep
            }

            xPos += colSep
            col  += 1
        }

        // "Honey" title text
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont(name: "Georgia-BoldItalic", size: 32) ?? .boldSystemFont(ofSize: 32),
            .foregroundColor: NSColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 0.85),
            .paragraphStyle:  pStyle
        ]
        let title = NSAttributedString(string: "🍯 Honey", attributes: attrs)
        let titleRect = NSRect(x: 0, y: bounds.height - 60, width: bounds.width, height: 48)
        title.draw(in: titleRect)

        // Subtitle
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont(name: "Menlo", size: 8) ?? .monospacedSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: NSColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 0.7),
            .paragraphStyle:  pStyle
        ]
        let sub = NSAttributedString(string: "AutoClick Engine for macOS", attributes: subAttrs)
        let subRect = NSRect(x: 0, y: bounds.height - 78, width: bounds.width, height: 18)
        sub.draw(in: subRect)
    }

    private func hexagonPath(center: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3.0 - .pi / 6.0
            let pt    = CGPoint(x: center.x + radius * cos(angle),
                                y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: pt) }
            else       { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

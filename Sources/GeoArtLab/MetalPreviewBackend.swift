import AppKit
import Foundation
import Metal

struct MetalPreviewFrame {
    var image: NSImage
    var renderMillis: Double
    var sceneShapeCount: Int
    var deviceName: String
}

final class MetalPreviewBackend {
    private let device: MTLDevice?

    init() {
        self.device = MTLCreateSystemDefaultDevice()
    }

    var isAvailable: Bool {
        device != nil
    }

    func renderPreview(
        params: RenderParameters,
        canvas: CanvasSettings,
        seed overrideSeed: Int? = nil
    ) -> MetalPreviewFrame? {
        guard let device else { return nil }

        let scene = SwiftRenderCore.sampleScene(params: params, canvas: canvas, seed: overrideSeed)
        guard scene.width > 0, scene.height > 0 else { return nil }

        let started = CFAbsoluteTimeGetCurrent()
        let size = NSSize(width: scene.width, height: scene.height)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

        ctx.setFillColor(backgroundColor(for: params.backgroundStyle).cgColor)
        ctx.fill(CGRect(origin: .zero, size: CGSize(width: scene.width, height: scene.height)))

        let palette = PaletteLibrary.colors(for: params)
        let paletteFallback = NSColor.white.cgColor

        for sample in scene.samples {
            let stroke = CGFloat(max(0.5, min(params.strokeWidths[sample.kind], 18)))
            let colorHex = palette.isEmpty ? "" : palette[sample.colorIndex % palette.count]
            let color = nsColor(hex: colorHex)?.cgColor ?? paletteFallback

            ctx.saveGState()
            ctx.translateBy(x: sample.x, y: sample.y)
            ctx.rotate(by: CGFloat(sample.angleDeg * .pi / 180.0))
            ctx.setStrokeColor(color)
            ctx.setFillColor(color)
            ctx.setLineWidth(stroke)

            let size = CGFloat(max(2.0, sample.size))
            switch sample.kind {
            case .circle:
                let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
                if sample.filled {
                    ctx.fillEllipse(in: rect)
                }
                ctx.strokeEllipse(in: rect)
            case .triangle:
                let half = size / 2
                ctx.beginPath()
                ctx.move(to: CGPoint(x: 0, y: half))
                ctx.addLine(to: CGPoint(x: -half, y: -half))
                ctx.addLine(to: CGPoint(x: half, y: -half))
                ctx.closePath()
                if sample.filled {
                    ctx.drawPath(using: .fillStroke)
                } else {
                    ctx.strokePath()
                }
            case .rectangle:
                let rect = CGRect(x: -size / 2, y: -size * 0.36, width: size, height: size * 0.72)
                if sample.filled {
                    ctx.fill(rect)
                }
                ctx.stroke(rect)
            case .line:
                let length = size * 1.25
                ctx.beginPath()
                ctx.move(to: CGPoint(x: -length / 2, y: 0))
                ctx.addLine(to: CGPoint(x: length / 2, y: 0))
                ctx.strokePath()
            }

            ctx.restoreGState()
        }

        let renderMillis = (CFAbsoluteTimeGetCurrent() - started) * 1000
        return MetalPreviewFrame(
            image: image,
            renderMillis: renderMillis,
            sceneShapeCount: scene.samples.count,
            deviceName: device.name
        )
    }

    private func backgroundColor(for style: BackgroundStyle) -> NSColor {
        switch style {
        case .paper:
            return NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.90, alpha: 1)
        case .midnight:
            return NSColor(calibratedRed: 0.02, green: 0.07, blue: 0.19, alpha: 1)
        case .warm:
            return NSColor(calibratedRed: 0.15, green: 0.07, blue: 0.03, alpha: 1)
        case .flat:
            return NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        case .pureBlack:
            return .black
        case .creme:
            return NSColor(calibratedRed: 0.96, green: 0.91, blue: 0.85, alpha: 1)
        }
    }

    private func nsColor(hex: String) -> NSColor? {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let hexValue = Int(value, radix: 16) else { return nil }
        let r = CGFloat((hexValue >> 16) & 0xFF) / 255.0
        let g = CGFloat((hexValue >> 8) & 0xFF) / 255.0
        let b = CGFloat(hexValue & 0xFF) / 255.0
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }
}

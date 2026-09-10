import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
        (transform as NSAffineTransform).concat()
        NSColor(calibratedRed: 0.78, green: 0.31, blue: 0.19, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 214, yRadius: 214).fill()
        NSColor(calibratedRed: 0.91, green: 0.80, blue: 0.61, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 255, y: 425, width: 490, height: 360), xRadius: 38, yRadius: 38).fill()
        NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.91, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 302, y: 382, width: 438, height: 351), xRadius: 35, yRadius: 35).fill()
        NSColor(calibratedRed: 0.27, green: 0.34, blue: 0.28, alpha: 1).setFill()
        let tray = NSBezierPath()
        tray.move(to: NSPoint(x: 193, y: 505)); tray.line(to: NSPoint(x: 405, y: 505))
        tray.line(to: NSPoint(x: 450, y: 425)); tray.line(to: NSPoint(x: 574, y: 425))
        tray.line(to: NSPoint(x: 619, y: 505)); tray.line(to: NSPoint(x: 831, y: 505))
        tray.line(to: NSPoint(x: 779, y: 236)); tray.line(to: NSPoint(x: 245, y: 236)); tray.close(); tray.fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon rendering failed") }
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png.write(to: output.appendingPathComponent(name))
    }
}

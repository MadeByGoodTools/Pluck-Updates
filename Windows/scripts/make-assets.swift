import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func save(_ name: String, draw: (NSRect) -> Void) throws {
    let size = NSSize(width: 256, height: 256)
    let image = NSImage(size: size)
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(origin: .zero, size: size))
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try png.write(to: output.appendingPathComponent(name))
}

func bird(in rect: NSRect, color: NSColor) {
    let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: x + 0.10*w, y: y + 0.15*h, width: 0.70*w, height: 0.70*h)).fill()
    let beak = NSBezierPath()
    beak.move(to: NSPoint(x: x + 0.68*w, y: y + 0.64*h))
    beak.line(to: NSPoint(x: x + 0.98*w, y: y + 0.50*h))
    beak.line(to: NSPoint(x: x + 0.68*w, y: y + 0.42*h))
    beak.close(); beak.fill()
    NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
    NSBezierPath(ovalIn: NSRect(x: x + 0.48*w, y: y + 0.61*h, width: 0.10*w, height: 0.10*h)).fill()
    NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
}

try save("pluck.png") { rect in
    let background = NSBezierPath(roundedRect: rect.insetBy(dx: 12, dy: 12), xRadius: 54, yRadius: 54)
    NSColor(calibratedRed: 0.67, green: 0.32, blue: 0.72, alpha: 1).setFill(); background.fill()
    bird(in: rect.insetBy(dx: 55, dy: 42), color: .white)
}

try save("app.png") { rect in
    let background = NSBezierPath(roundedRect: rect.insetBy(dx: 18, dy: 18), xRadius: 48, yRadius: 48)
    NSColor(calibratedWhite: 0.22, alpha: 1).setFill(); background.fill()
    let window = NSBezierPath(roundedRect: rect.insetBy(dx: 58, dy: 67), xRadius: 20, yRadius: 20)
    NSColor(calibratedRed: 0.67, green: 0.32, blue: 0.72, alpha: 1).setFill(); window.fill()
}

try save("folder.png") { rect in
    NSColor(calibratedRed: 0.67, green: 0.32, blue: 0.72, alpha: 1).setFill()
    let folder = NSBezierPath(roundedRect: NSRect(x: 31, y: 45, width: 194, height: 137), xRadius: 25, yRadius: 25)
    folder.fill()
    NSBezierPath(roundedRect: NSRect(x: 37, y: 164, width: 92, height: 43), xRadius: 15, yRadius: 15).fill()
}

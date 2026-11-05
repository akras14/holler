import AppKit
@testable import HollerKit

/// Renders the recording pill, mid-sentence, to a PNG at 2x for eyeballing its design.
@MainActor
func snapshotIndicator(to url: URL) {
    let view = BarsView(frame: NSRect(x: 0, y: 0, width: 88, height: 32))
    for level in [0.2, 0.5, 0.9, 0.7, 0.35, 0.8, 0.6, 0.3, 0.55] as [CGFloat] { view.push(level) }
    for _ in 0..<60 { view.tick() }
    let padded = NSView(frame: NSRect(x: 0, y: 0, width: 128, height: 64))
    padded.wantsLayer = true
    padded.layer?.backgroundColor = NSColor(white: 0.93, alpha: 1).cgColor
    view.setFrameOrigin(NSPoint(x: 20, y: 16))
    padded.addSubview(view)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 128, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = padded.bounds.size
    padded.cacheDisplay(in: padded.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

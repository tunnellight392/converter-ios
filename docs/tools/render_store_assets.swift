// Renders the App Store artwork in docs/ from the raw simulator screenshots:
//   • screenshots/<device>/captioned/*.png — each raw screenshot under a caption, on the app's
//     blue gradient, at the same pixel size as the raw one (so App Store Connect accepts it)
//   • banner-1024x500.png — a promotional banner with the app icon, name and tagline
//   • creative-assets/*.png — App Store featuring artwork (header and search-result sizes),
//     each text-free plus a "-text" version with the app name
//
// Run from the repo root:
//   swiftc -module-cache-path /tmp/swiftcache docs/tools/render_store_assets.swift -o /tmp/render_store_assets
//   /tmp/render_store_assets
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha
    ])!
}

// MARK: - Image I/O

func loadImage(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func makeContext(width: Int, height: Int) -> CGContext {
    // Opaque: App Store screenshots and banners must not have transparency.
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

func write(_ ctx: CGContext, to path: String) {
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                             withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(dest))
    print("wrote", path)
}

// MARK: - Drawing helpers (Core Graphics' own y-up coordinates)

/// The app's blue: lighter top-left to deeper bottom-right, with a soft highlight.
func drawBackground(_ ctx: CGContext, width: CGFloat, height: CGFloat) {
    let linear = CGGradient(colorsSpace: space, colors: [color(0x5A95F6), color(0x2563EB)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(linear, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, alpha: 0.18), color(0xFFFFFF, alpha: 0)] as CFArray, locations: [0, 1])!
    let center = CGPoint(x: width * 0.3, y: height * 0.85)
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: max(width, height) * 0.6, options: [])
}

func systemFont(size: CGFloat, bold: Bool) -> CTFont {
    let base = CTFontCreateUIFontForLanguage(.system, size, nil)!
    guard bold else { return base }
    return CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitBold, .traitBold) ?? base
}

/// Centred, wrapping text in `rect`, top-aligned. Returns the height actually used.
@discardableResult
func drawText(_ text: String, in rect: CGRect, size: CGFloat, bold: Bool, textColor: CGColor,
              alignment: CTTextAlignment = .center, ctx: CGContext) -> CGFloat {
    var align = alignment
    let paragraph = withUnsafeBytes(of: &align) { pointer in
        CTParagraphStyleCreate([CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size,
                                                        value: pointer.baseAddress!)], 1)
    }
    let attributed = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): systemFont(size: size, bold: bold),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): textColor,
        NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
    ])
    let setter = CTFramesetterCreateWithAttributedString(attributed)
    let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil,
                                                           CGSize(width: rect.width, height: .greatestFiniteMagnitude), nil)
    // Top-align within `rect`.
    let frameRect = CGRect(x: rect.minX, y: rect.maxY - ceil(fit.height), width: rect.width, height: ceil(fit.height))
    let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: frameRect, transform: nil), nil)
    CTFrameDraw(frame, ctx)
    return ceil(fit.height)
}

// MARK: - Captioned screenshots

struct Shot {
    let file: String
    let title: String
    let subtitle: String
}

let iPhoneShots = [
    Shot(file: "01-home", title: "Every unit, one tap away", subtitle: "Pin the conversions you use most"),
    Shot(file: "02-length", title: "Type it how you say it", subtitle: "5'11\", 12×3, 1½ — it just works"),
    Shot(file: "03-recipe", title: "Made for the kitchen", subtitle: "Cups, fractions and milliliters"),
    Shot(file: "04-clock", title: "Time zones, done right", subtitle: "Daylight saving handled for any date"),
    Shot(file: "05-pay", title: "Hourly, monthly, yearly", subtitle: "Worked out from your own hours"),
    Shot(file: "06-shoes", title: "Shoe and shirt sizes", subtitle: "US, UK and EU at a glance"),
    Shot(file: "07-search", title: "Find any unit fast", subtitle: "Search by name or symbol"),
    Shot(file: "08-dark", title: "Easy on the eyes", subtitle: "No ads. No tracking. Works offline.")
]

let iPadShots = [
    Shot(file: "01-home", title: "Every unit, one tap away", subtitle: "Pin the conversions you use most"),
    Shot(file: "02-length", title: "Type it how you say it", subtitle: "5'11\", 12×3, 1½ — it just works"),
    Shot(file: "03-clock", title: "Time zones, done right", subtitle: "Daylight saving handled for any date"),
    Shot(file: "04-dark", title: "Easy on the eyes", subtitle: "No ads. No tracking. Works offline.")
]

func renderCaptioned(_ shots: [Shot], device: String) {
    for shot in shots {
        let rawPath = "docs/screenshots/\(device)/raw/\(shot.file).png"
        guard let raw = loadImage(rawPath) else { print("missing", rawPath); continue }
        let width = CGFloat(raw.width), height = CGFloat(raw.height)
        let ctx = makeContext(width: raw.width, height: raw.height)
        drawBackground(ctx, width: width, height: height)

        // Caption block across the top.
        let unit = min(width, height * 0.5)
        let margin = width * 0.08
        let captionTop = height - height * 0.055
        let titleRect = CGRect(x: margin, y: 0, width: width - 2 * margin, height: captionTop)
        let titleHeight = drawText(shot.title, in: titleRect, size: unit * 0.085, bold: true, textColor: color(0xFFFFFF), ctx: ctx)
        let subtitleRect = CGRect(x: margin, y: 0, width: width - 2 * margin, height: captionTop - titleHeight - unit * 0.02)
        let subtitleHeight = drawText(shot.subtitle, in: subtitleRect, size: unit * 0.05, bold: false,
                                      textColor: color(0xFFFFFF, alpha: 0.88), ctx: ctx)

        // The screenshot below, scaled down with rounded corners and a soft shadow; it runs
        // off the bottom edge, as store screenshots commonly do.
        let shotTop = captionTop - titleHeight - subtitleHeight - unit * 0.07
        // Wide enough that the screenshot runs well past the bottom edge, so only its top
        // corners show and no row is cut by a rounded corner.
        let shotWidth = max(width * 0.82, (shotTop + height * 0.06) * width / height)
        let shotHeight = shotWidth * height / width
        let shotRect = CGRect(x: (width - shotWidth) / 2, y: shotTop - shotHeight, width: shotWidth, height: shotHeight)
        // iPad screens have much tighter corners than iPhones relative to their width.
        let radius = shotWidth * (device.hasPrefix("ipad") ? 0.03 : 0.07)
        let shape = CGPath(roundedRect: shotRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -unit * 0.012), blur: unit * 0.06, color: color(0x0B1F5C, alpha: 0.45))
        ctx.addPath(shape)
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.draw(raw, in: shotRect)
        ctx.restoreGState()

        write(ctx, to: "docs/screenshots/\(device)/captioned/\(shot.file).png")
    }
}

// MARK: - Banner

func renderBanner() {
    let width = 1024, height = 500
    let ctx = makeContext(width: width, height: height)
    drawBackground(ctx, width: CGFloat(width), height: CGFloat(height))

    // App icon on the left, rounded the way iOS shows it.
    if let icon = loadImage("converter-ios/Assets.xcassets/AppIcon.appiconset/AppIcon-iOS-1024.png") {
        let side: CGFloat = 260
        let rect = CGRect(x: 90, y: (CGFloat(height) - side) / 2, width: side, height: side)
        let shape = CGPath(roundedRect: rect, cornerWidth: side * 0.225, cornerHeight: side * 0.225, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 30, color: color(0x0B1F5C, alpha: 0.45))
        ctx.addPath(shape)
        ctx.setFillColor(color(0x2563EB))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.draw(icon, in: rect)
        ctx.restoreGState()
    }

    let textX: CGFloat = 400
    let textWidth = CGFloat(width) - textX - 60
    let used = drawText("Unit Converter", in: CGRect(x: textX, y: 0, width: textWidth, height: 330),
                        size: 64, bold: true, textColor: color(0xFFFFFF), alignment: .left, ctx: ctx)
    drawText("Fast, offline conversions.\nNo ads. No tracking.", in: CGRect(x: textX, y: 0, width: textWidth, height: 330 - used - 14),
             size: 32, bold: false, textColor: color(0xFFFFFF, alpha: 0.9), alignment: .left, ctx: ctx)
    write(ctx, to: "docs/banner-1024x500.png")
}

// MARK: - Creative assets (App Store featuring artwork)

/// The app icon, rounded the way iOS shows it, with a soft shadow. `rect` is in y-up coordinates.
func drawIcon(_ ctx: CGContext, in rect: CGRect) {
    guard let icon = loadImage("converter-ios/Assets.xcassets/AppIcon.appiconset/AppIcon-iOS-1024.png") else { return }
    let shape = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.03), blur: rect.width * 0.12, color: color(0x0B1F5C, alpha: 0.45))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x2563EB))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.draw(icon, in: rect)
    ctx.restoreGState()
}

/// A screenshot inside a simple black iPhone body, `height` tall (screen only), centred on
/// `center` and turned by `angle` radians.
func drawPhone(_ ctx: CGContext, _ screenshot: CGImage, center: CGPoint, height: CGFloat, angle: CGFloat = 0) {
    let width = height * CGFloat(screenshot.width) / CGFloat(screenshot.height)
    let bezel = width * 0.035
    let screen = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    let body = screen.insetBy(dx: -bezel, dy: -bezel)
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -height * 0.015), blur: height * 0.06, color: color(0x0B1F5C, alpha: 0.5))
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: width * 0.16, cornerHeight: width * 0.16, transform: nil))
    ctx.setFillColor(color(0x0A0A0A))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: width * 0.13, cornerHeight: width * 0.13, transform: nil))
    ctx.clip()
    ctx.draw(screenshot, in: screen)
    ctx.restoreGState()
}

/// The app name and tagline, left-aligned, top-aligned at `top`.
func drawTitle(_ ctx: CGContext, x: CGFloat, top: CGFloat, width: CGFloat, size: CGFloat) {
    let used = drawText("Unit Converter", in: CGRect(x: x, y: 0, width: width, height: top),
                        size: size, bold: true, textColor: color(0xFFFFFF), alignment: .left, ctx: ctx)
    drawText("Fast, offline conversions.\nNo ads. No tracking.", in: CGRect(x: x, y: 0, width: width, height: top - used - size * 0.25),
             size: size * 0.48, bold: false, textColor: color(0xFFFFFF, alpha: 0.9), alignment: .left, ctx: ctx)
}

/// Header artwork: the icon on the left, three phones fanned out on the right. Everything
/// important sits in the middle of the canvas, since the App Store may crop the edges.
func renderHeader(width: Int, height: Int, withText: Bool) {
    let w = CGFloat(width), h = CGFloat(height)
    let ctx = makeContext(width: width, height: height)
    drawBackground(ctx, width: w, height: h)
    let shots = ["02-length", "01-home", "04-clock"].compactMap { loadImage("docs/screenshots/iphone-6.9/raw/\($0).png") }

    // Work within a centred band no wider than 2.2 × the height, so ultra-wide crops match 16:9.
    let band = min(w, h * 2.2)
    let left = (w - band) / 2
    let phoneHeight = h * 0.74
    let iconSide = h * (withText ? 0.26 : 0.34)
    let iconCenterX = left + band * (withText ? 0.24 : 0.28)

    if shots.count == 3 {
        let centers = [0.62, 0.86, 0.74].map { left + band * $0 }
        drawPhone(ctx, shots[0], center: CGPoint(x: centers[0], y: h * 0.47), height: phoneHeight * 0.9, angle: 0.08)
        drawPhone(ctx, shots[2], center: CGPoint(x: centers[1], y: h * 0.47), height: phoneHeight * 0.9, angle: -0.08)
        drawPhone(ctx, shots[1], center: CGPoint(x: centers[2], y: h * 0.5), height: phoneHeight)
    }

    if withText {
        let iconRect = CGRect(x: iconCenterX - iconSide / 2, y: h * 0.56, width: iconSide, height: iconSide)
        drawIcon(ctx, in: iconRect)
        drawTitle(ctx, x: iconRect.minX, top: iconRect.minY - h * 0.05, width: band * 0.42, size: h * 0.075)
    } else {
        drawIcon(ctx, in: CGRect(x: iconCenterX - iconSide / 2, y: (h - iconSide) / 2, width: iconSide, height: iconSide))
    }
    write(ctx, to: "docs/creative-assets/header-\(width)x\(height)\(withText ? "-text" : "").png")
}

/// Search-result artwork: three phones side by side, with the icon to their left.
func renderSearchResult(width: Int, height: Int, withText: Bool) {
    let w = CGFloat(width), h = CGFloat(height)
    let ctx = makeContext(width: width, height: height)
    drawBackground(ctx, width: w, height: h)
    let shots = ["01-home", "03-recipe", "04-clock"].compactMap { loadImage("docs/screenshots/iphone-6.9/raw/\($0).png") }

    let band = min(w, h * 1.8)
    let left = (w - band) / 2
    // Phones about 0.36 × the height wide (bezel included), spaced 0.4 × the height apart, so
    // they never touch and the last one stays well inside the edge.
    let phoneHeight = h * (withText ? 0.66 : 0.72)
    let phoneY = withText ? h * 0.42 : h * 0.5
    for (index, shot) in shots.enumerated() {
        drawPhone(ctx, shot, center: CGPoint(x: left + band * (0.40 + 0.22 * CGFloat(index)), y: phoneY), height: phoneHeight)
    }
    let iconSide = h * 0.22
    let iconRect = CGRect(x: left + band * 0.14 - iconSide / 2, y: phoneY - iconSide / 2, width: iconSide, height: iconSide)
    drawIcon(ctx, in: iconRect)
    if withText {
        drawText("Unit Converter", in: CGRect(x: left, y: 0, width: band, height: h * 0.95),
                 size: h * 0.065, bold: true, textColor: color(0xFFFFFF), ctx: ctx)
    }
    write(ctx, to: "docs/creative-assets/search-\(width)x\(height)\(withText ? "-text" : "").png")
}

func renderCreativeAssets() {
    for withText in [false, true] {
        renderHeader(width: 5244, height: 2950, withText: withText)
        renderHeader(width: 3840, height: 1646, withText: withText)
        renderSearchResult(width: 5244, height: 2950, withText: withText)
        renderSearchResult(width: 3840, height: 2560, withText: withText)
        renderSearchResult(width: 1920, height: 1280, withText: withText)
    }
}

/// Simulator screenshots carry an alpha channel, which App Store Connect can reject; redraw
/// each raw screenshot onto an opaque canvas in place.
func flattenRaw(_ shots: [Shot], device: String) {
    for shot in shots {
        let path = "docs/screenshots/\(device)/raw/\(shot.file).png"
        guard let raw = loadImage(path), raw.alphaInfo != .noneSkipLast, raw.alphaInfo != .none else { continue }
        let ctx = makeContext(width: raw.width, height: raw.height)
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fill(CGRect(x: 0, y: 0, width: raw.width, height: raw.height))
        ctx.draw(raw, in: CGRect(x: 0, y: 0, width: raw.width, height: raw.height))
        write(ctx, to: path)
    }
}

flattenRaw(iPhoneShots, device: "iphone-6.9")
flattenRaw(iPadShots, device: "ipad-13")
renderCaptioned(iPhoneShots, device: "iphone-6.9")
renderCaptioned(iPadShots, device: "ipad-13")
renderBanner()
renderCreativeAssets()

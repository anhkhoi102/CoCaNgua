// Tạo biểu tượng ứng dụng theo phong cách logo: bốn mảnh ghép bốn màu xếp lệch trên nền mặt bàn, một viên xúc xắc,
// và ảnh quân mã đỏ đã dựng (mẫu 3D CC0 của lyricsz) đứng giữa.
// Dùng: swift Tools/make-icon.swift <knight_red@2x.png> <thư mục AppIcon.appiconset>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let knight = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("Dùng: make-icon.swift <ảnh quân mã> <AppIcon.appiconset>\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }

/// `fullBleed`: biểu tượng iOS. Hình vuông kín, không trong suốt (iOS tự bo góc), hình vẽ phóng to cho đầy khung.
func render(pixels: Int, fullBleed: Bool = false) -> CGImage {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: (fullBleed ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
    let unit = CGFloat(pixels) / 1024
    context.scaleBy(x: unit, y: unit)
    // Khuôn biểu tượng macOS: hình vuông bo góc 824 điểm giữa khung 1024, nền xanh mặt bàn như trong trò chơi.
    let plate = fullBleed ? CGRect(x: 0, y: 0, width: 1024, height: 1024) : CGRect(x: 100, y: 100, width: 824, height: 824)
    let corner: CGFloat = fullBleed ? 0 : 186
    let shape = CGPath(roundedRect: plate, cornerWidth: corner, cornerHeight: corner, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 22 * unit, color: rgb(0, 0, 0, 0.35))
    context.addPath(shape)
    context.setFillColor(rgb(0.07, 0.27, 0.26))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let table = CGGradient(colorsSpace: space, colors: [rgb(0.16, 0.46, 0.42), rgb(0.05, 0.21, 0.22)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(table, start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY), options: [])
    if fullBleed {
        context.translateBy(x: 512, y: 512)
        context.scaleBy(x: 1.16, y: 1.16)
        context.translateBy(x: -512, y: -512)
    }

    // Bốn mảnh ghép bốn màu xếp lệch nhau như logo: mặt màu, viền trắng, cạnh dưới sẫm màu.
    let tiles: [(CGPoint, CGFloat, CGColor, CGColor)] = [
        (CGPoint(x: 336, y: 690), -7, rgb(0.90, 0.28, 0.30), rgb(0.62, 0.16, 0.18)),   // Đỏ, trên trái
        (CGPoint(x: 694, y: 706), 5, rgb(0.96, 0.70, 0.08), rgb(0.70, 0.48, 0.04)),    // Vàng, trên phải
        (CGPoint(x: 330, y: 338), 4, rgb(0.22, 0.50, 0.96), rgb(0.12, 0.30, 0.68)),    // Xanh dương, dưới trái
        (CGPoint(x: 690, y: 330), -5, rgb(0.18, 0.68, 0.42), rgb(0.10, 0.44, 0.26)),   // Xanh lá, dưới phải
    ]
    let side: CGFloat = 318
    for (center, degrees, face, edge) in tiles {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: degrees * .pi / 180)
        let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
        context.setShadow(offset: CGSize(width: 0, height: -12 * unit), blur: 16 * unit, color: rgb(0, 0, 0, 0.32))
        context.addPath(CGPath(roundedRect: rect.offsetBy(dx: 0, dy: -24), cornerWidth: 72, cornerHeight: 72, transform: nil))
        context.setFillColor(edge)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        let facePath = CGPath(roundedRect: rect, cornerWidth: 72, cornerHeight: 72, transform: nil)
        context.addPath(facePath)
        context.setFillColor(face)
        context.fillPath()
        context.addPath(CGPath(roundedRect: rect.insetBy(dx: 8, dy: 8), cornerWidth: 64, cornerHeight: 64, transform: nil))
        context.setStrokeColor(rgb(1, 1, 1, 0.88))
        context.setLineWidth(15)
        context.strokePath()
        // Ô tròn trắng giữa mảnh, gợi chỗ đứng trong chuồng.
        context.addEllipse(in: CGRect(x: -62, y: -62, width: 124, height: 124))
        context.setFillColor(rgb(1, 1, 1, 0.30))
        context.fillPath()
        context.restoreGState()
    }
    context.restoreGState()

    // Viên xúc xắc nghiêng ở góc dưới phải.
    context.saveGState()
    context.translateBy(x: 800, y: 236)
    context.rotate(by: 14 * .pi / 180)
    let die = CGRect(x: -92, y: -92, width: 184, height: 184)
    context.setShadow(offset: CGSize(width: 0, height: -8 * unit), blur: 14 * unit, color: rgb(0, 0, 0, 0.35))
    context.addPath(CGPath(roundedRect: die.offsetBy(dx: 0, dy: -14), cornerWidth: 44, cornerHeight: 44, transform: nil))
    context.setFillColor(rgb(0.62, 0.16, 0.18))
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)
    context.addPath(CGPath(roundedRect: die, cornerWidth: 44, cornerHeight: 44, transform: nil))
    context.setFillColor(rgb(1, 1, 1))
    context.fillPath()
    context.addPath(CGPath(roundedRect: die.insetBy(dx: 5, dy: 5), cornerWidth: 40, cornerHeight: 40, transform: nil))
    context.setStrokeColor(rgb(0.90, 0.28, 0.30))
    context.setLineWidth(10)
    context.strokePath()
    context.setFillColor(rgb(0.17, 0.15, 0.20))
    for (column, row) in [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)] {
        context.fillEllipse(in: CGRect(x: CGFloat(column) * 46 - 17, y: CGFloat(row) * 46 - 17, width: 34, height: 34))
    }
    context.restoreGState()

    // Bóng tiếp xúc rồi quân mã đỏ đứng giữa.
    let shade = CGGradient(colorsSpace: space, colors: [rgb(0, 0, 0, 0.50), rgb(0, 0, 0, 0)] as CFArray, locations: [0, 1])!
    context.saveGState()
    context.translateBy(x: 524, y: 300)
    context.scaleBy(x: 1, y: 0.42)
    context.drawRadialGradient(shade, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 190, options: [])
    context.restoreGState()
    let height: CGFloat = 760
    let width = height * CGFloat(knight.width) / CGFloat(knight.height)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 6 * unit, height: -10 * unit), blur: 18 * unit, color: rgb(0, 0, 0, 0.38))
    context.draw(knight, in: CGRect(x: 512 - width / 2, y: 300 - 0.235 * height, width: width, height: height))
    context.restoreGState()
    return context.makeImage()!
}

var images: [String] = []
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let rep = NSBitmapImageRep(cgImage: render(pixels: points * scale))
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    images.append("    { \"idiom\" : \"mac\", \"size\" : \"\(points)x\(points)\", \"scale\" : \"\(scale)x\", \"filename\" : \"\(name)\" }")
}
// iOS chỉ cần một ảnh 1024; Xcode tự tạo các cỡ còn lại.
let iosRep = NSBitmapImageRep(cgImage: render(pixels: 1024, fullBleed: true))
try iosRep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_ios_1024.png"))
images.append("    { \"idiom\" : \"universal\", \"platform\" : \"ios\", \"size\" : \"1024x1024\", \"filename\" : \"icon_ios_1024.png\" }")
let json = "{\n  \"images\" : [\n\(images.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try json.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Đã ghi biểu tượng vào \(output.path)")

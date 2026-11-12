// Dựng ảnh quân cờ hình cá ngựa bốn màu. Toàn bộ hình khối được tạo bằng mã từ các khối cơ bản của SceneKit,
// không dùng mẫu 3D hay ảnh của bên thứ ba.
//
// Dùng:  Scripts/render-pieces.sh   (hoặc: swift Tools/render-seahorses.swift <thư mục xuất>)
// Kết quả: seahorse_red.png, seahorse_blue.png, seahorse_green.png, seahorse_yellow.png (nền trong suốt).
//
// Kiểu dáng: quân Ludo cổ điển (đế tròn loe, nhựa bóng một màu) với phần thân là một chú cá ngựa:
// đuôi cuộn, bụng tròn, cổ cong, mõm dài, mào trên đầu và vây lưng. Cả bốn màu dùng chung hình khối,
// góc nhìn và ánh sáng.

import AppKit
import CoreImage
import Metal
import SceneKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("Dùng: swift render-seahorses.swift <thư mục xuất>")
    exit(1)
}
let outputFolder = URL(fileURLWithPath: arguments[1], isDirectory: true)
let pixelSize = CGSize(width: 384, height: 512)

struct Palette {
    let name: String
    let body: NSColor
    var dark: NSColor { body.blended(withFraction: 0.38, of: .black)! }
    var light: NSColor { body.blended(withFraction: 0.45, of: .white)! }
}

// Cùng bảng màu với Theme.color(_:) trong ứng dụng.
let palettes = [
    Palette(name: "red", body: NSColor(srgbRed: 0.90, green: 0.28, blue: 0.30, alpha: 1)),
    Palette(name: "blue", body: NSColor(srgbRed: 0.22, green: 0.50, blue: 0.96, alpha: 1)),
    Palette(name: "green", body: NSColor(srgbRed: 0.18, green: 0.68, blue: 0.42, alpha: 1)),
    Palette(name: "yellow", body: NSColor(srgbRed: 0.96, green: 0.70, blue: 0.08, alpha: 1)),
]

func plastic(_ color: NSColor, shininess: CGFloat = 0.85, specular: CGFloat = 0.9) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .blinn
    material.diffuse.contents = color
    material.specular.contents = NSColor(white: specular, alpha: 1)
    material.shininess = shininess
    return material
}

func sphere(_ radius: CGFloat, _ material: SCNMaterial, at position: SCNVector3, scale: SCNVector3 = SCNVector3(1, 1, 1)) -> SCNNode {
    let geometry = SCNSphere(radius: radius)
    geometry.segmentCount = 48
    geometry.materials = [material]
    let node = SCNNode(geometry: geometry)
    node.position = position
    node.scale = scale
    return node
}

/// Điểm trên đường cong Catmull‑Rom qua các điểm điều khiển (x, y, bán kính).
func sample(_ points: [(CGFloat, CGFloat, CGFloat)], count: Int) -> [(CGFloat, CGFloat, CGFloat)] {
    func value(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ t: CGFloat) -> CGFloat {
        0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t * t * t)
    }
    var result: [(CGFloat, CGFloat, CGFloat)] = []
    let segments = points.count - 1
    for index in 0..<count {
        let position = CGFloat(index) / CGFloat(count - 1) * CGFloat(segments)
        let segment = min(Int(position), segments - 1)
        let t = position - CGFloat(segment)
        let p0 = points[max(segment - 1, 0)], p1 = points[segment], p2 = points[segment + 1], p3 = points[min(segment + 2, segments)]
        result.append((value(p0.0, p1.0, p2.0, p3.0, t), value(p0.1, p1.1, p2.1, p3.1, t), value(p0.2, p1.2, p2.2, p3.2, t)))
    }
    return result
}

func makePiece(_ palette: Palette) -> SCNNode {
    let piece = SCNNode()
    let body = plastic(palette.body)
    let dark = plastic(palette.dark)
    let light = plastic(palette.light, shininess: 0.7, specular: 0.7)

    // Đế quân Ludo: đĩa đáy, gờ, rồi phần loe thu dần lên trên.
    let foot = SCNCylinder(radius: 0.30, height: 0.07)
    foot.radialSegmentCount = 72
    foot.materials = [dark]
    let footNode = SCNNode(geometry: foot)
    footNode.position.y = 0.035
    piece.addChildNode(footNode)
    let lip = SCNTorus(ringRadius: 0.275, pipeRadius: 0.035)
    lip.ringSegmentCount = 72
    lip.materials = [body]
    let lipNode = SCNNode(geometry: lip)
    lipNode.position.y = 0.085
    piece.addChildNode(lipNode)
    let skirt = SCNCone(topRadius: 0.11, bottomRadius: 0.265, height: 0.20)
    skirt.radialSegmentCount = 72
    skirt.materials = [body]
    let skirtNode = SCNNode(geometry: skirt)
    skirtNode.position.y = 0.185
    piece.addChildNode(skirtNode)

    // Thân cá ngựa nhìn ngang, quay mặt sang phải (+x): chuỗi khối cầu chồng nhau dọc một đường cong,
    // tạo ra các đốt nhẹ giống thân cá ngựa thật. (x, y, bán kính)
    let spine: [(CGFloat, CGFloat, CGFloat)] = [
        (0.150, 0.330, 0.034), (0.165, 0.270, 0.040), (0.120, 0.215, 0.048), (0.040, 0.215, 0.058),   // đuôi cuộn
        (-0.020, 0.275, 0.070), (-0.020, 0.360, 0.086), (0.010, 0.450, 0.108),
        (0.045, 0.550, 0.140), (0.050, 0.650, 0.152), (0.025, 0.750, 0.138),                           // bụng và ngực
        (-0.020, 0.845, 0.112), (-0.030, 0.930, 0.100), (0.000, 1.010, 0.108), (0.040, 1.060, 0.128),  // cổ và đầu
    ]
    let seahorse = SCNNode()
    for (x, y, radius) in sample(spine, count: 34) {
        seahorse.addChildNode(sphere(radius, body, at: SCNVector3(x, y, 0)))
    }
    // Bụng sáng màu hơn: một dải liền chạy dọc mặt trước thân.
    let belly: [(CGFloat, CGFloat, CGFloat)] = [
        (0.060, 0.430, 0.060), (0.105, 0.520, 0.088), (0.125, 0.610, 0.100), (0.115, 0.700, 0.094), (0.075, 0.790, 0.070),
    ]
    for (x, y, radius) in sample(belly, count: 16) {
        seahorse.addChildNode(sphere(radius, light, at: SCNVector3(x, y, 0), scale: SCNVector3(1, 1, 0.80)))
    }
    // Mõm dài chúc xuống, đầu mõm loe nhẹ.
    for step in 0...9 {
        let t = CGFloat(step) / 9
        seahorse.addChildNode(sphere(0.066 - 0.022 * t, body, at: SCNVector3(0.110 + 0.185 * t, 1.045 - 0.085 * t, 0)))
    }
    seahorse.addChildNode(sphere(0.052, body, at: SCNVector3(0.305, 0.957, 0)))
    // Mắt.
    for side in [CGFloat(1), -1] {
        seahorse.addChildNode(sphere(0.046, plastic(.white, shininess: 0.9), at: SCNVector3(0.085, 1.095, 0.092 * side)))
        seahorse.addChildNode(sphere(0.026, plastic(NSColor(white: 0.08, alpha: 1), shininess: 1), at: SCNVector3(0.098, 1.098, 0.124 * side)))
    }
    // Mào trên đầu.
    for (x, y, radius, tilt) in [(0.045, 1.195, 0.036, 0.0), (-0.015, 1.180, 0.032, 0.35), (-0.065, 1.140, 0.028, 0.7)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        let cone = SCNCone(topRadius: 0.004, bottomRadius: radius, height: radius * 2.6)
        cone.materials = [dark]
        let node = SCNNode(geometry: cone)
        node.position = SCNVector3(x, y, 0)
        node.eulerAngles.z = tilt
        seahorse.addChildNode(node)
    }
    // Vây lưng: quạt mỏng sau lưng.
    seahorse.addChildNode(sphere(0.105, light, at: SCNVector3(-0.135, 0.640, 0), scale: SCNVector3(0.75, 1.15, 0.22)))
    // Gai lưng nhỏ dọc cổ.
    for (x, y) in [(-0.125, 0.860), (-0.130, 0.945), (-0.105, 1.030)] as [(CGFloat, CGFloat)] {
        seahorse.addChildNode(sphere(0.030, dark, at: SCNVector3(x, y, 0)))
    }
    seahorse.position.y = 0.045
    piece.addChildNode(seahorse)
    return piece
}

func makeScene(_ palette: Palette) -> (SCNScene, SCNNode) {
    let scene = SCNScene()
    scene.background.contents = NSColor.clear
    let piece = makePiece(palette)
    piece.eulerAngles.y = -0.38   // xoay nhẹ về phía người nhìn để thấy khối
    scene.rootNode.addChildNode(piece)

    func light(_ type: SCNLight.LightType, intensity: CGFloat, color: NSColor = .white, angles: SCNVector3 = SCNVector3Zero) {
        let node = SCNNode()
        node.light = SCNLight()
        node.light?.type = type
        node.light?.intensity = intensity
        node.light?.color = color
        node.eulerAngles = angles
        scene.rootNode.addChildNode(node)
    }
    light(.ambient, intensity: 380)
    light(.directional, intensity: 820, angles: SCNVector3(-0.85, -0.60, 0))                                                           // đèn chính: trên, trái
    light(.directional, intensity: 300, color: NSColor(srgbRed: 0.85, green: 0.92, blue: 1, alpha: 1), angles: SCNVector3(-0.20, 0.95, 0)) // đèn phụ
    light(.directional, intensity: 420, angles: SCNVector3(-0.45, 3.0, 0))                                                             // viền sáng phía sau

    let camera = SCNCamera()
    camera.usesOrthographicProjection = true
    camera.orthographicScale = 0.72
    let cameraNode = SCNNode()
    cameraNode.camera = camera
    // Cùng góc nhìn từ trên xuống với quân mã, khớp độ nghiêng của bàn cờ 2.5D.
    let pitch = 38.0 * Double.pi / 180
    cameraNode.position = SCNVector3(0.02, 0.60 + 6 * sin(pitch), 6 * cos(pitch))
    cameraNode.eulerAngles.x = CGFloat(-pitch)
    scene.rootNode.addChildNode(cameraNode)
    return (scene, cameraNode)
}

guard let device = MTLCreateSystemDefaultDevice() else {
    print("Không có thiết bị Metal")
    exit(1)
}
try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
for palette in palettes {
    let (scene, cameraNode) = makeScene(palette)
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = scene
    renderer.pointOfView = cameraNode
    renderer.autoenablesDefaultLighting = false
    let image = renderer.snapshot(atTime: 0, with: pixelSize, antialiasingMode: .multisampling4X)
    guard let tiff = image.tiffRepresentation, let rendered = CIImage(data: tiff) else {
        print("Không đọc được ảnh \(palette.name)")
        exit(1)
    }
    // Viền trắng mảnh quanh quân (kiểu sticker) để quân nổi rõ trên ô cùng màu.
    let extent = rendered.extent
    let silhouette = rendered
        .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 5.0])
        .applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ])
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.8])
    let outlined = rendered.composited(over: silhouette).cropped(to: extent)
    guard let cgImage = CIContext().createCGImage(outlined, from: extent),
          let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
        print("Không xuất được ảnh \(palette.name)")
        exit(1)
    }
    let url = outputFolder.appendingPathComponent("seahorse_\(palette.name).png")
    try png.write(to: url)
    print("Đã dựng \(url.lastPathComponent)")
}

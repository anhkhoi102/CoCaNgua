// Dựng ảnh quân mã cờ vua bốn màu từ một mẫu 3D định dạng GLB (glTF nhị phân).
//
// Dùng:  Scripts/render-pieces.sh   (hoặc: swift Tools/render-knights.swift <knight.glb> <thư mục xuất> [yaw độ])
// Kết quả: knight_red.png, knight_blue.png, knight_green.png, knight_yellow.png (nền trong suốt).
//
// SceneKit không đọc GLB nên file này tự đọc phần hình học (đỉnh, pháp tuyến, chỉ số tam giác) và bỏ qua
// vật liệu gốc: quân được phủ nhựa bóng theo màu người chơi, cùng góc nhìn và ánh sáng cho cả bốn màu.

import AppKit
import CoreImage
import Metal
import SceneKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("Dùng: swift render-knights.swift <knight.glb> <thư mục xuất> [yaw độ]")
    exit(1)
}
let modelURL = URL(fileURLWithPath: arguments[1])
let outputFolder = URL(fileURLWithPath: arguments[2], isDirectory: true)
let yawDegrees = arguments.count > 3 ? Double(arguments[3]) ?? 62 : 62
let pixelSize = CGSize(width: 384, height: 512)
/// Góc nhìn từ trên xuống của máy quay, khớp với độ nghiêng của bàn cờ 2.5D.
let cameraPitchDegrees = 38.0

// MARK: - Đọc GLB

struct GLBError: Error { let message: String }

func loadGLB(_ url: URL) throws -> SCNNode {
    let data = try Data(contentsOf: url)
    func u32(_ offset: Int) -> Int { Int(data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }) }
    guard data.count > 20, u32(0) == 0x46546C67 else { throw GLBError(message: "Không phải file GLB") }
    var offset = 12
    var json: [String: Any] = [:]
    var binary = Data()
    while offset + 8 <= data.count {
        let length = u32(offset), type = u32(offset + 4)
        let chunk = data.subdata(in: offset + 8..<offset + 8 + length)
        if type == 0x4E4F534A { json = try JSONSerialization.jsonObject(with: chunk) as? [String: Any] ?? [:] }
        if type == 0x004E4942 { binary = chunk }
        offset += 8 + length
    }
    let accessors = json["accessors"] as? [[String: Any]] ?? []
    let views = json["bufferViews"] as? [[String: Any]] ?? []
    let meshes = json["meshes"] as? [[String: Any]] ?? []
    let nodes = json["nodes"] as? [[String: Any]] ?? []

    func floats(_ index: Int, components: Int) throws -> [Float] {
        let accessor = accessors[index]
        guard accessor["componentType"] as? Int == 5126, let viewIndex = accessor["bufferView"] as? Int else {
            throw GLBError(message: "Kiểu dữ liệu đỉnh không được hỗ trợ")
        }
        let view = views[viewIndex]
        let start = (view["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
        let stride = view["byteStride"] as? Int ?? components * 4
        let count = accessor["count"] as? Int ?? 0
        var result = [Float](repeating: 0, count: count * components)
        binary.withUnsafeBytes { raw in
            for item in 0..<count {
                for component in 0..<components {
                    result[item * components + component] = raw.loadUnaligned(fromByteOffset: start + item * stride + component * 4, as: Float.self)
                }
            }
        }
        return result
    }

    func indices(_ index: Int) throws -> [UInt32] {
        let accessor = accessors[index]
        guard let viewIndex = accessor["bufferView"] as? Int, let type = accessor["componentType"] as? Int else {
            throw GLBError(message: "Thiếu chỉ số tam giác")
        }
        let view = views[viewIndex]
        let start = (view["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
        let count = accessor["count"] as? Int ?? 0
        return try binary.withUnsafeBytes { raw in
            try (0..<count).map { item in
                switch type {
                case 5121: return UInt32(raw.loadUnaligned(fromByteOffset: start + item, as: UInt8.self))
                case 5123: return UInt32(raw.loadUnaligned(fromByteOffset: start + item * 2, as: UInt16.self))
                case 5125: return raw.loadUnaligned(fromByteOffset: start + item * 4, as: UInt32.self)
                default: throw GLBError(message: "Kiểu chỉ số không được hỗ trợ")
                }
            }
        }
    }

    func geometry(_ mesh: [String: Any]) throws -> [SCNGeometry] {
        try (mesh["primitives"] as? [[String: Any]] ?? []).compactMap { primitive in
            guard let attributes = primitive["attributes"] as? [String: Int], let positionIndex = attributes["POSITION"] else { return nil }
            let positions = try floats(positionIndex, components: 3)
            var sources = [SCNGeometrySource(vertices: stride(from: 0, to: positions.count, by: 3).map {
                SCNVector3(CGFloat(positions[$0]), CGFloat(positions[$0 + 1]), CGFloat(positions[$0 + 2]))
            })]
            if let normalIndex = attributes["NORMAL"] {
                let normals = try floats(normalIndex, components: 3)
                sources.append(SCNGeometrySource(normals: stride(from: 0, to: normals.count, by: 3).map {
                    SCNVector3(CGFloat(normals[$0]), CGFloat(normals[$0 + 1]), CGFloat(normals[$0 + 2]))
                }))
            }
            let triangleIndices: [UInt32]
            if let indexAccessor = primitive["indices"] as? Int {
                triangleIndices = try indices(indexAccessor)
            } else {
                triangleIndices = (0..<UInt32(positions.count / 3)).map { $0 }
            }
            return SCNGeometry(sources: sources, elements: [SCNGeometryElement(indices: triangleIndices, primitiveType: .triangles)])
        }
    }

    func build(_ index: Int) throws -> SCNNode {
        let description = nodes[index]
        let node = SCNNode()
        if let matrix = description["matrix"] as? [Double], matrix.count == 16 {
            let m = matrix.map { CGFloat($0) }
            node.transform = SCNMatrix4(m11: m[0], m12: m[1], m13: m[2], m14: m[3], m21: m[4], m22: m[5], m23: m[6], m24: m[7],
                                        m31: m[8], m32: m[9], m33: m[10], m34: m[11], m41: m[12], m42: m[13], m43: m[14], m44: m[15])
        } else {
            if let t = description["translation"] as? [Double] { node.position = SCNVector3(CGFloat(t[0]), CGFloat(t[1]), CGFloat(t[2])) }
            if let r = description["rotation"] as? [Double] { node.orientation = SCNQuaternion(CGFloat(r[0]), CGFloat(r[1]), CGFloat(r[2]), CGFloat(r[3])) }
            if let s = description["scale"] as? [Double] { node.scale = SCNVector3(CGFloat(s[0]), CGFloat(s[1]), CGFloat(s[2])) }
        }
        if let meshIndex = description["mesh"] as? Int {
            for item in try geometry(meshes[meshIndex]) { node.addChildNode(SCNNode(geometry: item)) }
        }
        for child in description["children"] as? [Int] ?? [] { node.addChildNode(try build(child)) }
        return node
    }

    let root = SCNNode()
    let scenes = json["scenes"] as? [[String: Any]] ?? []
    let roots = scenes.first?["nodes"] as? [Int] ?? Array(nodes.indices)
    for index in roots { root.addChildNode(try build(index)) }
    return root
}

// MARK: - Dựng ảnh

struct Palette {
    let name: String
    let body: NSColor
}

// Cùng bảng màu với Theme.color(_:) trong ứng dụng.
let palettes = [
    Palette(name: "red", body: NSColor(srgbRed: 0.90, green: 0.28, blue: 0.30, alpha: 1)),
    Palette(name: "blue", body: NSColor(srgbRed: 0.22, green: 0.50, blue: 0.96, alpha: 1)),
    Palette(name: "green", body: NSColor(srgbRed: 0.18, green: 0.68, blue: 0.42, alpha: 1)),
    Palette(name: "yellow", body: NSColor(srgbRed: 0.96, green: 0.70, blue: 0.08, alpha: 1)),
]

func plastic(_ color: NSColor) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .blinn
    material.diffuse.contents = color
    material.specular.contents = NSColor(white: 0.9, alpha: 1)
    material.shininess = 0.85
    material.isDoubleSided = true
    return material
}

func makeScene(_ palette: Palette) throws -> (SCNScene, SCNNode) {
    let scene = SCNScene()
    scene.background.contents = NSColor.clear
    let model = try loadGLB(modelURL)
    model.enumerateHierarchy { node, _ in node.geometry?.materials = [plastic(palette.body)] }

    // Chuẩn hoá: cao 1 đơn vị, đáy ở y = 0, tâm ở trục y.
    let holder = SCNNode()
    holder.addChildNode(model)
    let (minimum, maximum) = holder.boundingBox
    let scale = 1 / (maximum.y - minimum.y)
    model.scale = SCNVector3(scale, scale, scale)
    model.position = SCNVector3(-(minimum.x + maximum.x) / 2 * scale, -minimum.y * scale, -(minimum.z + maximum.z) / 2 * scale)

    let piece = SCNNode()
    piece.addChildNode(holder)
    piece.eulerAngles.y = CGFloat(yawDegrees * .pi / 180)
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
    light(.directional, intensity: 820, angles: SCNVector3(-0.85, -0.60, 0))
    light(.directional, intensity: 300, color: NSColor(srgbRed: 0.85, green: 0.92, blue: 1, alpha: 1), angles: SCNVector3(-0.20, 0.95, 0))
    light(.directional, intensity: 420, angles: SCNVector3(-0.45, 3.0, 0))

    let camera = SCNCamera()
    camera.usesOrthographicProjection = true
    camera.orthographicScale = 0.64
    let cameraNode = SCNNode()
    cameraNode.camera = camera
    let pitch = cameraPitchDegrees * Double.pi / 180
    // Nhìn vào điểm cao 0,43 trên trục quân.
    cameraNode.position = SCNVector3(0, 0.43 + 6 * sin(pitch), 6 * cos(pitch))
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
    let (scene, cameraNode) = try makeScene(palette)
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = scene
    renderer.pointOfView = cameraNode
    renderer.autoenablesDefaultLighting = false
    let image = renderer.snapshot(atTime: 0, with: pixelSize, antialiasingMode: .multisampling4X)
    guard let tiff = image.tiffRepresentation, let rendered = CIImage(data: tiff) else {
        print("Không đọc được ảnh \(palette.name)")
        exit(1)
    }
    // Viền trắng mảnh quanh quân để quân nổi rõ trên ô cùng màu.
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
    let url = outputFolder.appendingPathComponent("knight_\(palette.name).png")
    try png.write(to: url)
    print("Đã dựng \(url.lastPathComponent)")
}

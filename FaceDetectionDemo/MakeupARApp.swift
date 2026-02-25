//
//  MakeupARApp.swift
//  FaceDetectionDemo
//
//  Created by Anand Upadhyay on 14/02/26.
//

import SwiftUI
import ARKit
import SceneKit
import RealityKit
import Combine
import UIKit

// MARK: - Models

enum MakeupFeature: String, CaseIterable, Hashable {
    case lip = "Lip"
    case hair = "Hair"
    case earring = "Earring"
    case nose = "Nose"
    case neck = "Neck"
    case eye = "Eye"
    case bindi = "Bindi"
    
    var displayName: String { rawValue }
    
    var iconName: String {
        switch self {
        case .lip: return "mouth"
        case .hair: return "scissors"
        case .earring: return "circle.circle"
        case .nose: return "nose"
        case .neck: return "person.crop.circle"
        case .eye: return "eye"
        case .bindi: return "circle.fill"
        }
    }
}

// MARK: - ViewModel

class MakeupViewModel: ObservableObject {
    @Published var selectedFeature: MakeupFeature?
    @Published var selectedColor: Color = .red
    @Published var showColorPicker: Bool = false
    
    // Lip positioning parameters - adjust these to fine-tune the shape
    @Published var lipVerticalMin: Double = -0.052    // Bottom of lower lip
    @Published var lipVerticalMax: Double = -0.015    // Top of upper lip
    @Published var lipHorizontalMax: Double = 0.037   // Width at center
    @Published var lipDepthMin: Double = -0.030       // Forward facing depth
}

// MARK: - AR Camera View

struct ARCameraView: UIViewRepresentable {
    @ObservedObject var viewModel: MakeupViewModel
    
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true
        view.scene = SCNScene()

        if ARFaceTrackingConfiguration.isSupported {
            let configuration = ARFaceTrackingConfiguration()
            configuration.isLightEstimationEnabled = true
            view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
        return view
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    
    func makeCoordinator() -> ARCoordinator {
        ARCoordinator(viewModel: viewModel)
    }
    
    class ARCoordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        var viewModel: MakeupViewModel
        var faceNode: SCNNode?
        var featureNode: SCNNode?
        
        init(viewModel: MakeupViewModel) {
            self.viewModel = viewModel
        }
        
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard let faceAnchor = anchor as? ARFaceAnchor,
                  let device = MTLCreateSystemDefaultDevice() else { return nil }
            
            let faceGeometry = ARSCNFaceGeometry(device: device)
            let node = SCNNode(geometry: faceGeometry)
            node.geometry?.firstMaterial?.fillMode = .lines
            node.geometry?.firstMaterial?.transparency = 0.0
            
            self.faceNode = node
            faceGeometry?.update(from: faceAnchor.geometry)
            return node
        }
        
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let faceAnchor = anchor as? ARFaceAnchor,
                  let faceGeometry = node.geometry as? ARSCNFaceGeometry else { return }
            
            faceGeometry.update(from: faceAnchor.geometry)
            updateFeatureOverlay(for: faceAnchor, on: node)
        }
        
        func updateFeatureOverlay(for anchor: ARFaceAnchor, on node: SCNNode) {
            featureNode?.removeFromParentNode()
            featureNode = nil

            guard let feature = viewModel.selectedFeature else { return }
            
            // Convert SwiftUI Color to UIColor properly
            let uiColor = UIColor(viewModel.selectedColor)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            
            // Extract RGBA components
            uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            
            let color = UIColor(
                red: red,
                green: green,
                blue: blue,
                alpha: 0.85
            )

            let material = SCNMaterial()
            material.diffuse.contents = color
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.writesToDepthBuffer = true
            material.readsFromDepthBuffer = true
            material.blendMode = .alpha
            material.transparencyMode = .dualLayer

            let faceGeometry = anchor.geometry

            switch feature {
            case .lip:
                if let indexData = createLipIndices(from: faceGeometry) {
                    let element = SCNGeometryElement(
                        data: indexData,
                        primitiveType: .triangles,
                        primitiveCount: indexData.count / (3 * MemoryLayout<Int32>.size),
                        bytesPerIndex: MemoryLayout<Int32>.size
                    )
                    
                    let vertices = faceGeometry.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
                    let texCoords = faceGeometry.textureCoordinates.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
                    
                    let vertexSource = SCNGeometrySource(vertices: vertices)
                    let texCoordSource = SCNGeometrySource(textureCoordinates: texCoords)
                    
                    let normalSource: SCNGeometrySource
                    if let device = MTLCreateSystemDefaultDevice(),
                       let tempGeometry = ARSCNFaceGeometry(device: device) {
                        tempGeometry.update(from: faceGeometry)
                        normalSource = tempGeometry.sources(for: .normal).first ?? SCNGeometrySource(normals: vertices.map { _ in SCNVector3(0, 0, 1) })
                    } else {
                        normalSource = SCNGeometrySource(normals: vertices.map { _ in SCNVector3(0, 0, 1) })
                    }
                    
                    let customGeometry = SCNGeometry(
                        sources: [vertexSource, normalSource, texCoordSource],
                        elements: [element]
                    )
                    customGeometry.materials = [material]
                    
                    let nodeGeom = SCNNode(geometry: customGeometry)
                    node.addChildNode(nodeGeom)
                    self.featureNode = nodeGeom
                } else if let geom = makeGeometry(from: faceGeometry, with: Self.lipTriangles) {
                    geom.materials = [material]
                    let nodeGeom = SCNNode(geometry: geom)
                    node.addChildNode(nodeGeom)
                    self.featureNode = nodeGeom
                }

            case .nose:
                if let geom = makeGeometry(from: faceGeometry, with: Self.noseTriangles) {
                    geom.materials = [material]
                    let nodeGeom = SCNNode(geometry: geom)
                    node.addChildNode(nodeGeom)
                    self.featureNode = nodeGeom
                }

            case .earring:
                let vertexCount = Int(faceGeometry.vertices.count)
                guard Self.leftEarApproxIndex < vertexCount && Self.rightEarApproxIndex < vertexCount else { return }
                
                let leftV = faceGeometry.vertices[Self.leftEarApproxIndex]
                let rightV = faceGeometry.vertices[Self.rightEarApproxIndex]

                let leftSphere = SCNSphere(radius: 0.007)
                leftSphere.materials = [material]
                let leftNode = SCNNode(geometry: leftSphere)
                leftNode.position = SCNVector3(leftV.x - 0.018, leftV.y - 0.028, leftV.z)

                let rightSphere = SCNSphere(radius: 0.007)
                rightSphere.materials = [material]
                let rightNode = SCNNode(geometry: rightSphere)
                rightNode.position = SCNVector3(rightV.x + 0.018, rightV.y - 0.028, rightV.z)

                let container = SCNNode()
                container.addChildNode(leftNode)
                container.addChildNode(rightNode)
                node.addChildNode(container)
                self.featureNode = container

            case .hair:
                if let geom = makeGeometry(from: faceGeometry, with: Self.hairlineTriangles) {
                    geom.materials = [material]
                    let nodeGeom = SCNNode(geometry: geom)
                    node.addChildNode(nodeGeom)
                    self.featureNode = nodeGeom
                }

            case .neck:
                if let geom = makeGeometry(from: faceGeometry, with: Self.jawlineTriangles) {
                    geom.materials = [material]
                    let nodeGeom = SCNNode(geometry: geom)
                    node.addChildNode(nodeGeom)
                    self.featureNode = nodeGeom
                }

            case .bindi:
                let vertexCount = Int(faceGeometry.vertices.count)
                guard 9 < vertexCount else { return }
                
                let v = faceGeometry.vertices[9]
                let sphere = SCNSphere(radius: 0.009)
                sphere.materials = [material]
                let bindiNode = SCNNode(geometry: sphere)
                bindiNode.position = SCNVector3(v.x, v.y + 0.03, v.z - 0.005)
                node.addChildNode(bindiNode)
                self.featureNode = bindiNode

            default:
                break
            }
        }
        
        func createLipIndices(from geometry: ARFaceGeometry) -> Data? {
            let triangleIndices = geometry.triangleIndices
            let vertexCount = geometry.vertices.count
            var lipIndices: [Int32] = []
            
            let totalIndices = triangleIndices.count
            guard totalIndices >= 3 else { return nil }
            
            let triangleCount = totalIndices / 3
            for triangleIdx in 0..<triangleCount {
                let baseIdx = triangleIdx * 3
                let v1 = Int(triangleIndices[baseIdx])
                let v2 = Int(triangleIndices[baseIdx + 1])
                let v3 = Int(triangleIndices[baseIdx + 2])
                
                guard v1 < vertexCount && v2 < vertexCount && v3 < vertexCount else { continue }
                
                let vertex1 = geometry.vertices[v1]
                let vertex2 = geometry.vertices[v2]
                let vertex3 = geometry.vertices[v3]
                
                let inRegionCount = [vertex1, vertex2, vertex3].filter { isInLipRegion($0) }.count
                
                if inRegionCount == 3 {
                    lipIndices.append(Int32(v1))
                    lipIndices.append(Int32(v2))
                    lipIndices.append(Int32(v3))
                }
            }
            
            guard !lipIndices.isEmpty else { return nil }
            return Data(bytes: lipIndices, count: lipIndices.count * MemoryLayout<Int32>.size)
        }
        
        func isInLipRegion(_ vertex: vector_float3) -> Bool {
            let y = vertex.y, x = vertex.x, z = vertex.z
            
            // Use tunable parameters from viewModel
            let verticalMin = Float(viewModel.lipVerticalMin)
            let verticalMax = Float(viewModel.lipVerticalMax)
            let horizontalMax = Float(viewModel.lipHorizontalMax)
            let depthMin = Float(viewModel.lipDepthMin)
            
            // Basic vertical bounds
            guard y > verticalMin && y < verticalMax else { return false }
            
            // Depth check - lips are forward-facing
            guard z > depthMin else { return false }
            
            // Calculate position relative to lip center
            let verticalCenter = (verticalMin + verticalMax) / 2.0
            let verticalRange = verticalMax - verticalMin
            let yNormalized = (y - verticalCenter) / (verticalRange / 2.0)
            
            // Create elliptical shape - wider in middle, narrower at top and bottom
            let ellipseFactor = sqrt(max(0, 1.0 - yNormalized * yNormalized))
            let maxXAtY = horizontalMax * ellipseFactor
            
            // Check horizontal bounds
            return abs(x) < maxXAtY
        }
        
        private func makeGeometry(from face: ARFaceGeometry, with triangles: [Int32]) -> SCNGeometry? {
            guard !triangles.isEmpty else { return nil }
            let vertices = face.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
            let vertexSource = SCNGeometrySource(vertices: vertices)
            let data = Data(bytes: triangles, count: triangles.count * MemoryLayout<Int32>.size)
            let element = SCNGeometryElement(
                data: data,
                primitiveType: .triangles,
                primitiveCount: triangles.count / 3,
                bytesPerIndex: MemoryLayout<Int32>.size
            )
            return SCNGeometry(sources: [vertexSource], elements: [element])
        }
        
        static let lipTriangles: [Int32] = [
            37, 267, 269,  269, 270, 409,  409, 270, 291,
            61, 185, 40,   40, 185, 39,    39, 185, 37,
            146, 91, 181,  181, 84, 17,    17, 84, 314,
            314, 405, 321, 321, 375, 291,  
            78, 191, 80,   80, 191, 81,    81, 191, 82,
            82, 13, 312,   312, 13, 311,   311, 13, 310,
            61, 146, 91,   91, 146, 181,   181, 146, 84,
            40, 39, 37,    37, 0, 267,     267, 0, 269,
            321, 405, 375, 375, 291, 409
        ]
        static let noseTriangles: [Int32] = [6, 7, 9, 7, 10, 9, 9, 10, 11, 11, 10, 12, 12, 13, 14, 11, 12, 14]
        static let hairlineTriangles: [Int32] = [18, 19, 20, 20, 21, 22, 22, 23, 18]
        static let jawlineTriangles: [Int32] = [50, 51, 60, 60, 61, 62, 62, 63, 64, 64, 65, 50]
        static let leftEarApproxIndex: Int = 127
        static let rightEarApproxIndex: Int = 356
    }
}

// MARK: - Views

struct MakeupARView: View {
    @StateObject private var viewModel = MakeupViewModel()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    Button(action: { print("Left button tapped") }) {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.cyan)
                            .padding()
                    }
                    Spacer()
                    Text("AI Makeup Assistant")
                        .font(.headline)
                        .foregroundColor(.cyan)
                    Spacer()
                    Button(action: { print("Right button tapped") }) {
                        Image(systemName: "camera")
                            .font(.title2)
                            .foregroundColor(.cyan)
                            .padding()
                    }
                }
                .frame(height: 60)
                .background(Color.black.opacity(0.3))
                
                Spacer().frame(height: 100)
                
                ARCameraView(viewModel: viewModel)
                    .frame(width: 380, height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white, lineWidth: 2))
                
                Spacer().frame(height: 40)
                
                FeatureSelectionView(viewModel: viewModel)
                Spacer()
                
                if viewModel.selectedFeature != nil {
                    ColorSelectionView(viewModel: viewModel)
                        .transition(.move(edge: .bottom))
                }
            }
            
            if viewModel.showColorPicker {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { viewModel.showColorPicker = false }
                
                VStack {
                    Spacer()
                    FullColorPickerView(viewModel: viewModel)
                        .transition(.move(edge: .bottom))
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

struct FeatureSelectionView: View {
    @ObservedObject var viewModel: MakeupViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Feature")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal)
            
            if let selected = viewModel.selectedFeature {
                Text("Feature - \(selected.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(MakeupFeature.allCases, id: \.self) { feature in
                        FeatureButton(
                            feature: feature,
                            isSelected: viewModel.selectedFeature == feature
                        ) {
                            withAnimation { viewModel.selectedFeature = feature }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
}

struct FeatureButton: View {
    let feature: MakeupFeature
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: feature.iconName)
                    .font(.title2)
                    .frame(width: 60, height: 60)
                    .background(isSelected ? Color.pink : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Text(feature.displayName)
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
    }
}

struct ColorSelectionView: View {
    @ObservedObject var viewModel: MakeupViewModel
    
    let presetColors: [Color] = [
        .red, .pink, Color(red: 0.9, green: 0.3, blue: 0.4),
        Color(red: 0.8, green: 0.2, blue: 0.3), .orange,
        Color(red: 0.7, green: 0.1, blue: 0.2), .purple,
        Color(red: 0.5, green: 0.0, blue: 0.3)
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(presetColors.indices, id: \.self) { index in
                            Circle()
                                .fill(presetColors[index])
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Circle()
                                        .stroke(viewModel.selectedColor == presetColors[index] ? Color.white : Color.clear, lineWidth: 3)
                                )
                                .onTapGesture { viewModel.selectedColor = presetColors[index] }
                        }
                    }
                    .padding(.horizontal)
                }
                
                Button(action: {
                    withAnimation { viewModel.showColorPicker = true }
                }) {
                    Image(systemName: "eyedropper")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.trailing)
            }
        }
        .padding(.bottom, 20)
    }
}

struct FullColorPickerView: View {
    @ObservedObject var viewModel: MakeupViewModel
    @State private var redValue: Double = 0
    @State private var greenValue: Double = 0
    @State private var blueValue: Double = 0
    @State private var hexInput: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray)
                .frame(width: 40, height: 5)
                .padding(.top, 10)
            
            Text("Custom Color Picker")
                .font(.headline)
                .foregroundColor(.white)
            
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: redValue, green: greenValue, blue: blueValue))
                .frame(height: 60)
                .padding(.horizontal)
            
            VStack(spacing: 15) {
                ColorSlider(label: "Red", value: $redValue, color: .red)
                ColorSlider(label: "Green", value: $greenValue, color: .green)
                ColorSlider(label: "Blue", value: $blueValue, color: .blue)
            }
            .padding(.horizontal)
            
            HStack {
                Text("Hex:")
                    .foregroundColor(.white)
                TextField("#RRGGBB", text: $hexInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: hexInput) { updateFromHex($0) }
            }
            .padding(.horizontal)
            
            ColorPicker("System Picker", selection: Binding(
                get: { Color(red: redValue, green: greenValue, blue: blueValue) },
                set: { color in
                    if let components = color.cgColor?.components {
                        redValue = components[0]
                        greenValue = components[1]
                        blueValue = components[2]
                        updateHex()
                    }
                }
            ))
            .padding(.horizontal)
            
            Button(action: {
                viewModel.selectedColor = Color(red: redValue, green: greenValue, blue: blueValue)
                withAnimation { viewModel.showColorPicker = false }
            }) {
                Text("Apply Color")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.pink)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .background(Color(white: 0.15))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
        .onAppear {
            if let components = viewModel.selectedColor.cgColor?.components {
                redValue = components[0]
                greenValue = components[1]
                blueValue = components[2]
                updateHex()
            }
        }
    }
    
    func updateFromHex(_ hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 else { return }
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        redValue = Double((rgb & 0xFF0000) >> 16) / 255.0
        greenValue = Double((rgb & 0x00FF00) >> 8) / 255.0
        blueValue = Double(rgb & 0x0000FF) / 255.0
    }
    
    func updateHex() {
        hexInput = String(format: "#%02X%02X%02X", Int(redValue * 255), Int(greenValue * 255), Int(blueValue * 255))
    }
}

struct ColorSlider: View {
    let label: String
    @Binding var value: Double
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.white)
                .frame(width: 50, alignment: .leading)
            Slider(value: $value, in: 0...1)
                .tint(color)
            Text("\(Int(value * 255))")
                .foregroundColor(.white)
                .frame(width: 40)
        }
    }
}

#Preview {
    MakeupARView()
}

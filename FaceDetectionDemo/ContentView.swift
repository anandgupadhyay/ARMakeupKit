//
//  ContentView.swift
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

// MARK: - Main App View
struct MakeupARView: View {
    @StateObject private var viewModel = MakeupViewModel()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Navigation Bar
                HStack {
                    Button(action: {
                        print("Left button tapped")
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                    }
                    
                    Spacer()
                    
                    Text("AR Makeup")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        print("Right button tapped")
                    }) {
                        Image(systemName: "camera")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                .frame(height: 60)
                .background(Color.black.opacity(0.3))
                
                Spacer()
                    .frame(height: 100)
                
                // AR Camera View
                ARCameraView(viewModel: viewModel)
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white, lineWidth: 2)
                    )
                
                Spacer()
                    .frame(height: 40)
                
                // Feature Selection
                FeatureSelectionView(viewModel: viewModel)
                
                Spacer()
                
                // Color Selection (shown when feature is selected)
                if viewModel.selectedFeature != nil {
                    ColorSelectionView(viewModel: viewModel)
                        .transition(.move(edge: .bottom))
                }
            }
            
            // Full Color Picker
            if viewModel.showColorPicker {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.showColorPicker = false
                    }
                
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

// MARK: - Feature Selection View
struct FeatureSelectionView: View {
    @ObservedObject var viewModel: MakeupViewModel
    
    let features: [MakeupFeature] = [
        .lip, .hair, .earring, .nose, .neck, .eye, .bindi
    ]
    
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
                    ForEach(features, id: \.self) { feature in
                        FeatureButton(
                            feature: feature,
                            isSelected: viewModel.selectedFeature == feature
                        ) {
                            withAnimation {
                                viewModel.selectedFeature = feature
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
}

// MARK: - Feature Button
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

// MARK: - Color Selection View
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
                                .onTapGesture {
                                    viewModel.selectedColor = presetColors[index]
                                }
                        }
                    }
                    .padding(.horizontal)
                }
                
                Button(action: {
                    withAnimation {
                        viewModel.showColorPicker = true
                    }
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

// MARK: - Full Color Picker View
struct FullColorPickerView: View {
    @ObservedObject var viewModel: MakeupViewModel
    @State private var redValue: Double = 0
    @State private var greenValue: Double = 0
    @State private var blueValue: Double = 0
    @State private var hexInput: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Handle bar
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray)
                .frame(width: 40, height: 5)
                .padding(.top, 10)
            
            Text("Custom Color Picker")
                .font(.headline)
                .foregroundColor(.white)
            
            // Preview
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: redValue, green: greenValue, blue: blueValue))
                .frame(height: 60)
                .padding(.horizontal)
            
            // RGB Sliders
            VStack(spacing: 15) {
                ColorSlider(label: "Red", value: $redValue, color: .red)
                ColorSlider(label: "Green", value: $greenValue, color: .green)
                ColorSlider(label: "Blue", value: $blueValue, color: .blue)
            }
            .padding(.horizontal)
            
            // Hex Input
            HStack {
                Text("Hex:")
                    .foregroundColor(.white)
                TextField("#RRGGBB", text: $hexInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: hexInput) { oldValue, newValue in
                        updateFromHex(newValue)
                    }
            }
            .padding(.horizontal)
            
            // Native Color Picker
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
            
            // Apply Button
            Button(action: {
                viewModel.selectedColor = Color(red: redValue, green: greenValue, blue: blueValue)
                withAnimation {
                    viewModel.showColorPicker = false
                }
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
        let r = Int(redValue * 255)
        let g = Int(greenValue * 255)
        let b = Int(blueValue * 255)
        hexInput = String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Color Slider
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

// MARK: - AR Camera View
struct ARCameraView: UIViewRepresentable {
    @ObservedObject var viewModel: MakeupViewModel
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        arView.delegate = context.coordinator
        arView.session.delegate = context.coordinator
        
        // Configure AR session for face tracking
        let configuration = ARFaceTrackingConfiguration()
        if ARFaceTrackingConfiguration.isSupported {
            arView.session.run(configuration)
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.viewModel = viewModel
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        var viewModel: MakeupViewModel
        var faceNode: SCNNode?
        var lipNode: SCNNode?
        
        init(viewModel: MakeupViewModel) {
            self.viewModel = viewModel
        }
        
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard let faceAnchor = anchor as? ARFaceAnchor else { return nil }
            
            let faceNode = SCNNode()
            self.faceNode = faceNode
            
            updateLipColor(for: faceAnchor, faceNode: faceNode)
            
            return faceNode
        }
        
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let faceAnchor = anchor as? ARFaceAnchor,
                  let faceNode = self.faceNode else { return }
            
            updateLipColor(for: faceAnchor, faceNode: faceNode)
        }
        
        func updateLipColor(for faceAnchor: ARFaceAnchor, faceNode: SCNNode) {
            // Remove existing lip node
            lipNode?.removeFromParentNode()
            
            // Only apply if Lip feature is selected
            guard viewModel.selectedFeature == .lip else { return }
            
            // Create geometry from face anchor
            let geometry = ARSCNFaceGeometry(device: MTLCreateSystemDefaultDevice()!)
            geometry?.update(from: faceAnchor.geometry)
            
            // Create material with selected color
            let material = SCNMaterial()
            if let components = viewModel.selectedColor.cgColor?.components {
                material.diffuse.contents = UIColor(
                    red: CGFloat(components[0]),
                    green: CGFloat(components[1]),
                    blue: CGFloat(components[2]),
                    alpha: 0.7
                )
            }
            material.transparency = 0.7
            
            geometry?.materials = [material]
            
            // Create node for lips only
            let node = SCNNode(geometry: geometry)
            node.renderingOrder = 10
            
            lipNode = node
            faceNode.addChildNode(node)
        }
    }
}

// MARK: - View Model
class MakeupViewModel: ObservableObject {
    @Published var selectedFeature: MakeupFeature?
    @Published var selectedColor: Color = .red
    @Published var showColorPicker: Bool = false
}

// MARK: - Makeup Feature Enum
enum MakeupFeature: String, CaseIterable, Hashable {
    case lip = "Lip"
    case hair = "Hair"
    case earring = "Earring"
    case nose = "Nose"
    case neck = "Neck"
    case eye = "Eye"
    case bindi = "Bindi"
    
    var displayName: String {
        return self.rawValue
    }
    
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

// MARK: - Preview
#Preview {
    MakeupARView()
}

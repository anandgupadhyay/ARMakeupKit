//
//  Untitled.swift
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

// MARK: - AR Camera View
struct ARCameraView: UIViewRepresentable {
    @ObservedObject var viewModel: MakeupViewModel
    
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true

        let scene = SCNScene()
        view.scene = scene

        if ARFaceTrackingConfiguration.isSupported {
            let configuration = ARFaceTrackingConfiguration()
            configuration.isLightEstimationEnabled = true
            view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }

        return view
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // No-op for now; updates handled via ARSession delegate
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
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
            // Remove previous feature overlay
            featureNode?.removeFromParentNode()
            featureNode = nil
            
            guard let feature = viewModel.selectedFeature,
                  let device = MTLCreateSystemDefaultDevice(),
                  let components = viewModel.selectedColor.cgColor?.components else { return }
            
            let color = UIColor(
                red: CGFloat(components[0]),
                green: CGFloat(components[1]),
                blue: CGFloat(components[2]),
                alpha: 0.7
            )
            
            // Create overlay geometry
            let overlayGeometry = ARSCNFaceGeometry(device: device)
            overlayGeometry?.update(from: anchor.geometry)
            
            // Create material with color
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.lightingModel = .physicallyBased
            
            // Apply material based on feature
            switch feature {
            case .lip:
                // Only show lips area
                if let indexData = createLipIndices(from: anchor.geometry) {
                    let element = SCNGeometryElement(
                        data: indexData,
                        primitiveType: .triangles,
                        primitiveCount: indexData.count / (3 * MemoryLayout<Int32>.size),
                        bytesPerIndex: MemoryLayout<Int32>.size
                    )
                    
                    let vertices = anchor.geometry.vertices.map {
                        SCNVector3($0.x, $0.y, $0.z)
                    }
                    let vertexSource = SCNGeometrySource(vertices: vertices)
                    
                    let customGeometry = SCNGeometry(sources: [vertexSource], elements: [element])
                    customGeometry.materials = [material]
                    
                    let featureNode = SCNNode(geometry: customGeometry)
                    node.addChildNode(featureNode)
                    self.featureNode = featureNode
                }
                
            case .nose:
                if let indexData = createNoseIndices(from: anchor.geometry) {
                    let element = SCNGeometryElement(
                        data: indexData,
                        primitiveType: .triangles,
                        primitiveCount: indexData.count / (3 * MemoryLayout<Int32>.size),
                        bytesPerIndex: MemoryLayout<Int32>.size
                    )
                    
                    let vertices = anchor.geometry.vertices.map {
                        SCNVector3($0.x, $0.y, $0.z)
                    }
                    let vertexSource = SCNGeometrySource(vertices: vertices)
                    
                    let customGeometry = SCNGeometry(sources: [vertexSource], elements: [element])
                    customGeometry.materials = [material]
                    
                    let featureNode = SCNNode(geometry: customGeometry)
                    node.addChildNode(featureNode)
                    self.featureNode = featureNode
                }
                
            case .bindi:
                // Forehead center
                let vertex = anchor.geometry.vertices[9]
                let sphere = SCNSphere(radius: 0.01)
                sphere.materials = [material]
                
                let bindiNode = SCNNode(geometry: sphere)
                bindiNode.position = SCNVector3(vertex.x, vertex.y, vertex.z)
                node.addChildNode(bindiNode)
                self.featureNode = bindiNode
                
            case .earring:
                // Left ear
                let leftEar = anchor.geometry.vertices[127]
                let leftSphere = SCNSphere(radius: 0.008)
                leftSphere.materials = [material]
                let leftNode = SCNNode(geometry: leftSphere)
                leftNode.position = SCNVector3(leftEar.x - 0.02, leftEar.y - 0.03, leftEar.z)
                
                // Right ear
                let rightEar = anchor.geometry.vertices[356]
                let rightSphere = SCNSphere(radius: 0.008)
                rightSphere.materials = [material]
                let rightNode = SCNNode(geometry: rightSphere)
                rightNode.position = SCNVector3(rightEar.x + 0.02, rightEar.y - 0.03, rightEar.z)
                
                let earringContainer = SCNNode()
                earringContainer.addChildNode(leftNode)
                earringContainer.addChildNode(rightNode)
                node.addChildNode(earringContainer)
                self.featureNode = earringContainer
                
            case .neck:
                if let indexData = createNeckIndices(from: anchor.geometry) {
                    let element = SCNGeometryElement(
                        data: indexData,
                        primitiveType: .triangles,
                        primitiveCount: indexData.count / (3 * MemoryLayout<Int32>.size),
                        bytesPerIndex: MemoryLayout<Int32>.size
                    )
                    
                    let vertices = anchor.geometry.vertices.map {
                        SCNVector3($0.x, $0.y, $0.z)
                    }
                    let vertexSource = SCNGeometrySource(vertices: vertices)
                    
                    let customGeometry = SCNGeometry(sources: [vertexSource], elements: [element])
                    customGeometry.materials = [material]
                    
                    let featureNode = SCNNode(geometry: customGeometry)
                    node.addChildNode(featureNode)
                    self.featureNode = featureNode
                }
                
            case .hair:
                if let indexData = createHairIndices(from: anchor.geometry) {
                    let element = SCNGeometryElement(
                        data: indexData,
                        primitiveType: .triangles,
                        primitiveCount: indexData.count / (3 * MemoryLayout<Int32>.size),
                        bytesPerIndex: MemoryLayout<Int32>.size
                    )
                    
                    let vertices = anchor.geometry.vertices.map {
                        SCNVector3($0.x, $0.y, $0.z)
                    }
                    let vertexSource = SCNGeometrySource(vertices: vertices)
                    
                    let customGeometry = SCNGeometry(sources: [vertexSource], elements: [element])
                    customGeometry.materials = [material]
                    
                    let featureNode = SCNNode(geometry: customGeometry)
                    node.addChildNode(featureNode)
                    self.featureNode = featureNode
                }
                
            default:
                break
            }
        }
        
        // Helper functions to create indices for specific features
        func createLipIndices(from geometry: ARFaceGeometry) -> Data? {
            let triangleIndices = geometry.triangleIndices.map { Int32($0) }
            var lipIndices: [Int32] = []
            
            // Lip region vertex range (approximate)
            let lipVertexRange = Set(0..<50) // Lower face vertices
            
            for i in stride(from: 0, to: triangleIndices.count, by: 3) {
                let v1 = triangleIndices[i]
                let v2 = triangleIndices[i + 1]
                let v3 = triangleIndices[i + 2]
                
                // Check if vertices are in lip region
                let vertex1 = geometry.vertices[Int(v1)]
                let vertex2 = geometry.vertices[Int(v2)]
                let vertex3 = geometry.vertices[Int(v3)]
                
                // Lip region: y < -0.02 and y > -0.08, centered around x=0
                if isInLipRegion(vertex1) && isInLipRegion(vertex2) && isInLipRegion(vertex3) {
                    lipIndices.append(v1)
                    lipIndices.append(v2)
                    lipIndices.append(v3)
                }
            }
            
            guard !lipIndices.isEmpty else { return nil }
            return Data(bytes: lipIndices, count: lipIndices.count * MemoryLayout<Int32>.size)
        }
        
        func isInLipRegion(_ vertex: vector_float3) -> Bool {
            return vertex.y < -0.02 && vertex.y > -0.08 &&
                   abs(vertex.x) < 0.04 &&
                   vertex.z > -0.06
        }
        
        func createNoseIndices(from geometry: ARFaceGeometry) -> Data? {
            let triangleIndices = geometry.triangleIndices.map { Int32($0) }
            var noseIndices: [Int32] = []
            
            for i in stride(from: 0, to: triangleIndices.count, by: 3) {
                let v1 = triangleIndices[i]
                let v2 = triangleIndices[i + 1]
                let v3 = triangleIndices[i + 2]
                
                let vertex1 = geometry.vertices[Int(v1)]
                let vertex2 = geometry.vertices[Int(v2)]
                let vertex3 = geometry.vertices[Int(v3)]
                
                if isInNoseRegion(vertex1) && isInNoseRegion(vertex2) && isInNoseRegion(vertex3) {
                    noseIndices.append(v1)
                    noseIndices.append(v2)
                    noseIndices.append(v3)
                }
            }
            
            guard !noseIndices.isEmpty else { return nil }
            return Data(bytes: noseIndices, count: noseIndices.count * MemoryLayout<Int32>.size)
        }
        
        func isInNoseRegion(_ vertex: vector_float3) -> Bool {
            return vertex.y > -0.02 && vertex.y < 0.04 &&
                   abs(vertex.x) < 0.025 &&
                   vertex.z > 0.0
        }
        
        func createNeckIndices(from geometry: ARFaceGeometry) -> Data? {
            let triangleIndices = geometry.triangleIndices.map { Int32($0) }
            var neckIndices: [Int32] = []
            
            for i in stride(from: 0, to: triangleIndices.count, by: 3) {
                let v1 = triangleIndices[i]
                let v2 = triangleIndices[i + 1]
                let v3 = triangleIndices[i + 2]
                
                let vertex1 = geometry.vertices[Int(v1)]
                let vertex2 = geometry.vertices[Int(v2)]
                let vertex3 = geometry.vertices[Int(v3)]
                
                if isInNeckRegion(vertex1) && isInNeckRegion(vertex2) && isInNeckRegion(vertex3) {
                    neckIndices.append(v1)
                    neckIndices.append(v2)
                    neckIndices.append(v3)
                }
            }
            
            guard !neckIndices.isEmpty else { return nil }
            return Data(bytes: neckIndices, count: neckIndices.count * MemoryLayout<Int32>.size)
        }
        
        func isInNeckRegion(_ vertex: vector_float3) -> Bool {
            return vertex.y < -0.08 && abs(vertex.x) < 0.06
        }
        
        func createHairIndices(from geometry: ARFaceGeometry) -> Data? {
            let triangleIndices = geometry.triangleIndices.map { Int32($0) }
            var hairIndices: [Int32] = []
            
            for i in stride(from: 0, to: triangleIndices.count, by: 3) {
                let v1 = triangleIndices[i]
                let v2 = triangleIndices[i + 1]
                let v3 = triangleIndices[i + 2]
                
                let vertex1 = geometry.vertices[Int(v1)]
                let vertex2 = geometry.vertices[Int(v2)]
                let vertex3 = geometry.vertices[Int(v3)]
                
                if isInHairRegion(vertex1) && isInHairRegion(vertex2) && isInHairRegion(vertex3) {
                    hairIndices.append(v1)
                    hairIndices.append(v2)
                    hairIndices.append(v3)
                }
            }
            
            guard !hairIndices.isEmpty else { return nil }
            return Data(bytes: hairIndices, count: hairIndices.count * MemoryLayout<Int32>.size)
        }
        
        func isInHairRegion(_ vertex: vector_float3) -> Bool {
            return vertex.y > 0.04 && abs(vertex.x) < 0.08
        }
    }
}

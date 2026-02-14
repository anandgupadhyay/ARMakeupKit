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
            configuration.maximumNumberOfTrackedFaces = 1
            view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        } else {
            print("⚠️ ARFaceTrackingConfiguration is not supported on this device")
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
        
        // Handle AR session errors
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("⚠️ AR Session failed with error: \(error.localizedDescription)")
        }
        
        func sessionWasInterrupted(_ session: ARSession) {
            print("⚠️ AR Session was interrupted")
        }
        
        func sessionInterruptionEnded(_ session: ARSession) {
            print("✅ AR Session interruption ended")
        }
        
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard let faceAnchor = anchor as? ARFaceAnchor else { return nil }
            guard let device = MTLCreateSystemDefaultDevice() else {
                print("⚠️ Failed to create Metal device")
                return nil
            }
            
            guard let faceGeometry = ARSCNFaceGeometry(device: device) else {
                print("⚠️ Failed to create ARSCNFaceGeometry")
                return nil
            }
            
            let node = SCNNode(geometry: faceGeometry)
            node.geometry?.firstMaterial?.fillMode = .lines
            node.geometry?.firstMaterial?.transparency = 0.0
            
            self.faceNode = node
            faceGeometry.update(from: faceAnchor.geometry)
            
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

            guard let feature = viewModel.selectedFeature else { return }
            guard let cgColor = viewModel.selectedColor.cgColor,
                  let components = cgColor.components,
                  components.count >= 3 else {
                print("⚠️ Invalid color components")
                return
            }

            // Enhanced color with better alpha and rendering properties
            let color = UIColor(
                red: CGFloat(components[0]),
                green: CGFloat(components[1]),
                blue: CGFloat(components[2]),
                alpha: 0.85  // Increased opacity for better visibility
            )

            let material = SCNMaterial()
            material.diffuse.contents = color
            material.lightingModel = .constant  // Changed to constant for better color accuracy
            material.isDoubleSided = true
            material.writesToDepthBuffer = true
            material.readsFromDepthBuffer = true
            // Blending mode for better color rendering
            material.blendMode = .alpha
            material.transparencyMode = .dualLayer

            let faceGeometry = anchor.geometry

            switch feature {
            case .lip:
                // Try using heuristic region first for better accuracy
                if let indexData = createLipIndices(from: faceGeometry) {
                    let element = SCNGeometryElement(
                        data: indexData,
                        primitiveType: .triangles,
                        primitiveCount: indexData.count / (3 * MemoryLayout<Int32>.size),
                        bytesPerIndex: MemoryLayout<Int32>.size
                    )
                    
                    // Create geometry with vertices and texture coordinates
                    let vertices = faceGeometry.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
                    let texCoords = faceGeometry.textureCoordinates.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
                    
                    let vertexSource = SCNGeometrySource(vertices: vertices)
                    let texCoordSource = SCNGeometrySource(textureCoordinates: texCoords)
                    
                    // Calculate normals from the geometry
                    let normalSource: SCNGeometrySource
                    if let device = MTLCreateSystemDefaultDevice(),
                       let tempGeometry = ARSCNFaceGeometry(device: device) {
                        tempGeometry.update(from: faceGeometry)
                        normalSource = tempGeometry.sources(for: .normal).first ?? SCNGeometrySource(normals: vertices.map { _ in SCNVector3(0, 0, 1) })
                    } else {
                        // Fallback: use simple forward-facing normals
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
                    // fallback to predefined triangles
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
                } else if let indexData = createNoseIndices(from: faceGeometry) {
                    let element = SCNGeometryElement(
                        data: indexData,
                        primitiveType: .triangles,
                        primitiveCount: indexData.count / (3 * MemoryLayout<Int32>.size),
                        bytesPerIndex: MemoryLayout<Int32>.size
                    )
                    let vertices = faceGeometry.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
                    let vertexSource = SCNGeometrySource(vertices: vertices)
                    let customGeometry = SCNGeometry(sources: [vertexSource], elements: [element])
                    customGeometry.materials = [material]
                    let nodeGeom = SCNNode(geometry: customGeometry)
                    node.addChildNode(nodeGeom)
                    self.featureNode = nodeGeom
                }

            case .earring:
                // Keep spheres but refine positions using cheek/ear-adjacent vertices
                let vertexCount = Int(faceGeometry.vertices.count)
                let left = min(Self.leftEarApproxIndex, vertexCount - 1)
                let right = min(Self.rightEarApproxIndex, vertexCount - 1)
                
                guard left >= 0 && left < vertexCount && right >= 0 && right < vertexCount else {
                    print("⚠️ Invalid earring vertex indices")
                    return
                }
                
                let leftV = faceGeometry.vertices[left]
                let rightV = faceGeometry.vertices[right]

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
                } else if let indexData = createHairIndices(from: faceGeometry) {
                    let element = SCNGeometryElement(
                        data: indexData,
                        primitiveType: .triangles,
                        primitiveCount: indexData.count / (3 * MemoryLayout<Int32>.size),
                        bytesPerIndex: MemoryLayout<Int32>.size
                    )
                    let vertices = faceGeometry.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
                    let vertexSource = SCNGeometrySource(vertices: vertices)
                    let customGeometry = SCNGeometry(sources: [vertexSource], elements: [element])
                    customGeometry.materials = [material]
                    let nodeGeom = SCNNode(geometry: customGeometry)
                    node.addChildNode(nodeGeom)
                    self.featureNode = nodeGeom
                }

            case .neck:
                if let geom = makeGeometry(from: faceGeometry, with: Self.jawlineTriangles) {
                    geom.materials = [material]
                    let nodeGeom = SCNNode(geometry: geom)
                    node.addChildNode(nodeGeom)
                    self.featureNode = nodeGeom
                } else if let indexData = createNeckIndices(from: faceGeometry) {
                    let element = SCNGeometryElement(
                        data: indexData,
                        primitiveType: .triangles,
                        primitiveCount: indexData.count / (3 * MemoryLayout<Int32>.size),
                        bytesPerIndex: MemoryLayout<Int32>.size
                    )
                    let vertices = faceGeometry.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
                    let vertexSource = SCNGeometrySource(vertices: vertices)
                    let customGeometry = SCNGeometry(sources: [vertexSource], elements: [element])
                    customGeometry.materials = [material]
                    let nodeGeom = SCNNode(geometry: customGeometry)
                    node.addChildNode(nodeGeom)
                    self.featureNode = nodeGeom
                }

            case .bindi:
                // Estimate forehead center: a bit above nose bridge midpoint
                let vertexCount = Int(faceGeometry.vertices.count)
                let noseBridgeIdx = min(9, vertexCount - 1)
                
                guard noseBridgeIdx >= 0 && noseBridgeIdx < vertexCount else {
                    print("⚠️ Invalid bindi vertex index")
                    return
                }
                
                let v = faceGeometry.vertices[noseBridgeIdx]
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
        
        // Helper functions to create indices for specific features
        func createLipIndices(from geometry: ARFaceGeometry) -> Data? {
            let triangleIndices = geometry.triangleIndices.map { Int32($0) }
            let vertexCount = geometry.vertices.count
            var lipIndices: [Int32] = []
            var validTriangleCount = 0
            
            for i in stride(from: 0, to: triangleIndices.count - 2, by: 3) {
                let v1 = triangleIndices[i]
                let v2 = triangleIndices[i + 1]
                let v3 = triangleIndices[i + 2]
                
                // Bounds check
                guard Int(v1) < vertexCount && Int(v2) < vertexCount && Int(v3) < vertexCount else {
                    continue
                }
                
                // Check if vertices are in lip region
                let vertex1 = geometry.vertices[Int(v1)]
                let vertex2 = geometry.vertices[Int(v2)]
                let vertex3 = geometry.vertices[Int(v3)]
                
                // Count how many vertices are in lip region
                let inRegionCount = [vertex1, vertex2, vertex3].filter { isInLipRegion($0) }.count
                
                // Only include triangles where ALL vertices are in lip region
                // This prevents extending beyond lip boundaries
                if inRegionCount == 3 {
                    lipIndices.append(v1)
                    lipIndices.append(v2)
                    lipIndices.append(v3)
                    validTriangleCount += 1
                }
            }
            
            guard !lipIndices.isEmpty else { return nil }
            return Data(bytes: lipIndices, count: lipIndices.count * MemoryLayout<Int32>.size)
        }
        
        func isInLipRegion(_ vertex: vector_float3) -> Bool {
            // Much more refined lip region with elliptical shape
            let y = vertex.y
            let x = vertex.x
            let z = vertex.z
            
            // Use tunable parameters from viewModel
            let verticalMin = Float(viewModel.lipVerticalMin)
            let verticalMax = Float(viewModel.lipVerticalMax)
            let horizontalMax = Float(viewModel.lipHorizontalMax)
            let depthMin = Float(viewModel.lipDepthMin)
            
            // Vertical range for lips (tighter)
            guard y > verticalMin && y < verticalMax else { return false }
            
            // Depth check - lips are forward-facing
            guard z > depthMin else { return false }
            
            // Elliptical horizontal constraint (narrower at top and bottom)
            let verticalCenter = (verticalMin + verticalMax) / 2.0
            let verticalRange = verticalMax - verticalMin
            let yNormalized = (y - verticalCenter) / verticalRange  // Normalize to -0.5 to 0.5
            
            // Create elliptical shape - wider in middle, narrower at edges
            let ellipseMultiplier = 1.0 - abs(yNormalized) * 0.8
            let maxXAtY = horizontalMax * ellipseMultiplier
            
            // Check if within elliptical boundary
            guard abs(x) < maxXAtY else { return false }
            
            // Additional center check - lips are more prominent in the center
            let distanceFromCenter = sqrt(x * x + (y - verticalCenter) * (y - verticalCenter) * 4.0)
            
            return distanceFromCenter < 0.065
        }
        
        func createNoseIndices(from geometry: ARFaceGeometry) -> Data? {
            let triangleIndices = geometry.triangleIndices.map { Int32($0) }
            let vertexCount = geometry.vertices.count
            var noseIndices: [Int32] = []
            
            for i in stride(from: 0, to: triangleIndices.count - 2, by: 3) {
                let v1 = triangleIndices[i]
                let v2 = triangleIndices[i + 1]
                let v3 = triangleIndices[i + 2]
                
                // Bounds check
                guard Int(v1) < vertexCount && Int(v2) < vertexCount && Int(v3) < vertexCount else {
                    continue
                }
                
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
            let vertexCount = geometry.vertices.count
            var neckIndices: [Int32] = []
            
            for i in stride(from: 0, to: triangleIndices.count - 2, by: 3) {
                let v1 = triangleIndices[i]
                let v2 = triangleIndices[i + 1]
                let v3 = triangleIndices[i + 2]
                
                // Bounds check
                guard Int(v1) < vertexCount && Int(v2) < vertexCount && Int(v3) < vertexCount else {
                    continue
                }
                
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
            let vertexCount = geometry.vertices.count
            var hairIndices: [Int32] = []
            
            for i in stride(from: 0, to: triangleIndices.count - 2, by: 3) {
                let v1 = triangleIndices[i]
                let v2 = triangleIndices[i + 1]
                let v3 = triangleIndices[i + 2]
                
                // Bounds check
                guard Int(v1) < vertexCount && Int(v2) < vertexCount && Int(v3) < vertexCount else {
                    continue
                }
                
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
        
        // Approximate, curated triangle sets for features. These are small and safe index triplets.
        // Note: ARFaceGeometry typically has ~1220 vertices and ~2200 triangles; indices below are conservative.
        // Lips in ARKit face mesh - these indices correspond to the mouth region
        static let lipTriangles: [Int32] = [
            // Upper lip region
            37, 267, 269,  269, 270, 409,  409, 270, 291,
            61, 185, 40,   40, 185, 39,    39, 185, 37,
            // Lower lip region  
            146, 91, 181,  181, 84, 17,    17, 84, 314,
            314, 405, 321, 321, 375, 291,  
            // Center mouth area
            78, 191, 80,   80, 191, 81,    81, 191, 82,
            82, 13, 312,   312, 13, 311,   311, 13, 310,
            // Additional lip coverage
            61, 146, 91,   91, 146, 181,   181, 146, 84,
            // Corners and edges
            40, 39, 37,    37, 0, 267,     267, 0, 269,
            321, 405, 375, 375, 291, 409
        ]

        static let noseTriangles: [Int32] = [
            6,  7,  9,   7,  10, 9,   9,  10, 11,  11, 10, 12,
            12, 13, 14,  11, 12, 14
        ]

        static let leftEyeTriangles: [Int32] = [
            106, 107, 108,  108, 109, 110,  110, 111, 106
        ]

        static let rightEyeTriangles: [Int32] = [
            276, 277, 278,  278, 279, 280,  280, 281, 276
        ]

        static let hairlineTriangles: [Int32] = [
            18, 19, 20,  20, 21, 22,  22, 23, 18
        ]

        static let jawlineTriangles: [Int32] = [
            50, 51, 60,  60, 61, 62,  62, 63, 64,  64, 65, 50
        ]

        static let leftEarApproxIndex: Int = 127
        static let rightEarApproxIndex: Int = 356
    }
}


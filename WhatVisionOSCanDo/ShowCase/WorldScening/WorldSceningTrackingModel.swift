//
//  TrackingModel.swift
//  WhatVisionOSCanDo
//
//  Created by onee on 2023/8/11.
//

import ARKit
import Foundation
import RealityKit
import ARKit
import SwiftUI

class WorldSceningTrackingModel: TrackingModel {
    let sceneDataProvider = SceneReconstructionProvider(modes: [.classification])
    
    @MainActor func run(enableGeoMesh: Bool, enableMeshClassfication: Bool) async {
        var providers: [DataProvider] = []
        if SceneReconstructionProvider.isSupported {
            providers.append(sceneDataProvider)
        }
        do {
            try await session.run(providers)
            for await sceneUpdate in sceneDataProvider.anchorUpdates {
                let anchor = sceneUpdate.anchor
                let geometry = anchor.geometry
                switch sceneUpdate.event {
                    case .added:
                        // print classifications
                        print("add anchor classification is \(String(describing: geometry.classifications))")
                        try await createMeshEntity(geometry, anchor)
                        let meshCount = rootEntity.children.count
                        print("There are now \(meshCount) meshes")
                    case .updated:
                        try await updateMeshEntity(geometry, anchor)
                    case .removed:
                        print("removed anchor classification is \(String(describing: geometry.classifications))")
                        try removeMeshEntity(geometry, anchor)
                }
            }
        } catch {
            print("error is \(error)")
        }
    }
    
    // MARK: Geometry Mesh
    
    @MainActor fileprivate  func createMeshEntity(_ geometry: MeshAnchor.Geometry, _ anchor: MeshAnchor) async throws  {
        let modelEntity = try await generateModelEntity(anchorId: anchor.id, geometry: geometry)
        let anchorEntity = AnchorEntity(world: anchor.originFromAnchorTransform)
        anchorEntity.addChild(modelEntity)
        anchorEntity.name = "MeshAnchor-\(anchor.id)"
        rootEntity.addChild(anchorEntity)
    }
    
    @MainActor fileprivate func updateMeshEntity(_ geometry: MeshAnchor.Geometry, _ anchor: MeshAnchor) async throws {
        let modelEntity = try await generateModelEntity(anchorId: anchor.id, geometry: geometry)
        if let anchorEntity = rootEntity.findEntity(named: "MeshAnchor-\(anchor.id)") {
            anchorEntity.children.removeAll()
            anchorEntity.addChild(modelEntity)
        }
    }
    
    fileprivate func removeMeshEntity(_ geometry: MeshAnchor.Geometry, _ anchor: MeshAnchor) throws {
        if let anchorEntity = rootEntity.findEntity(named: "MeshAnchor-\(anchor.id)") {
            anchorEntity.removeFromParent()
        }
    }
    
    // MARK: Helpers
    
    private func colorFromUUID(_ uuid: UUID) -> SimpleMaterial.Color {
        var redByte: UInt8 = 0
        var greenByte: UInt8 = 0
        var blueByte: UInt8 = 0
        
        // Extract bytes from UUID
        let data = withUnsafePointer(to: uuid.uuid) {
            Data(bytes: $0, count: MemoryLayout.size(ofValue: uuid.uuid))
        }
        
        // Use specific bytes for color components
        redByte = data[0]
        greenByte = data[1]
        blueByte = data[2]
        
        // Normalize the values to [0, 1] for UIColor
        let red = CGFloat(redByte) / 255.0
        let green = CGFloat(greenByte) / 255.0
        let blue = CGFloat(blueByte) / 255.0
        
        return SimpleMaterial.Color(red: red, green: green, blue: blue, alpha: 1.0)
    }
    
    @MainActor fileprivate func generateModelEntity(anchorId: UUID,geometry: MeshAnchor.Geometry) async throws -> ModelEntity {
        // generate mesh
        var desc = MeshDescriptor()
        let posValues = geometry.vertices.asSIMD3(ofType: Float.self)
        desc.positions = .init(posValues)
        let normalValues = geometry.normals.asSIMD3(ofType: Float.self)
        desc.normals = .init(normalValues)
        do {
            desc.primitives = .polygons(
                // 应该都是三角形，所以这里直接写 3
                (0..<geometry.faces.count).map { _ in UInt8(3) },
                (0..<geometry.faces.count * 3).map {
                    geometry.faces.buffer.contents()
                        .advanced(by: $0 * geometry.faces.bytesPerIndex)
                        .assumingMemoryBound(to: UInt32.self).pointee
                }
            )
        }
        let meshResource = try MeshResource.generate(from: [desc])
        let material = SimpleMaterial(color: colorFromUUID(anchorId), isMetallic: false)
        let modelEntity = ModelEntity(mesh: meshResource, materials: [material])
        return modelEntity
    }
}

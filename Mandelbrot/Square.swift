//
//  Square.swift
//  Mandelbrot
//
//  Created by Andriy K. on 2/4/16.
//  Copyright © 2016 Andriy K. All rights reserved.
//

import Foundation
import MetalKit

struct Vertex {
    let x, y, z : Float
}

struct Square {
    var vertexBuffer: MTLBuffer?
    var vertexCount: Int
    
    init(device: MTLDevice) {
        let A = Vertex(x: -1.0, y: -1.0, z: 0),
            B = Vertex(x: -1.0, y: 1.0, z: 0),
            C = Vertex(x: 1.0, y: -1.0, z: 0),
            D = Vertex(x: 1.0, y: 1.0, z: 0)
        
        let vertices = [A, B, C, B, D, C]
        
        vertexCount = vertices.count
        vertexBuffer = Self.createVertexBuffer(device: device, vertices: vertices)
    }
    
    static func createVertexBuffer(device: MTLDevice, vertices: [Vertex]) -> MTLBuffer? {
        guard !vertices.isEmpty else {
            return nil
        }
        
        return device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            options: []
        )
    }
    
    static func defaultSampler(for device:MTLDevice) -> MTLSamplerState? {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.mipFilter = .nearest
        samplerDescriptor.maxAnisotropy = 1
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.rAddressMode = .clampToEdge
        samplerDescriptor.normalizedCoordinates = true
        samplerDescriptor.lodMinClamp = 0
        samplerDescriptor.lodMaxClamp = .greatestFiniteMagnitude
        
        return device.makeSamplerState(descriptor: samplerDescriptor)
    }
}

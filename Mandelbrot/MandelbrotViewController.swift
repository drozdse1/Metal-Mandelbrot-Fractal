//
//  ViewController.swift
//  Mandelbrot
//
//  Created by Andriy K. on 2/4/16.
//  Copyright © 2016 Andriy K. All rights reserved.
//

import Cocoa
import MetalKit
import os

class MandelbrotViewController: NSViewController {
    
    let logger = Logger()

    // MARK: - Metal Properties

    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var depthStencilState: MTLDepthStencilState!
    private var paletteTexture: MTLTexture!
    private var samplerState: MTLSamplerState!
    private var uniformBufferProvider: BufferProvider!
    private var mandelbrotSceneUniform = Uniform()

    // MARK: - Flags and Objects

    private var needsRedraw = true
    private var forceAlwaysDraw = false
    private var square: Square!
    private var oldZoom: Float = 1.0
    private var shiftX: Float = 0
    private var shiftY: Float = 0
    
    private let infoConsole = NSTextField(labelWithString: "Coordinates: X:\(0.0) Y:\(0.0), Zoom: \(0.0)")

    // MARK: - Outlets

    @IBOutlet var metalView: MTKView! {
        didSet {
            metalView.device = device
            metalView.delegate = self
            metalView.preferredFramesPerSecond = 60
            metalView.depthStencilPixelFormat = .depth32Float_stencil8
        }
    }
    
    // MARK: - View Controller Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMetal()
        setupPipeline()
        
        // add simple console for debug and info output
        infoConsole.translatesAutoresizingMaskIntoConstraints = false
        infoConsole.textColor = .white

        metalView.addSubview(infoConsole)
        
        // Manually call drawableSizeWillChange with the initial drawable size
        mtkView(metalView, drawableSizeWillChange: metalView.drawableSize)
    }

    // MARK: - Metal Setup

    private func setupMetal() {
        device = MTLCreateSystemDefaultDevice()
        metalView.device = device
        commandQueue = device.makeCommandQueue()
        square = Square(device: device)

        let textureLoader = MTKTextureLoader(device: device)
        let path = Bundle.main.path(forResource: "pal", ofType: "png")!
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        paletteTexture = try! textureLoader.newTexture(data: data, options: nil)
        samplerState = Square.defaultSampler(for: device)
        uniformBufferProvider = BufferProvider(inFlightBuffers: 3, device: device)
    }

    // MARK: - Pipeline Setup

    private func setupPipeline() {
        guard let defaultLibrary = device.makeDefaultLibrary(),
              let vertexProgram = defaultLibrary.makeFunction(name: "vertexShader"),
              let fragmentProgram = defaultLibrary.makeFunction(name: "fragmentShader") else {
            fatalError("Failed to create shaders or library.")
        }
        
        let metalVertexDescriptor = createVertexDescriptor()
        pipelineState = compiledPipelineStateFrom(vertexShader: vertexProgram,
                                           fragmentShader: fragmentProgram,
                                           vertexDescriptor: metalVertexDescriptor)
        depthStencilState = compiledDepthState()
    }

    // MARK: - Vertex Descriptor Creation

    private func createVertexDescriptor() -> MTLVertexDescriptor {
        let metalVertexDescriptor = MTLVertexDescriptor()
        if let attribute = metalVertexDescriptor.attributes[0] {
            attribute.format = .float3
            attribute.offset = 0
            attribute.bufferIndex = 0
        }
        if let layout = metalVertexDescriptor.layouts[0] {
            layout.stride = MemoryLayout<Float>.size * 3
        }
        return metalVertexDescriptor
    }
}

// MARK: - Compiled states
extension MandelbrotViewController {
    
    /// Compile vertex, fragment shaders and vertex descriptor into pipeline state object
    func compiledPipelineStateFrom(vertexShader: MTLFunction,
                                   fragmentShader: MTLFunction, vertexDescriptor: MTLVertexDescriptor) -> MTLRenderPipelineState? {
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexDescriptor = vertexDescriptor
        pipelineStateDescriptor.vertexFunction = vertexShader
        pipelineStateDescriptor.fragmentFunction = fragmentShader
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        pipelineStateDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        pipelineStateDescriptor.stencilAttachmentPixelFormat = metalView.depthStencilPixelFormat
        
        let compiledState = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        return compiledState
    }
    
    /// Compile depth/stencil descriptor into state object
    /// We don't really need depth check for this example but it's a good thing to have
    func compiledDepthState() -> MTLDepthStencilState {
        let depthStencilDesc = MTLDepthStencilDescriptor()
        depthStencilDesc.depthCompareFunction = MTLCompareFunction.less
        depthStencilDesc.isDepthWriteEnabled = true
        
        return device.makeDepthStencilState(descriptor: depthStencilDesc)!
    }
}


// MARK: - Zoom & Move
extension MandelbrotViewController {
    
    // MARK: - Mouse Dragging
    
    override func mouseDragged(with mouseEvent: NSEvent) {
        super.mouseDragged(with: mouseEvent)
        
        let xDelta = Float(mouseEvent.deltaX / view.bounds.width)
        let yDelta = Float(mouseEvent.deltaY / view.bounds.height)
        
        shiftX += 3 * xDelta / oldZoom
        shiftY -= 3 * yDelta / oldZoom
        
        updateMandelbrotSceneUniform()
        
        infoConsole.stringValue = "Coordinates: X:\(shiftX) Y:\(shiftY), Zoom: \(oldZoom)"
    }
    
    // MARK: - Scroll Wheel
    
    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        
        logger.log("scrollingDeltaY: \(event.scrollingDeltaY)")
        
        let zoom = Float(event.scrollingDeltaY) / 20
        let zoomMultiplier = Float(max(Int(oldZoom / 100), 1)) // Speed up zooming as you go deeper
        
        oldZoom += zoom * zoomMultiplier
        oldZoom = max(1, oldZoom)
        
        logger.log("oldZoom: \(self.oldZoom)")
        
        updateMandelbrotSceneUniform()
        
        infoConsole.stringValue = "Coordinates: X:\(shiftX) Y:\(shiftY), Zoom: \(oldZoom)"
    }
    
    // MARK: - Update Mandelbrot Scene Uniform
    
    private func updateMandelbrotSceneUniform() {
        mandelbrotSceneUniform.translation = (shiftX, shiftY)
        mandelbrotSceneUniform.scale = 1 / oldZoom
        needsRedraw = true
    }
}


extension MandelbrotViewController: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        mandelbrotSceneUniform.aspectRatio = Float(size.width / size.height)
        needsRedraw = true
    }

    func draw(in view: MTKView) {
        guard needsRedraw || forceAlwaysDraw else { return }
        
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        configureRenderPassDescriptor(renderPassDescriptor, with: drawable)
        
        renderEncoderState(renderEncoder)
        setVertexBuffer(renderEncoder)
        setUniformBuffers(renderEncoder)
        setFragmentTextures(renderEncoder)
        
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        view.drawPageBorder(with: NSSize(width: 20, height: 3))
        
        needsRedraw = false
    }


    // MARK: - Rendering Configuration Methods

    private func configureRenderPassDescriptor(_ renderPassDescriptor: MTLRenderPassDescriptor, with drawable: CAMetalDrawable) {
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1.0, green: 0.4, blue: 0.6, alpha: 1.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
    }

    private func renderEncoderState(_ renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setCullMode(.none)
    }

    private func setVertexBuffer(_ renderEncoder: MTLRenderCommandEncoder) {
        if let squareBuffer = square?.vertexBuffer {
            renderEncoder.setVertexBuffer(squareBuffer, offset: 0, index: 0)
        }
    }

    private func setUniformBuffers(_ renderEncoder: MTLRenderCommandEncoder) {
        let uniformBuffer = uniformBufferProvider.nextBufferWithData(mandelbrotSceneUniform)
        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
    }

    private func setFragmentTextures(_ renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setFragmentTexture(paletteTexture, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
    }
}

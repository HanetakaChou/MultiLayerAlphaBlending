/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which perfoms Metal setup and per frame rendering
*/
@import simd;
@import ModelIO;
@import MetalKit;

#import "AAPLRenderer.h"
#import "AAPLMesh.h"
#import "AAPLMathUtilities.h"

// Include header shared between C code here, which executes Metal API commands, and .metal files
#import "AAPLShaderTypes.h"

// The max number of command buffers in flight
static const NSUInteger AAPLMaxBuffersInFlight = 3;

// Main class performing the rendering
@implementation AAPLRenderer
{
    CGSize _windowSize;

    NSUInteger _frameNum;
    
    dispatch_semaphore_t _inFlightSemaphore;
    id <MTLDevice> _device;
    id <MTLCommandQueue> _commandQueue;

    // Buffer for uniforms which change per-frame
    id <MTLBuffer> _frameUniformBuffers[AAPLMaxBuffersInFlight];
    
    MTLRenderPassDescriptor *_MLABRenderPassDescriptor;
    id <MTLRenderPipelineState> _kbuffer_RMW_PipelineState;
    id <MTLRenderPipelineState> _resolvePipelineState;
    
    id <MTLDepthStencilState> _compositePassDepthState;
    
    // We have a fragment shader per rendering method
    id <MTLDepthStencilState> _depthState;
    
    // Metal vertex descriptor specifying how vertices will by laid out  render
    //   for input into our pipeline and how we'll layout our ModelIO vertices
    MTLVertexDescriptor *_mtlVertexDescriptor;

    // Used to determine _uniformBufferStride each frame.
    //   This is the current frame number modulo AAPLMaxBuffersInFlight
    uint8_t _uniformBufferIndex;

    // Projection matrix calculated as a function of view size
    matrix_float4x4 _projectionMatrix;

    // Current rotation of our object in radians
    float _rotation;

    // Array of App-Specific mesh objects in our scene
    NSArray<AAPLMesh *> *_meshes;
}

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view
{
    self = [super init];
    if(self)
    {
        _device = view.device;

        //if(![_device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily4_v1])
        //{
            // This sample requires features avaliable with the iOS_GPUFamily4_v1 feature set
            //   (which is avaliable on devices with A11 GPUs or later).  If the iOS_GPUFamily4_v1
            //   feature set is is unavliable, the app would need to implement a backup path that
            //   does not use many of the APIs demonstated in this sample.  However, the
            //   implementation of such a backup path is beyond the scope of this sample.
        //    assert(!"Sample requires GPUFamily4_v1 (introduced with A11)");
        //    return nil;
        //}

        _inFlightSemaphore = dispatch_semaphore_create(AAPLMaxBuffersInFlight);

        [self loadMetalWithMetalKitView:view];
        [self loadAssets];
    }

    return self;
}

/// Create and load our basic Metal state objects
- (void)loadMetalWithMetalKitView:(nonnull MTKView *)view
{
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    view.sampleCount = 1;
    
    NSError *error;

    _AC0V0_KBuffer4LayerFormat = MTLPixelFormatRGBA16Float;
    _AC1V1_KBuffer4LayerFormat = MTLPixelFormatRGBA8Unorm; //PixelLocalStorage 大小不够，最后若干层的贡献最低，适当降低精度 //A7-A10 256位 //A11 512位
    _AC2V2_KBuffer4LayerFormat = MTLPixelFormatRGBA8Unorm;
    _AC3V3_KBuffer4LayerFormat = MTLPixelFormatRGBA8Unorm;
    _D0123_KBuffer4LayerFormat = MTLPixelFormatRGBA16Float;
    
    // Load all the shader files with a metal file extension in the project
    id <MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

    // Create and allocate uniform buffer objects.
    for(NSUInteger i = 0; i < AAPLMaxBuffersInFlight; i++)
    {
        // Indicate shared storage so that both the CPU and GPU can access the buffer
        const MTLResourceOptions storageMode = MTLResourceStorageModeShared;

        _frameUniformBuffers[i] = [_device newBufferWithLength:sizeof(AAPLFrameUniforms)
                                                       options:storageMode];

        _frameUniformBuffers[i].label = [NSString stringWithFormat:@"FrameUniformBuffer%lu", i];
    }
        
    //
    _MLABRenderPassDescriptor = [MTLRenderPassDescriptor new];
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentLighting].loadAction =  MTLLoadActionClear;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentLighting].storeAction = MTLStoreActionStore;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentLighting].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC0V0].loadAction = MTLLoadActionClear;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC0V0].storeAction = MTLStoreActionDontCare;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC0V0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC1V1].loadAction = MTLLoadActionClear;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC1V1].storeAction = MTLStoreActionDontCare;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC1V1].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC2V2].loadAction = MTLLoadActionClear;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC2V2].storeAction = MTLStoreActionDontCare;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC2V2].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC3V3].loadAction = MTLLoadActionClear;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC3V3].storeAction = MTLStoreActionDontCare;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC3V3].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentD0123].loadAction = MTLLoadActionClear;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentD0123].storeAction = MTLStoreActionDontCare;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentD0123].clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0);
    _MLABRenderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
    _MLABRenderPassDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
    _MLABRenderPassDescriptor.stencilAttachment.loadAction = MTLLoadActionClear;
    _MLABRenderPassDescriptor.stencilAttachment.storeAction = MTLStoreActionDontCare;
    _MLABRenderPassDescriptor.depthAttachment.clearDepth = 1.0;
    _MLABRenderPassDescriptor.stencilAttachment.clearStencil = 0;
    
    // Load the various fragment functions into the library
    id <MTLFunction> fullscreentriangleVertexFunction = [defaultLibrary newFunctionWithName:@"fullscreentriangle_vertex"];
    id <MTLFunction> OIT_4Layer_FragmentFunction = [defaultLibrary newFunctionWithName:@"OIT_4Layer_FragmentFunction"];
    id <MTLFunction> OITResolve_4Layer_FragmentFunction = [defaultLibrary newFunctionWithName:@"OITResolve_4Layer_fragment"];
    
    // Load the vertex function into the library
    id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexTransform"];
    
    // Create a vertex descriptor for our Metal pipeline. Specifies the layout of vertices the
    //   pipeline should expect.  The layout below keeps attributes used to calculate vertex shader
    //   output position separate (world position, skinning, tweening weights) separate from other
    //   attributes (texture coordinates, normals).  This generally maximizes pipeline efficiency

    _mtlVertexDescriptor = [[MTLVertexDescriptor alloc] init];

    // Positions.
    _mtlVertexDescriptor.attributes[AAPLVertexAttributePosition].format = MTLVertexFormatFloat3;
    _mtlVertexDescriptor.attributes[AAPLVertexAttributePosition].offset = 0;
    _mtlVertexDescriptor.attributes[AAPLVertexAttributePosition].bufferIndex = AAPLBufferIndexMeshPositions;

    // Texture coordinates.
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeTexcoord].format = MTLVertexFormatFloat2;
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeTexcoord].offset = 0;
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeTexcoord].bufferIndex = AAPLBufferIndexMeshGenerics;

    // Position Buffer Layout
    _mtlVertexDescriptor.layouts[AAPLBufferIndexMeshPositions].stride = 12;
    _mtlVertexDescriptor.layouts[AAPLBufferIndexMeshPositions].stepRate = 1;
    _mtlVertexDescriptor.layouts[AAPLBufferIndexMeshPositions].stepFunction = MTLVertexStepFunctionPerVertex;

    // Generic Attribute Buffer Layout
    _mtlVertexDescriptor.layouts[AAPLBufferIndexMeshGenerics].stride = 8;
    _mtlVertexDescriptor.layouts[AAPLBufferIndexMeshGenerics].stepRate = 1;
    _mtlVertexDescriptor.layouts[AAPLBufferIndexMeshGenerics].stepFunction = MTLVertexStepFunctionPerVertex;

    {
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [MTLRenderPipelineDescriptor new];
        
        pipelineStateDescriptor.label = @"KBuffer ReadModifyWrite";
        pipelineStateDescriptor.vertexDescriptor = _mtlVertexDescriptor;
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = OIT_4Layer_FragmentFunction;
        pipelineStateDescriptor.sampleCount = view.sampleCount;
        pipelineStateDescriptor.colorAttachments[MLABColorAttachmentLighting].pixelFormat = view.colorPixelFormat;
        pipelineStateDescriptor.colorAttachments[MLABColorAttachmentLighting].blendingEnabled = NO;
        pipelineStateDescriptor.colorAttachments[MLABColorAttachmentLighting].writeMask = MTLColorWriteMaskNone;
        pipelineStateDescriptor.colorAttachments[MLABColorAttachmentAC0V0].pixelFormat=_AC0V0_KBuffer4LayerFormat;
        pipelineStateDescriptor.colorAttachments[MLABColorAttachmentAC1V1].pixelFormat=_AC1V1_KBuffer4LayerFormat;
        pipelineStateDescriptor.colorAttachments[MLABColorAttachmentAC2V2].pixelFormat=_AC2V2_KBuffer4LayerFormat;
        pipelineStateDescriptor.colorAttachments[MLABColorAttachmentAC3V3].pixelFormat=_AC3V3_KBuffer4LayerFormat;
        pipelineStateDescriptor.colorAttachments[MLABColorAttachmentD0123].pixelFormat=_D0123_KBuffer4LayerFormat;
        pipelineStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
        pipelineStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;
        
        _kbuffer_RMW_PipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        if (!_kbuffer_RMW_PipelineState)
        {
            NSLog(@"Failed to create pipeline state, error %@", error);
        }
    }
    
    {
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [MTLRenderPipelineDescriptor new];
        
        pipelineStateDescriptor.label = @"OITResolve";
        pipelineStateDescriptor.vertexDescriptor = nil;
        pipelineStateDescriptor.vertexFunction = fullscreentriangleVertexFunction;
        pipelineStateDescriptor.fragmentFunction = OITResolve_4Layer_FragmentFunction;
        pipelineStateDescriptor.sampleCount = view.sampleCount;
        pipelineStateDescriptor.colorAttachments[MLABColorAttachmentLighting].pixelFormat = view.colorPixelFormat;
        pipelineStateDescriptor.colorAttachments[MLABColorAttachmentAC0V0].pixelFormat=_AC0V0_KBuffer4LayerFormat;
        pipelineStateDescriptor.colorAttachments[MLABColorAttachmentAC1V1].pixelFormat=_AC1V1_KBuffer4LayerFormat;
        pipelineStateDescriptor.colorAttachments[MLABColorAttachmentAC2V2].pixelFormat=_AC2V2_KBuffer4LayerFormat;
        pipelineStateDescriptor.colorAttachments[MLABColorAttachmentAC3V3].pixelFormat=_AC3V3_KBuffer4LayerFormat;
        pipelineStateDescriptor.colorAttachments[MLABColorAttachmentD0123].pixelFormat=_D0123_KBuffer4LayerFormat;
        pipelineStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
        pipelineStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;
        
        _resolvePipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        if (!_resolvePipelineState)
        {
            NSLog(@"Failed to create pipeline state, error %@", error);
        }
    }
    
    {
        MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
        depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
        depthStateDesc.depthWriteEnabled = NO;
        _depthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];
    }
    
    {
        MTLDepthStencilDescriptor *depthStateDesc = [MTLDepthStencilDescriptor new];
        depthStateDesc.label = @"CompositePass";
        depthStateDesc.depthCompareFunction = MTLCompareFunctionAlways;
        depthStateDesc.depthWriteEnabled = NO;
        _compositePassDepthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];
    }
    
    // Create the command queue
    _commandQueue = [_device newCommandQueue];

    _frameNum = 0;
}

/// Create and load our assets into Metal objects including meshes and textures
- (void)loadAssets
{
	NSError *error;

    // Creata a ModelIO vertexDescriptor so that we format/layout our ModelIO mesh vertices to
    //   fit our Metal render pipeline's vertex descriptor layout
    MDLVertexDescriptor *modelIOVertexDescriptor =
        MTKModelIOVertexDescriptorFromMetal(_mtlVertexDescriptor);

    // Indicate how each Metal vertex descriptor attribute maps to each ModelIO  attribute
    modelIOVertexDescriptor.attributes[AAPLVertexAttributePosition].name = MDLVertexAttributePosition;
    modelIOVertexDescriptor.attributes[AAPLVertexAttributeTexcoord].name  = MDLVertexAttributeTextureCoordinate;

    NSURL *modelFileURL = [[NSBundle mainBundle] URLForResource:@"Meshes/Temple.obj"
                                                  withExtension:nil];

    if(!modelFileURL)
    {
        NSLog(@"Could not find model (%@) file in bundle",
              modelFileURL.absoluteString);
    }

    _meshes = [AAPLMesh newMeshesFromUrl:modelFileURL
                 modelIOVertexDescriptor:modelIOVertexDescriptor
                             metalDevice:_device
                                   error:&error];

    if(!_meshes || error)
    {
        NSLog(@"Could not create meshes from model file %@: %@", modelFileURL.absoluteString,
              error.localizedDescription);
    }
}

/// Update the state of our "Game" for the current frame
- (void)updateGameState
{
    // Update any game state (including updating dynamically changing Metal buffer)
    _uniformBufferIndex = (_uniformBufferIndex + 1) % AAPLMaxBuffersInFlight;

    AAPLFrameUniforms *uniforms =
        (AAPLFrameUniforms *)_frameUniformBuffers[_uniformBufferIndex].contents;

    uniforms->projectionMatrix = _projectionMatrix;
    uniforms->viewMatrix = matrix4x4_translation(0.0, 0, 1000.0);
    vector_float3 rotationAxis = {0, 1, 0};
    matrix_float4x4 modelMatrix = matrix4x4_rotation(_rotation, rotationAxis);
    matrix_float4x4 translation = matrix4x4_translation(0.0, -200, 0);
    modelMatrix = matrix_multiply(modelMatrix, translation);

    uniforms->modelViewMatrix = matrix_multiply(uniforms->viewMatrix, modelMatrix);

    uniforms->screenWidth = _windowSize.width;

    _rotation += 0.01;
}

/// Called whenever view changes orientation or layout is changed
- (void) mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // When reshape is called, update the aspect ratio and projection matrix since the view
    //   orientation or size has changed
    _windowSize = size;
    
	float aspect = size.width / (float)size.height;
    _projectionMatrix = matrix_perspective_left_hand(65.0f * (M_PI / 180.0f), aspect, 1.0f, 5000.0);
    
    MTLTextureDescriptor *KBuffer4LayerTextureDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatInvalid width:size.width height:size.height mipmapped:NO];
    KBuffer4LayerTextureDesc.usage = MTLTextureUsageRenderTarget;
    KBuffer4LayerTextureDesc.storageMode = MTLStorageModeMemoryless;
    
    KBuffer4LayerTextureDesc.pixelFormat = _AC0V0_KBuffer4LayerFormat;
    _AC0V0_KBuffer4Layer = [_device newTextureWithDescriptor:KBuffer4LayerTextureDesc];
    
    KBuffer4LayerTextureDesc.pixelFormat = _AC1V1_KBuffer4LayerFormat;
    _AC1V1_KBuffer4Layer = [_device newTextureWithDescriptor:KBuffer4LayerTextureDesc];
    
    KBuffer4LayerTextureDesc.pixelFormat = _AC2V2_KBuffer4LayerFormat;
    _AC2V2_KBuffer4Layer = [_device newTextureWithDescriptor:KBuffer4LayerTextureDesc];
    
    KBuffer4LayerTextureDesc.pixelFormat = _AC3V3_KBuffer4LayerFormat;
    _AC3V3_KBuffer4Layer = [_device newTextureWithDescriptor:KBuffer4LayerTextureDesc];
    
    KBuffer4LayerTextureDesc.pixelFormat = _D0123_KBuffer4LayerFormat;
    _D0123_KBuffer4Layer = [_device newTextureWithDescriptor:KBuffer4LayerTextureDesc];
    
    _AC0V0_KBuffer4Layer.label = @"AC0V0";
    _AC1V1_KBuffer4Layer.label = @"AC1V1";
    _AC2V2_KBuffer4Layer.label = @"AC2V2";
    _AC3V3_KBuffer4Layer.label = @"AC3V3";
    _D0123_KBuffer4Layer.label = @"D0123";
    
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC0V0].texture = _AC0V0_KBuffer4Layer;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC1V1].texture = _AC1V1_KBuffer4Layer;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC2V2].texture = _AC2V2_KBuffer4Layer;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentAC3V3].texture = _AC3V3_KBuffer4Layer;
    _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentD0123].texture = _D0123_KBuffer4Layer;
}

// Called whenever the view needs to render
- (void) drawInMTKView:(nonnull MTKView *)view
{
    // Wait to ensure only AAPLMaxBuffersInFlight are getting proccessed by any stage in the Metal
    //   pipeline (App, Metal, Drivers, GPU, etc)
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    // Create a new command buffer for each renderpass to the current drawable
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    //commandBuffer.label = @"MyCommand";

    // Add completion hander which signal _inFlightSemaphore when Metal and the GPU has fully
    //   finished proccssing the commands we're encoding this frame.  This indicates when the
    //   dynamic buffers, that we're writing to this frame, will no longer be needed by Metal
    //   and the GPU.
    __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer)
    {
        dispatch_semaphore_signal(block_sema);
    }];

    [self updateGameState];

    id<MTLTexture> drawableTexture = view.currentDrawable.texture;
    
    // The pass can only render if a drawable is available, otherwise it needs to skip
    // rendering this frame.
    if(drawableTexture)
    {
      
        _MLABRenderPassDescriptor.colorAttachments[MLABColorAttachmentLighting].texture = drawableTexture;
        _MLABRenderPassDescriptor.depthAttachment.texture = view.depthStencilTexture;
        _MLABRenderPassDescriptor.stencilAttachment.texture = view.depthStencilTexture;
        
        // Create a render command encoder so we can render into something
        id <MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:_MLABRenderPassDescriptor];
        renderEncoder.label = @"Rendering";
        
        // Set render command encoder state
        [renderEncoder pushDebugGroup:@"Render Mesh"];
        
        [renderEncoder setCullMode:MTLCullModeBack];
        [renderEncoder setDepthStencilState:_depthState];
        [renderEncoder setRenderPipelineState:_kbuffer_RMW_PipelineState];
        
        // Set our per frame buffers
        [renderEncoder setVertexBuffer:_frameUniformBuffers[_uniformBufferIndex] offset:0 atIndex:AAPLBufferIndexFrameUniforms];
        
        for (__unsafe_unretained AAPLMesh *mesh in _meshes)
        {
            __unsafe_unretained MTKMesh *metalKitMesh = mesh.metalKitMesh;
            
            // Set mesh's vertex buffers
            for (NSUInteger bufferIndex = 0; bufferIndex < metalKitMesh.vertexBuffers.count; bufferIndex++)
            {
                __unsafe_unretained MTKMeshBuffer *vertexBuffer = metalKitMesh.vertexBuffers[bufferIndex];
                if((NSNull*)vertexBuffer != [NSNull null])
                {
                    [renderEncoder setVertexBuffer:vertexBuffer.buffer
                                            offset:vertexBuffer.offset
                                           atIndex:bufferIndex];
                }
            }
            
            // Draw each submesh of our mesh
            for(__unsafe_unretained AAPLSubmesh *submesh in mesh.submeshes)
            {
                // Set any textures read/sampled from our render pipeline
                [renderEncoder setFragmentTexture:submesh.textures[AAPLTextureIndexBaseColor] atIndex:AAPLTextureIndexBaseColor];
                
                MTKSubmesh *metalKitSubmesh = submesh.metalKitSubmmesh;
                
                [renderEncoder drawIndexedPrimitives:metalKitSubmesh.primitiveType
                                          indexCount:metalKitSubmesh.indexCount
                                           indexType:metalKitSubmesh.indexType
                                         indexBuffer:metalKitSubmesh.indexBuffer.buffer
                                   indexBufferOffset:metalKitSubmesh.indexBuffer.offset];
            }
        }
        
        [renderEncoder popDebugGroup];
        
        [renderEncoder pushDebugGroup:@"Composite Pass"];
        
        [renderEncoder setCullMode:MTLCullModeNone];
        [renderEncoder setRenderPipelineState:_resolvePipelineState];
        [renderEncoder setDepthStencilState:_compositePassDepthState];
        //[renderEncoder setVertexBuffer
        
        // Draw full screen triangle
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        
        [renderEncoder popDebugGroup];
    
        // We're done encoding commands
        [renderEncoder endEncoding];
    }

    // Schedule a present once the framebuffer is complete using the current drawable
    [commandBuffer presentDrawable:view.currentDrawable];

    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];

    _frameNum++;
}

@end




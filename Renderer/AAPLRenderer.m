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
    
    // We have a fragment shader per rendering method
    id <MTLRenderPipelineState> _pipelineStates[AAPLNumTransparencyMethods];
    id <MTLDepthStencilState> _depthState;
    
    // Tile shader used to prepare the imageblock memory
    id <MTLRenderPipelineState> _clearTileStates[AAPLNumTransparencyMethods];
    
    // Tile shader used to resolve the imageblock OIT data into the final framebuffer
    id <MTLRenderPipelineState> _resolveStates[AAPLNumTransparencyMethods];

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

    // Buffer that holds OIT data if device memory is being used
    id <MTLBuffer> _oitBufferData;

}

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view
{
    self = [super init];
    if(self)
    {
        _device = view.device;

        if(![_device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily4_v1])
        {
            // This sample requires features avaliable with the iOS_GPUFamily4_v1 feature set
            //   (which is avaliable on devices with A11 GPUs or later).  If the iOS_GPUFamily4_v1
            //   feature set is is unavliable, the app would need to implement a backup path that
            //   does not use many of the APIs demonstated in this sample.  However, the
            //   implementation of such a backup path is beyond the scope of this sample.
            assert(!"Sample requires GPUFamily4_v1 (introduced with A11)");
            return nil;
        }

        _inFlightSemaphore = dispatch_semaphore_create(AAPLMaxBuffersInFlight);

        [self loadMetalWithMetalKitView:view];
        [self loadAssets];
    }

    return self;
}

/// Create and load our basic Metal state objects
- (void)loadMetalWithMetalKitView:(nonnull MTKView *)view
{
    NSError *error;

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
    
    // Function constants for the functions
    MTLFunctionConstantValues *constantValues = [MTLFunctionConstantValues new];
    
    // Load the various fragment functions into the library
    id <MTLFunction> transparencyMethodFragmentFunctions[AAPLNumTransparencyMethods] = {
        [defaultLibrary newFunctionWithName:@"OITFragmentFunction_4Layer" constantValues:constantValues error:nil],
        [defaultLibrary newFunctionWithName:@"OITFragmentFunction_2Layer" constantValues:constantValues error:nil],
        [defaultLibrary newFunctionWithName:@"unorderedFragmentShader" constantValues:constantValues error:nil],
    };

    // Load the vertex function into the library
    id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexTransform"];
    
    id <MTLFunction> resolveFunctions[AAPLNumTransparencyMethods] = {
        [defaultLibrary newFunctionWithName:@"OITResolve_4Layer" constantValues:constantValues error:nil],
        [defaultLibrary newFunctionWithName:@"OITResolve_2Layer" constantValues:constantValues error:nil],
         nil
    };
    
    id <MTLFunction> clearFunctions[AAPLNumTransparencyMethods] = {
        [defaultLibrary newFunctionWithName:@"OITClear_4Layer" constantValues:constantValues error:nil],
        [defaultLibrary newFunctionWithName:@"OITClear_2Layer" constantValues:constantValues error:nil],
        nil
    };

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

    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    view.sampleCount = 1;
    
    // Create a reusable pipeline state
    MTLRenderPipelineDescriptor *pipelineStateDescriptor =
        [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.vertexDescriptor = _mtlVertexDescriptor;
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.sampleCount = view.sampleCount;
    pipelineStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
    pipelineStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;

    // Create the various pipeline states
    for (int i = 0; i < AAPLNumTransparencyMethods; ++i)
    {
        pipelineStateDescriptor.label = [[NSString alloc] initWithUTF8String:s_transparencyMethodNames[i]];

        if(AAPLMethodUnorderedBlending == i)
        {
            // Alpha blending should only be enable for our unordered alpha blending method
            pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;
            pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
            pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            pipelineStateDescriptor.colorAttachments[0].writeMask = MTLColorWriteMaskAll;
        }
        else
        {
            // We will not actually write colors with our render pass when using or OIT methods
            //    Instead, our tile shaders will accomplish these writes
            pipelineStateDescriptor.colorAttachments[0].blendingEnabled = NO;
            pipelineStateDescriptor.colorAttachments[0].writeMask = MTLColorWriteMaskNone;
        }

        pipelineStateDescriptor.fragmentFunction = transparencyMethodFragmentFunctions[i];

        _pipelineStates[i] = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        if (!_pipelineStates[i])
        {
            NSLog(@"Failed to create pipeline state, error %@", error);
        }
    }

    // Create the various tile states for setting up and resolving imageblock memory
    // because of the usage of tile render pipeline descriptors
    for (NSUInteger i = 0; i < AAPLNumTransparencyMethods; ++i)
    {

        if(AAPLMethodUnorderedBlending == i)
        {
            // Tile shading only used for ordering
            continue;
        }

        MTLTileRenderPipelineDescriptor *tileDesc = [MTLTileRenderPipelineDescriptor new];
        tileDesc.label = [[NSString alloc] initWithFormat:@"%lu Layer OIT Resolve", i];
        tileDesc.tileFunction = resolveFunctions[i];
        tileDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat;
        tileDesc.threadgroupSizeMatchesTileSize = YES;

        _resolveStates[i] = [_device newRenderPipelineStateWithTileDescriptor:tileDesc
                                                                      options:0
                                                                   reflection:nil
                                                                        error:&error];
        if (!_resolveStates[i])
        {
            NSLog(@"Failed to create tile pipeline state, error %@", error);
        }

        tileDesc.label = [[NSString alloc] initWithFormat:@"%lu Layer OIT Clear", i];
        tileDesc.tileFunction = clearFunctions[i];
        _clearTileStates[i] = [_device newRenderPipelineStateWithTileDescriptor:tileDesc
                                                                        options:0
                                                                     reflection:nil
                                                                          error:&error];
        if (!_clearTileStates[i])
        {
            NSLog(@"Failed to create tile pipeline state, error %@", error);
        }
    }

    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled = NO;
    _depthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];

    // Create the command queue
    _commandQueue = [_device newCommandQueue];
    
    // Set alpha blending as our starting rendering method
    _transparencyMethod = AAPLMethod4LayerOrderIndependent;

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
}

- (bool)isOITRenderingMethod
{
    return _transparencyMethod != AAPLMethodUnorderedBlending;
}

- (MTLSize)optimalTileSize
{
    switch (_transparencyMethod)
    {
        case AAPLMethod2LayerOrderIndependent: return MTLSizeMake(32, 32, 1);
        case AAPLMethod4LayerOrderIndependent: return MTLSizeMake(32, 16, 1);
        default:
        NSLog(@"Invalid tile size for rendering method: %d", _transparencyMethod);
        return MTLSizeMake(32, 32, 1);
    }
}

// Called whenever the view needs to render
- (void) drawInMTKView:(nonnull MTKView *)view
{
    assert((int)_transparencyMethod < AAPLNumTransparencyMethods);
    
    // Wait to ensure only AAPLMaxBuffersInFlight are getting proccessed by any stage in the Metal
    //   pipeline (App, Metal, Drivers, GPU, etc)
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    // Create a new command buffer for each renderpass to the current drawable
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";

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

    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;

    // If we've gotten a renderPassDescriptor we can render to the drawable, otherwise we'll skip
    //   any rendering this frame because we have no drawable to draw to
    if(renderPassDescriptor != nil) {
        
        MTLSize tileSize = {};

        if (self.isOITRenderingMethod)
        {
            tileSize = self.optimalTileSize;
            
            renderPassDescriptor.tileWidth = tileSize.width;
            renderPassDescriptor.tileHeight = tileSize.height;
            
            // Get the imageblock sample length from the compiled pipeline state
            renderPassDescriptor.imageblockSampleLength =
                _resolveStates[_transparencyMethod].imageblockSampleLength;
        }

        // Create a render command encoder so we can render into something
        id <MTLRenderCommandEncoder> renderEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"Rendering";

        if(self.isOITRenderingMethod)
        {
            // If we're not using device memory, we need to clear the threadgroup data
            [renderEncoder pushDebugGroup:@"Clear Imageblock Memory"];
            [renderEncoder setRenderPipelineState:_clearTileStates[_transparencyMethod]];
            [renderEncoder dispatchThreadsPerTile:tileSize];
            [renderEncoder popDebugGroup];
        }

        // Set render command encoder state
        [renderEncoder pushDebugGroup:@"Render Mesh"];
        
		[renderEncoder setCullMode:MTLCullModeBack];
        [renderEncoder setDepthStencilState:_depthState];
        [renderEncoder setRenderPipelineState:_pipelineStates[_transparencyMethod]];

        // Set our per frame buffers
        [renderEncoder setVertexBuffer:_frameUniformBuffers[_uniformBufferIndex]
                                offset:0
                               atIndex:AAPLBufferIndexFrameUniforms];

        [renderEncoder setFragmentBuffer:_frameUniformBuffers[_uniformBufferIndex]
                                  offset:0
                                 atIndex:AAPLBufferIndexFrameUniforms];

        [renderEncoder setFragmentBuffer:_oitBufferData
                                  offset:0
                                 atIndex:AAPLBufferIndexOITData];


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
                [renderEncoder setFragmentTexture:submesh.textures[AAPLTextureIndexBaseColor]
                                          atIndex:AAPLTextureIndexBaseColor];

                MTKSubmesh *metalKitSubmesh = submesh.metalKitSubmmesh;

                [renderEncoder drawIndexedPrimitives:metalKitSubmesh.primitiveType
                                          indexCount:metalKitSubmesh.indexCount
                                           indexType:metalKitSubmesh.indexType
                                         indexBuffer:metalKitSubmesh.indexBuffer.buffer
                                   indexBufferOffset:metalKitSubmesh.indexBuffer.offset];
            }
        }

        [renderEncoder popDebugGroup];

        if(self.isOITRenderingMethod)
        {
            // Resolve the OIT data from the threadgroup data
            [renderEncoder pushDebugGroup:@"ResolveTranparency"];
            [renderEncoder setRenderPipelineState:_resolveStates[_transparencyMethod]];
            [renderEncoder dispatchThreadsPerTile:tileSize];
            [renderEncoder popDebugGroup];
        }
        
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




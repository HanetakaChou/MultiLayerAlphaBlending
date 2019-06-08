/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal shaders used for rendering
*/

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "AAPLShaderTypes.h"
#import "AAPLShaderCommon.h"

// Per-vertex inputs fed by vertex buffer laid out with MTLVertexDescriptor in Metal API
typedef struct
{
    float3 position [[attribute(AAPLVertexAttributePosition)]];
    float2 texCoord [[attribute(AAPLVertexAttributeTexcoord)]];
} Vertex;

// Vertex function
vertex ColorInOut vertexTransform(Vertex in [[stage_in]],
                                  constant AAPLFrameUniforms & frameUniforms [[ buffer(AAPLBufferIndexFrameUniforms) ]])
{
    ColorInOut out;

    // Make position a float4 to perform 4x4 matrix math on it
    float4 position = float4(in.position, 1.0);

    // Calculate the position of our vertex in clip space and output for clipping
    //   and rasterization
    out.position = frameUniforms.projectionMatrix * frameUniforms.modelViewMatrix * position;

    // Pass the normal as a texture coordinate since we'll sample from a cubemap
    out.texCoord = in.texCoord;

    return out;
}

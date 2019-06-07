/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header containing types and enum constants shared between Metal shaders and C/ObjC source
*/
#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum AAPLBufferIndices
{
    AAPLBufferIndexMeshPositions = 0,
    AAPLBufferIndexMeshGenerics  = 1,
    AAPLBufferIndexFrameUniforms = 2,
    AAPLBufferIndexActorUniforms = 3,
    AAPLBufferIndexOITData       = 4
} AAPLBufferIndices;

// Attribute index values shared between shader and C code to ensure Metal shader vertex
//   attribute indices match the Metal API vertex descriptor attribute indices
typedef enum AAPLVertexAttributes
{
    AAPLVertexAttributePosition  = 0,
    AAPLVertexAttributeTexcoord  = 1,
} AAPLVertexAttributes;

// Texture index values shared between shader and C code to ensure Metal shader texture indices
//   match indices of Metal API texture set calls
typedef enum AAPLTextureIndices
{
	AAPLTextureIndexBaseColor = 0,
	AAPLNumTextureIndices
} AAPLTextureIndices;

// Structures shared between shader and C code to ensure the layout of uniform data accessed in
//    Metal shaders matches the layout of uniform data set in C code

// Per frame uniforms
typedef struct
{
    matrix_float4x4 modelViewMatrix;
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    uint screenWidth;
} AAPLFrameUniforms;

#endif /* ShaderTypes_h */


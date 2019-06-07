/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Code shared between .metal source files
*/

#ifndef AAPLShaderCommon_h
#define AAPLShaderCommon_h

#include "AAPLShaderTypes.h"

// Vertex shader outputs and per-fragmeht inputs.  Includes clip-space position and vertex outputs
//  interpolated by rasterizer and fed to each fragment genterated by clip-space primitives.
typedef struct
{
    float4 position [[position]];
    float2 texCoord;
} ColorInOut;

#endif /* AAPLShaderCommon_h */

/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Kernels to perform Order Independent Transparency
*/

#include <metal_stdlib>
using namespace metal;

#import "AAPLShaderCommon.h"

constant uint useDeviceMemory [[function_constant(0)]];

typedef rgba8unorm<half4> rgba8storage;
typedef r8unorm<half> r8storage;

template <int NUM_LAYERS>
struct OITData
{
    static constexpr constant short s_numLayers = NUM_LAYERS;
    
    rgba8storage colors         [[raster_order_group(0)]] [NUM_LAYERS];
    half         depths         [[raster_order_group(0)]] [NUM_LAYERS];
    r8storage    transmittances [[raster_order_group(0)]] [NUM_LAYERS];
};

// The imageblock structure
template <int NUM_LAYERS>
struct OITImageblock
{
    OITData<NUM_LAYERS> oitData;
};

template <int NUM_LAYERS>
struct FragOut
{
    OITImageblock<NUM_LAYERS> aoitImageBlock [[imageblock_data]];
};

// OITFragmentFunction, InsertFragment, Resolve, and Clear are templatized on OITDataT   in order
//   to control the number of layers

template <typename OITDataT>
inline void InsertFragment(OITDataT oitData, half4 color, half depth, half transmittance)
{
    const short numLayers = oitData->s_numLayers;

    for (short i = 0; i < numLayers - 1; ++i)
    {
        half layerDepth = oitData->depths[i];
        half4 layerColor = oitData->colors[i];
        half layerTransmittance = oitData->transmittances[i];

        bool insert = (depth <= layerDepth);
        oitData->colors[i] = insert ? color : layerColor;
        oitData->depths[i] = insert ? depth : layerDepth;
        oitData->transmittances[i] = insert ? transmittance : layerTransmittance;

        color = insert ? layerColor : color;
        depth = insert ? layerDepth : depth;
        transmittance = insert ? layerTransmittance : transmittance;
    }

    const short lastLayer = numLayers - 1;
    half lastDepth = oitData->depths[lastLayer];
    half4 lastColor = oitData->colors[lastLayer];
    half lastTransmittance = oitData->transmittances[lastLayer];

    bool newDepthFirst = (depth <= lastDepth);

    half firstDepth = newDepthFirst ? depth : lastDepth;
    half4 firstColor = newDepthFirst ? color : lastColor;
    half4 secondColor = newDepthFirst ? lastColor : color;
    half firstTransmittance = newDepthFirst ? transmittance : lastTransmittance;

    oitData->colors[lastLayer] = firstColor + secondColor * firstTransmittance;
    oitData->depths[lastLayer] = firstDepth;
    oitData->transmittances[lastLayer] = transmittance * lastTransmittance;
}

template <typename OITDataT>
void OITFragmentFunction(ColorInOut                   in,
                         constant AAPLFrameUniforms & uniforms,
                         texture2d<half>              baseColorMap,
                         OITDataT                     oitData)
{
    const float depth = in.position.z / in.position.w;
    
    constexpr sampler linearSampler(mip_filter::linear,
                                    mag_filter::linear,
                                    min_filter::linear);
    
    half4 fragmentColor = baseColorMap.sample(linearSampler, in.texCoord);

    fragmentColor.a = 0.5;

    fragmentColor.rgb *= (1 - fragmentColor.a);
    InsertFragment(oitData, fragmentColor, depth, 1 - fragmentColor.a);
}

template <int NUM_LAYERS>
void OITClear(imageblock<OITImageblock<NUM_LAYERS>, imageblock_layout_explicit> oitData,
              ushort2 tid)
{
    threadgroup_imageblock OITData<NUM_LAYERS> &pixelData = oitData.data(tid)->oitData;
    const short numLayers = pixelData.s_numLayers;

    for (ushort i = 0; i < numLayers; ++i)
    {
        pixelData.colors[i] = half4(0.0);
        pixelData.depths[i] = 65504.0;
        pixelData.transmittances[i] = 1.0;
    }
}

template <int NUM_LAYERS>
half4 OITResolve(OITData<NUM_LAYERS> pixelData)
{
    const short numLayers = pixelData.s_numLayers;

    // Composite!
    half4 finalColor = 0;
    half transmittance = 1;
    for (ushort i = 0; i < numLayers; ++i)
    {
        finalColor += (half4)pixelData.colors[i] * transmittance;
        transmittance *= (half)pixelData.transmittances[i];
    }

    finalColor.w = 1;
    return finalColor;
}

fragment FragOut<2>
OITFragmentFunction_2Layer(ColorInOut                   in            [[ stage_in ]],
                           constant AAPLFrameUniforms & uniforms      [[ buffer (AAPLBufferIndexFrameUniforms) ]],
                           texture2d<half>              baseColorMap  [[ texture(AAPLTextureIndexBaseColor) ]],
                           OITImageblock<2>             oitImageblock [[ imageblock_data ]])
{
    OITFragmentFunction(in, uniforms, baseColorMap, &oitImageblock.oitData);
    FragOut<2> Out;
    Out.aoitImageBlock = oitImageblock;
    return Out;
}

fragment FragOut<4>
OITFragmentFunction_4Layer(ColorInOut                   in            [[ stage_in ]],
                           constant AAPLFrameUniforms & uniforms      [[ buffer (AAPLBufferIndexFrameUniforms) ]],
                           texture2d<half>              baseColorMap  [[ texture(AAPLTextureIndexBaseColor) ]],
                           OITImageblock<4>             oitImageblock [[ imageblock_data ]])
{
    OITFragmentFunction(in, uniforms, baseColorMap, &oitImageblock.oitData);
    FragOut<4> Out;
    Out.aoitImageBlock = oitImageblock;
    return Out;
}

kernel void OITClear_2Layer(imageblock<OITImageblock<2>, imageblock_layout_explicit> oitData,
                            ushort2 tid [[thread_position_in_threadgroup]])
{
    OITClear(oitData, tid);
}

kernel void OITClear_4Layer(imageblock<OITImageblock<4>, imageblock_layout_explicit> oitData,
                            ushort2 tid [[thread_position_in_threadgroup]])
{
    OITClear(oitData, tid);
}

fragment half4 OITResolve_2Layer(OITImageblock<2> oitImageblock [[imageblock_data]])
{
    return OITResolve(oitImageblock.oitData);
}

fragment half4 OITResolve_4Layer(OITImageblock<4> oitImageblock [[imageblock_data]])
{
    return OITResolve(oitImageblock.oitData);
}


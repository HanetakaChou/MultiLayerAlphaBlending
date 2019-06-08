/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Kernels to perform Order Independent Transparency
*/

#include <metal_stdlib>
using namespace metal;

#import "AAPLShaderCommon.h"

typedef struct
{
    float4 position [[position]];
} TriangleInOut;

vertex TriangleInOut fullscreentriangle_vertex(uint vid[[vertex_id]])
{
    TriangleInOut out;

    switch(vid)
    {
        case 0:
            out.position = float4(-1, -3, 0, 1);
            break;
        case 1:
            out.position = float4(-1, 1, 0, 1);
            break;
        case 2:
            out.position = float4(3, 1, 0, 1);
            break;
    }
    
    return out;
}

typedef struct
{
    half4 AC0V0[[color(MLABColorAttachmentAC0V0)]];
    half4 AC1V1[[color(MLABColorAttachmentAC1V1)]];
    half4 AC2V2[[color(MLABColorAttachmentAC2V2)]];
    half4 AC3V3[[color(MLABColorAttachmentAC3V3)]];
    half4 D0123[[color(MLABColorAttachmentD0123)]];
} KBuffer_4Layer;

struct OITData_4Layer
{
    half4 ACV[4];
    half D[4];
};

fragment KBuffer_4Layer OIT_4Layer_FragmentFunction(ColorInOut in[[stage_in]],
                                           texture2d<half> baseColorMap[[texture(AAPLTextureIndexBaseColor)]],
                                           KBuffer_4Layer kbuffer)
{
    const float depth = in.position.z; /// in.position.w;
    
    constexpr sampler linearSampler(mip_filter::linear,
                                    mag_filter::linear,
                                    min_filter::linear);
    
    half4 baseColorSample = baseColorMap.sample(linearSampler, in.texCoord);
    // Reduce alpha a little so transparency is easier to see
    baseColorSample.a *= 0.6f;
    
    half4 newACV = half4(baseColorSample.a*baseColorSample.rgb, 1 - baseColorSample.a);
    half newD = depth;
    
    //Read KBuffer
    OITData_4Layer oitData;
    oitData.ACV[0] = kbuffer.AC0V0;
    oitData.ACV[1] = kbuffer.AC1V1;
    oitData.ACV[2] = kbuffer.AC2V2;
    oitData.ACV[3] = kbuffer.AC3V3;
    oitData.D[0] = kbuffer.D0123.r;
    oitData.D[1] = kbuffer.D0123.g;
    oitData.D[2] = kbuffer.D0123.b;
    oitData.D[3] = kbuffer.D0123.a;
    
    //Modify KBuffer
    const short numLayers = 4;
    const short lastLayer = numLayers - 1;

    //Insert
    for (short i = 0; i < numLayers; ++i)
    {
        half4 layerACV = oitData.ACV[i];
        half layerD = oitData.D[i];

        bool insert = (newD <= layerD);
        //Insert
        oitData.ACV[i] = insert ? newACV : layerACV;
        oitData.D[i] = insert ? newD : layerD;
        //Pop Current Layer And Insert It Later
        newACV = insert ? layerACV : newACV;
        newD = insert ? layerD : newD;
    }
    
    //Merge
    half4 lastACV = oitData.ACV[lastLayer];
    half lastD = oitData.D[lastLayer];
    
    bool newDepthFirst = (newD <= lastD); //此时newD指向原KBuffer中的最后一个Layer（目前已被Pop）
    
    half4 firstACV = newDepthFirst ? newACV : lastACV;
    half firstD = newDepthFirst ? newD : lastD;
    half4 secondACV = newDepthFirst ? lastACV : newACV;
    
    oitData.ACV[lastLayer] = half4(firstACV.rgb + secondACV.rgb * firstACV.a, firstACV.a*secondACV.a);
    oitData.D[lastLayer] = firstD;
    
    //Write KBuffer
    KBuffer_4Layer output;
    output.AC0V0 = oitData.ACV[0];
    output.AC1V1 = oitData.ACV[1];
    output.AC2V2 = oitData.ACV[2];
    output.AC3V3 = oitData.ACV[3];
    output.D0123 = half4(oitData.D[0], oitData.D[1], oitData.D[2], oitData.D[3]);
    return output;
}

struct AccumLightBuffer
{
    half4 lighting[[color(MLABColorAttachmentLighting)]];
};

typedef struct
{
    half4 AC0V0[[color(MLABColorAttachmentAC0V0)]];
    half4 AC1V1[[color(MLABColorAttachmentAC1V1)]];
    half4 AC2V2[[color(MLABColorAttachmentAC2V2)]];
    half4 AC3V3[[color(MLABColorAttachmentAC3V3)]];
} KBuffer_4Layer_NoDepth;

struct OITData_4Layer_NoDepth
{
    half4 ACV[4];
};

fragment AccumLightBuffer OITResolve_4Layer_fragment(KBuffer_4Layer_NoDepth kbuffer)
{
    OITData_4Layer_NoDepth oitData;
    oitData.ACV[0] = kbuffer.AC0V0;
    oitData.ACV[1] = kbuffer.AC1V1;
    oitData.ACV[2] = kbuffer.AC2V2;
    oitData.ACV[3] = kbuffer.AC3V3;
    
    //Under Operation
    const short numLayers = 4;
    half3 CFinal = half3(0.0f,0.0f,0.0f);
    half AlphaTotal = 1.0f;
    for (ushort i = 0; i < numLayers; ++i)
    {
        CFinal += oitData.ACV[i].rgb * AlphaTotal;
        AlphaTotal *= oitData.ACV[i].a;
    }
    
    AccumLightBuffer output;
    output.lighting = half4(CFinal, AlphaTotal);
    return output;
}

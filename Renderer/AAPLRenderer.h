/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header for renderer class which perfoms Metal setup and per frame rendering
*/

@import MetalKit;

enum AAPLTransparencyMethod
{
    AAPLMethod4LayerOrderIndependent,
    AAPLMethod2LayerOrderIndependent,
    AAPLMethodUnorderedBlending,
    AAPLNumTransparencyMethods
};

static const char* __nonnull  s_transparencyMethodNames[] = {
    "4 Layer Order Independant Transparency",
    "2 Layer Order Independant Transparency",
    "Unordered Alpha Blending",
};


@interface AAPLRenderer : NSObject <MTKViewDelegate>

@property (nonatomic) enum AAPLTransparencyMethod transparencyMethod;

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;

@end



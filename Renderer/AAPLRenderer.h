/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header for renderer class which perfoms Metal setup and per frame rendering
*/

@import MetalKit;

@interface AAPLRenderer : NSObject <MTKViewDelegate>

//KBuffer Property
@property (nonatomic, readonly) MTLPixelFormat AC0V0_KBuffer4LayerFormat;
@property (nonatomic, readonly) MTLPixelFormat AC1V1_KBuffer4LayerFormat;
@property (nonatomic, readonly) MTLPixelFormat AC2V2_KBuffer4LayerFormat;
@property (nonatomic, readonly) MTLPixelFormat AC3V3_KBuffer4LayerFormat;
@property (nonatomic, readonly) MTLPixelFormat D0123_KBuffer4LayerFormat;
@property (nonatomic, readonly, nonnull) id <MTLTexture> AC0V0_KBuffer4Layer;
@property (nonatomic, readonly, nonnull) id <MTLTexture> AC1V1_KBuffer4Layer;
@property (nonatomic, readonly, nonnull) id <MTLTexture> AC2V2_KBuffer4Layer;
@property (nonatomic, readonly, nonnull) id <MTLTexture> AC3V3_KBuffer4Layer;
@property (nonatomic, readonly, nonnull) id <MTLTexture> D0123_KBuffer4Layer;


-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;

@end



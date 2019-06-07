/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of our iOS view controller
*/

#import "AAPLViewController.h"
#import "AAPLRenderer.h"

@implementation AAPLViewController
{
    MTKView *_view;

    AAPLRenderer *_renderer;
    UITapGestureRecognizer *_tapRecognizer;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Set the view to use the default device
    _view = (MTKView *)self.view;
    _view.device = MTLCreateSystemDefaultDevice();

    if(!_view.device)
    {
        NSLog(@"Metal is not supported on this device");
        self.view = [[UIView alloc] initWithFrame:self.view.frame];
    }

    _renderer = [[AAPLRenderer alloc] initWithMetalKitView:_view];

    if(!_renderer)
    {
        NSLog(@"Renderer failed initialization");
        return;
    }

    [_renderer mtkView:_view drawableSizeWillChange:_view.drawableSize];

    _view.delegate = _renderer;

    // Set up the tap gesture recognizer
    _tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self.view addGestureRecognizer:_tapRecognizer];

    [self updateTransparencyMethodText];
}

- (void)updateTransparencyMethodText
{    
    self.mainLabel.text = [NSString stringWithFormat:@"%s", s_transparencyMethodNames[_renderer.transparencyMethod]];
}

- (void)handleTap:(UITapGestureRecognizer *)tap
{
    _renderer.transparencyMethod = ((_renderer.transparencyMethod + 1) % AAPLNumTransparencyMethods);
    [self updateTransparencyMethodText];
}

@end


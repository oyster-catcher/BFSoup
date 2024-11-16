//
//  ViewController.m
//  PeaSoup
//
//  Created by Adrian Skilling on 18/04/2024.
//

#import "ViewController.h"

#import <MetalKit/MetalKit.h>
#import <CoreImage/CoreImage.h>
#import "Renderer.h"

// IMGUI
//#include "imgui.h"
//#include "imgui_impl_metal.h"
//#include "imgui_impl_osx.h"

@implementation ViewController
{
   MTKView *_view;
   Renderer *_renderer;
}

- (void)viewDidLoad {
   [super viewDidLoad];

   _view = (MTKView*)self.view;
   _view.device = MTLCreateSystemDefaultDevice();
   _view.preferredFramesPerSecond = 30; //was 30
   _renderer = [[Renderer alloc] initWithMetalKitView:_view size:_view.bounds.size];
   NSAssert(_renderer, @"Renderer failed initialization");
   _view.delegate = _renderer;
   NSAssert(_view.device, @"Metal is not supported on this device");
   NSLog(@"viewDidLoad...");
}

- (void)loadView {
   [super loadView];
}

- (void)awakeFromNib {
}

- (void)viewDidDisappear {
}

- (void)setRepresentedObject:(id)representedObject {
   [super setRepresentedObject:representedObject];
}

- (void)scrollWheel:(NSEvent *)event {
   NSPoint cursorPoint = [ event locationInWindow ];
   [_renderer swipe:event.deltaY x:cursorPoint.x y:cursorPoint.y];
}

@end

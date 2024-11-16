 //
//  Renderer.m
//  PeaSoup
//
//  Created by Adrian Skilling on 18/04/2024.
//

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>

#import "Renderer.h"
#import "World.h"
#import "ShaderDefinitions.h"
#import "Analysis.h"

#include "imgui.h"
#include "imgui_impl_metal.h"
#include "imgui_impl_osx.h"

@implementation Renderer
{
   MTKView* _view;
   id<MTLDevice> _device;
   id<MTLLibrary> _library;
   id<MTLCommandQueue> _commandQueue;
   id<MTLRenderPipelineState> _renderPipelineState;
   id<MTLBuffer> _worldParamsBuffer;
   struct WorldParams * _worldParams;
   World *_world;
   ImVec2 _cent;      // cent location of window in world pos
   ImVec2 _offset;
   ImVec2 _dragStart; // world pos of mouse where drag started
   float _magnification;
   float _initMagnification;
   int _simulationSpeed;
   NSTextField* _infoText;
   int _epoch;
   bool _analysisOpen;
   char _autoSavePath[256];
   int _autoSaveInterval;
}

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view size:(CGSize)size
{
   self = [super init];
   if(self)
   {
      _view = (MTKView*)view;
      _device = MTLCreateSystemDefaultDevice();
      _library = [_device newDefaultLibrary];
      _renderPipelineState = nil;
      _commandQueue = [_device newCommandQueue];
      _magnification = 1680 * 1.25;
      _initMagnification = _magnification;
            
      _worldParamsBuffer = [_device newBufferWithLength:sizeof(struct WorldParams) options:MTLResourceStorageModeShared];
      _worldParams = (struct WorldParams*)_worldParamsBuffer.contents;
      
      _world = [[World alloc]initWithDevice:_device library:_library worldParamsBuffer:_worldParamsBuffer];
      _simulationSpeed = 1;
      _epoch = 0;
      _analysisOpen = true;
      _infoText = [NSTextField labelWithString:@"Info:"];
      [_infoText setTextColor:NSColor.darkGrayColor];
      [_infoText setBackgroundColor:NSColor.whiteColor];
      [_infoText setDrawsBackground:YES];
      [_infoText setFrameOrigin:NSMakePoint(0,0)];
      [_infoText setFrameSize:NSMakeSize(200,_infoText.frame.size.height)];
      [view addSubview:_infoText];

      // Setup IMGUI
      // Setup Dear ImGui context
      // FIXME: This example doesn't have proper cleanup...
      IMGUI_CHECKVERSION();
      ImGui::CreateContext();
      ImGuiIO& io = ImGui::GetIO(); (void)io;
      io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
      io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls

      // Setup Dear ImGui style
      ImGui::StyleColorsDark();
      
      // Setup Renderer backend
      ImGui_ImplMetal_Init(_device);
      ImGui_ImplOSX_Init(view);
      
      strcpy(_autoSavePath, "");
      _autoSaveInterval = 1000;
   }
   return self;
}

- (void)swipe:(float)deltaY x:(float)x y:(float)y {
   // calculate change in world position at the position of the pointer
   float wx1 = (4*x - _view.drawableSize.width)/_magnification;
   float wy1 = (4*y - _view.drawableSize.height)/_magnification;
   float newMag = _magnification * (1 - deltaY*0.01);
   float wx2 = (4*x - _view.drawableSize.width)/newMag;
   float wy2 = (4*y - _view.drawableSize.height)/newMag;

   // (x,y) is from (-1,-1) to (+1,+1) normalized device co-ords
   _cent.x += wx1 - wx2;
   _cent.y += wy1 - wy2;
   _magnification *= (1 - deltaY*0.01);
   //_magnification = fmax(1920, _magnification);
}

- (ImVec2)screenPosToWorldPos:(ImVec2)screenPos {
   float x = screenPos.x - _view.frame.origin.x - _view.frame.size.width/2;
   float y = _view.frame.origin.y + _view.frame.size.height/2 - screenPos.y;
   return ImVec2(_cent.x + (4*x/_magnification),_cent.y + (4*y/_magnification));
}

- (ImVec2)worldPosToScreenPos:(ImVec2)worldPos {
   float wx = worldPos.x;
   float wy = worldPos.y;
   float px = _magnification * (wx - _cent.x) * 0.25;
   float py = _magnification * (wy - _cent.y) * 0.25;
   float sx = px + _view.frame.origin.x + _view.frame.size.width/2;
   float sy = _view.frame.origin.y + _view.frame.size.height/2 - py;
   return ImVec2(sx,sy);
}

- (ImVec2)screenOffsetToWorldOffset:(ImVec2)worldOffset {
   return ImVec2(4 * worldOffset.x/_magnification, 4 * worldOffset.y / _magnification);
}

- (id<MTLRenderPipelineState>)makeRenderPipelineStateWithView:(nonnull MTKView *)view
                                               vertexShader:(NSString*)vertexShader
                                             fragmentShader:(NSString*)fragmentShader {
   MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
   id <MTLFunction> vertexFunc = [_library newFunctionWithName:vertexShader];
   pipelineDescriptor.vertexFunction = vertexFunc;
   id <MTLFunction> fragmentFunc = [_library newFunctionWithName:fragmentShader];
   pipelineDescriptor.fragmentFunction = fragmentFunc;
   pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
   pipelineDescriptor.colorAttachments[0].blendingEnabled = true;
   pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
   pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
   pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
   pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
   pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
   pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
   
   MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor new];
   vertexDescriptor.attributes[0].format = MTLVertexFormatFloat;
   vertexDescriptor.attributes[0].offset = 0;
   vertexDescriptor.attributes[0].bufferIndex = 0;
   int stride = sizeof(struct Vertex) * 3;
   vertexDescriptor.layouts[0].stride = stride;
   pipelineDescriptor.vertexDescriptor = vertexDescriptor;
   
   NSError *error;
   id<MTLRenderPipelineState> renderPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
   NSAssert(renderPipelineState, @"Failed to create pipeline state: %@", error);
   
   return renderPipelineState;
}

- (void)drawInMTKView:(nonnull MTKView *)view {
   id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
   commandBuffer.label = @"Screen rendering";
   
   if (_renderPipelineState == nil)
   {
      _renderPipelineState = [self makeRenderPipelineStateWithView:view vertexShader:@"texturedVertexShader" fragmentShader:@"texturedFragmentShader"];
   }
   
   
   MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor new];
   vertexDescriptor.attributes[0].format = MTLVertexFormatFloat;
   vertexDescriptor.attributes[0].offset = 0;
   vertexDescriptor.attributes[0].bufferIndex = 0;
   vertexDescriptor.layouts[0].stride = sizeof(float) * 3;
   
   MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
   renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 255);
   renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
   renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
   id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
   
   //IMGUI stuff
   ImGuiIO& io = ImGui::GetIO();
   io.DisplaySize.x = _view.bounds.size.width;
   io.DisplaySize.y = _view.bounds.size.height;

      
   // Set up transformationmatrix
   float width = view.currentDrawable.texture.width;
   float height = view.currentDrawable.texture.height;

   float scaleX = _magnification/width;
   float scaleY = _magnification/height;
   [_world drawWithRenderEncoder:renderEncoder
            renderPipelineState:_renderPipelineState
                           centX:_cent.x-_offset.x centY:_cent.y+_offset.y
                          scaleX:scaleX scaleY:scaleY];

   [self runGui:renderEncoder renderPassDescriptor:renderPassDescriptor];
   
   [_world compute:_simulationSpeed];
   _epoch = [_world epoch];
   
   // Loop through any skipped epochs
   for(int epoch = _epoch - _simulationSpeed + 1; epoch <= _epoch; epoch++) {
      if ((_autoSaveInterval >= 1) && (strcmp(_autoSavePath, "") != 0) && (_epoch % _autoSaveInterval == 0)) {
         NSString *path = [NSString stringWithFormat:[NSString stringWithUTF8String: _autoSavePath],_epoch];
         NSString* fullpath = [@"file://" stringByAppendingString:path];
         NSError *error = [_world save:[NSURL URLWithString:fullpath]];
         if (error != nil) {
            NSAlert* alert = [NSAlert alertWithError:error];
            [alert runModal];
         }
         NSLog(@"Auto saved to %@", path);
      }
   }
   [self setInfoText];

   [renderEncoder endEncoding];

   // Present
   [commandBuffer presentDrawable:view.currentDrawable];
   [commandBuffer commit];
}

- (void)setInfoText {
   NSString* infoText = [[NSString alloc]initWithFormat:@"Epoch %d  |  ",_epoch];
   switch(_simulationSpeed) {
      case 0:
         infoText = [infoText stringByAppendingString:@"||"];
         break;
      case 1:
         infoText = [infoText stringByAppendingString:@">"];
         break;
      case 2:
         infoText = [infoText stringByAppendingString:@">>"];
         break;
      case 4:
         infoText = [infoText stringByAppendingString:@">>>>"];
         break;
   }
   [_infoText setStringValue:infoText];
}

- (void)runGui:(id<MTLRenderCommandEncoder>)renderEncoder
renderPassDescriptor:(MTLRenderPassDescriptor*)renderPassDescriptor {
   id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
   
   //IMGUI stuff
   ImGuiIO& io = ImGui::GetIO();
   io.DisplaySize.x = _view.bounds.size.width;
   io.DisplaySize.y = _view.bounds.size.height;
   
#if TARGET_OS_OSX
   CGFloat framebufferScale = _view.window.screen.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor;
#else
   CGFloat framebufferScale = _view.window.screen.scale ?: UIScreen.mainScreen.scale;
#endif
   io.DisplayFramebufferScale = ImVec2(framebufferScale, framebufferScale);
   
   // Start the Dear ImGui frame
   ImGui_ImplMetal_NewFrame(renderPassDescriptor);
#if TARGET_OS_OSX
   ImGui_ImplOSX_NewFrame(_view);
#endif
   ImGui::NewFrame();
   
   [Analysis runGui:_worldParams world:_world open:&_analysisOpen];

   //ImGui::ShowDemoWindow();
   ImGui::Begin("Settings", NULL, ImGuiWindowFlags_AlwaysAutoResize);
   
   ImGui::SliderFloat("mutate%", &_worldParams->background_mutation_rate,0.0, 1.0);
   ImGui::SliderInt("max steps", &_worldParams->max_steps, 0, 8*1024);
   ImGui::SliderInt("max dist", &_worldParams->max_dist, 1, 100);
   ImGui::Checkbox("fixed shuffle", &_worldParams->fixed_shuffle);
   ImGui::InputText("Autosave path", _autoSavePath, 256);
   ImGui::InputInt("Autosave interval", &_autoSaveInterval);

   int sx = arc4random_uniform(WORLD_WIDTH);
   int sy = arc4random_uniform(WORLD_HEIGHT);
   if (ImGui::Button("Spawn self-replicator 1")) {
      [_world setCellX:sx Y:sy program:1];
   }
   if (ImGui::Button("Spawn self-replicator 2")) {
      [_world setCellX:sx Y:sy program:2];
   }
   if (ImGui::Button("Spawn self-replicator 3")) {
      [_world setCellX:sx Y:sy program:3];
   }
   ImGui::InputInt("Random seed", &_worldParams->seed);
   if (ImGui::Button("Reset")) {
      [_world reset:_worldParams->seed];
   }
   if (ImGui::Button("Save world")) {
      int savedSimSpeed = _simulationSpeed;
      _simulationSpeed = 0;
      NSSavePanel* panel = [NSSavePanel savePanel];
      [panel beginSheetModalForWindow:_view.window completionHandler:^(NSInteger result){
         if (result == NSModalResponseOK)
         {
            NSError *error = [_world save:[panel URL]];
            NSAlert *alert;
            if (error != nil) {
               alert = [NSAlert alertWithError:error];
            } else {
               alert = [NSAlert alertWithMessageText:@"Success!" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Saved %@",[panel URL]];
            }
            [alert runModal];
         }
         _simulationSpeed = savedSimSpeed;
      }];
   }
   
   if (ImGui::Button("Load world")) {
      int savedSimSpeed = _simulationSpeed;
      _simulationSpeed = 0;
      NSOpenPanel* panel = [NSOpenPanel openPanel];
      [panel beginSheetModalForWindow:_view.window completionHandler:^(NSInteger result){
         if (result == NSModalResponseOK)
         {
            [_world load:[panel URL]];
            _epoch = [_world epoch];
         }
         _simulationSpeed = savedSimSpeed;
      }];
   }
   ImGui::End();
   

   ImGui::Render();
   ImDrawData* draw_data = ImGui::GetDrawData();
   
   ImGui_ImplMetal_RenderDrawData(draw_data, commandBuffer, renderEncoder);

   if (!io.WantCaptureMouse) {
      if (ImGui::IsMouseDragging(ImGuiMouseButton_Left,1)) {
         _offset = [self screenOffsetToWorldOffset:ImGui::GetMouseDragDelta(ImGuiMouseButton_Left)];
      }
      if (ImGui::IsMouseReleased(ImGuiMouseButton_Left)) {
               _cent.x -= _offset.x;
               _cent.y += _offset.y;
               _offset = ImVec2(0,0);
      }
      if (ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left)) {
         _cent.x = 0;
         _cent.y = 0;
         _magnification = _initMagnification;
      }
   }
   
   if (!io.WantCaptureKeyboard) {
      if (ImGui::IsKeyPressed(ImGuiKey_Space)) {
         if (_simulationSpeed == 0) {
            _simulationSpeed = 1;
         } else {
            _simulationSpeed = _simulationSpeed * 2;
            if (_simulationSpeed > 4) {
               _simulationSpeed = 0;
            }
         }
         [self setInfoText];
      }
   }
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
}


@end

//
//  Analysis.m
//  PeaSoup
//
//  Created by Adrian Skilling on 17/06/2024.
//

#import <Foundation/Foundation.h>

#include "imgui.h"
#include "imgui_impl_metal.h"
#include "imgui_impl_osx.h"

#import "ShaderDefinitions.h"
#import "Analysis.h"
#import "World.h"
//#import "Utils.h"

@implementation Analysis

+ (float)computeHistogram:(float*)values len:(int)len world:(World*)world {
   float ymax = 0;
   for(int x=0; x<len; x++) {
      values[x] = 0;
   }
   for(int x=0; x<WORLD_WIDTH; x++) {
      for(int y=0; y<WORLD_HEIGHT; y++) {
         struct Cell* cell = [world getCellX:x Y:y];
         for(int i=0; i<64; i++) {
            values[cell->tape[i]]++;
         }
      }
   }
   for(int i=0; i<256; i++) {
      if (values[i] > ymax) {
         ymax = values[i];
      }
   }
   return ymax;
}

+ (void)histogram:(const char*)name
             data:(float*)data
              len:(int)len
            world:(World*)world {
   static int frame = 0;
   if (frame%4 == 0) {
      [world syncGpuCells];
   }
   float ymax = [self computeHistogram:data len:len world:world];
   int width = ImGui::GetWindowWidth();
   ImGui::PlotHistogram("##size", data, len, 0, NULL, 0.0f, ymax, ImVec2(-1,0.25*width));
   frame++;
}

+ (ImVec4)instructionToColor:(int)v {
   switch(v) {
      case 0:
         return ImVec4(1,0,0,1);
         break;
      case '[':
      case ']':
         return ImVec4(0,192/255.0,0,1);
         break;
      case '+':
      case '-':
         return ImVec4(170/255.0,0,170/255.0,1);
         break;
      case '.':
      case ',':
         return ImVec4(200/255.0,0,200/255.0,1);
         break;
      case '<':
      case '>':
         return ImVec4(0,128/255.0,220/255.0,1);
         break;
      case '{':
      case '}':
         return ImVec4(0,128/255.0,220/255.0,1);
         break;
   }
   return ImVec4(0,0,0,1);
}


+ (void)runGui:(WorldParams*)worldParams world:(World*)world open:(bool*)open {
   ImGui::Begin("Analysis", open, ImGuiWindowFlags_None);
   ImGui::BeginTabBar("analysis_tabs", ImGuiTabBarFlags_None);
   if (ImGui::BeginTabItem("Bytes")) {
      static float bytes[256];
      [self histogram:"bytes" data:bytes len:IM_ARRAYSIZE(bytes) world:world];
      ImGui::EndTabItem();
   }
   if (ImGui::BeginTabItem("Instructions")) {
      static float bytes[256];
      static int frame = 0;
      if (frame%4 == 0) {
         [world syncGpuCells];
      }
      float ymax = [self computeHistogram:bytes len:256 world:world];
      static char instructions[] = "<>{},.-+[]";
      for(int i=0; i<strlen(instructions); i++) {
         char c = instructions[i];
         //sprintf(buf,"%d",bytes[c]);
         static char text[] = "X";
         text[0] = c;
         ImGui::Text(text);
         ImGui::SameLine(0.0f, ImGui::GetStyle().ItemInnerSpacing.x);
         ImGui::PushStyleColor(ImGuiCol_PlotHistogram, [self instructionToColor:c]);
         ImGui::ProgressBar(((float)bytes[c])/ymax, ImVec2(0.0f,0.0f));
         ImGui::PopStyleColor();
      }
      frame++;
      ImGui::EndTabItem();
   }
   ImGui::EndTabBar();
   
   ImGui::End();
}
   
@end
   

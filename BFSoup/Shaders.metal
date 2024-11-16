//
//  Shaders.metal
//  Orbits
//
//  Created by Adrian Skilling on 25/02/2023.
//

#include <metal_stdlib>
#include "ShaderDefinitions.h"

using namespace metal;

struct VertexIn {
   float2 pos [[ attribute(0) ]];
};

struct TexturedVertexOut {
   float4 pos [[position]];
   float2 texCoord;
};

// TODO: We need to change the parameters and return types of the shaders.
struct VertexOut {
   float4 color;
   float4 pos [[position]];
};

vertex TexturedVertexOut texturedVertexShader(const device TexturedVertex *vertexArray [[buffer(0)]],
                                      SceneParams constant &scene [[buffer(1)]],
                                      unsigned int bid [[vertex_id]])
{
   TexturedVertex in = vertexArray[bid];
   TexturedVertexOut out;
   out.pos = float4((in.pos - scene.cent) * scene.scale, 1, 1);
   out.texCoord = in.texCoord;
   return out;
}

fragment float4 texturedFragmentShader(TexturedVertexOut in [[stage_in]],
                                       texture2d<float> colorTexture [[texture(0)]])
{
   constexpr sampler colorSampler(mip_filter::nearest, mag_filter::nearest, min_filter::linear);
   float4 out = colorTexture.sample(colorSampler, in.texCoord);
   return float4(out.rgb,1);
}

fragment float4 fragmentShader(VertexOut interpolated [[stage_in]])
{
   float4 out = interpolated.color;
   return out;
}


package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Scene Color")
@description("Read HDR scene color behind current pixel, available from forwardAlpha onwards")
@group("Property")
@needsSceneColor
class SceneColor extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var offset : Vec2;
		@sgoutput var output : Vec3;

		@global var sceneColorMap : Sampler2D;

		var projectedPosition : Vec4;
		var screenUV : Vec2;

		function fragment() {
			screenUV = screenToUv(projectedPosition.xy / projectedPosition.w);
			output = sceneColorMap.get(clamp(screenUV + offset, vec2(0.0), vec2(1.0))).rgb;
		}
	};
}

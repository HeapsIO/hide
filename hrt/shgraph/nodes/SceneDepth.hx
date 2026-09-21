package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Scene Depth")
@description("Read depth behind current pixel")
@group("Property")
class SceneDepth extends ShaderNodeHxsl {

	static var SRC = {
		@sginput("calculatedUV") var uv : Vec2;
		@sgoutput var output : Float;

		@global var depthMap : Channel;

		@global var camera : {
			var zNear : Float;
			var zFar : Float;
		};

		var projectedPosition : Vec4;
		var screenUV : Vec2;

		function fragment() {
			screenUV = screenToUv(projectedPosition.xy / projectedPosition.w);
			output = depthMap.get(screenUV);
		}
	};
}

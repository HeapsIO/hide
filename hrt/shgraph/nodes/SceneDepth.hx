package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Scene Depth")
@description("Read depth behind current pixel")
@group("Property")
class SceneDepth extends ShaderNodeHxsl {

	static var SRC = {
		@sgoutput var output : Float;

        @global var depthMap : Channel;

		@global var camera : {
			var zNear : Float;
			var zFar : Float;
		};

        var screenUV : Vec2;

		function fragment() {
			output = depthMap.get(screenUV);
		}
	};
}

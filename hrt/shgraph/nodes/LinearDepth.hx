package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Linear Depth")
@description("Linearize depth")
@group("Property")
class LinearDepth extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var d : Float;
		@sgoutput var output : Float;

		@global var camera : {
			var zNear : Float;
			var zFar : Float;
		};

        var screenUV : Vec2;

		function fragment() {
			var n = camera.zNear;
			var f = camera.zFar;
			output = (2 * n * f) / (f + n - (2 * d - 1) * (f - n));
		}
	};
}

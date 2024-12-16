package hrt.shgraph.nodes;

using hxsl.Ast;

@name("WorldToScreen")
@description("Transform a position from world space to screen space")
@group("Property")
class WorldToScreen extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var input : Vec3;
		@sgoutput var output : Vec3;

		@global var camera : { var viewProj : Mat4; };

		function fragment() {
			var result = vec4(input, 1.0) * camera.viewProj;
			output = result.xyz / result.w;
		}
	};
}

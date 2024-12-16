package hrt.shgraph.nodes;

using hxsl.Ast;

@name("CameraToScreen")
@description("Transform a position from camera space to screen space")
@group("Property")
class CameraToScreen extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var input : Vec3;
		@sgoutput var output : Vec3;

		@global var camera : { var proj : Mat4; };

		function fragment() {
			var result = vec4(input, 1.0) * camera.proj;
			output = result.xyz / result.w;
		}
	};
}

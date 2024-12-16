package hrt.shgraph.nodes;

using hxsl.Ast;

@name("WorldToCamera")
@description("Transform a position from world space to camera space")
@group("Property")
class WorldToCamera extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var input : Vec3;
		@sgoutput var output : Vec3;

		@global var camera : { var view : Mat4; };

		function fragment() {
			output = input * camera.view.mat3x4();
		}
	};
}

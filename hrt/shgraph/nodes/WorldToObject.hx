package hrt.shgraph.nodes;

using hxsl.Ast;

@name("WorldToObject")
@description("Transform a position from world space to object space")
@group("Property")
class WorldToObject extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var input : Vec3;
		@sgoutput var output : Vec3;

		@global var global : { @perObject var modelViewInverse : Mat4; };

		function fragment() {
			output = input * global.modelViewInverse.mat3x4();
		}
	};
}

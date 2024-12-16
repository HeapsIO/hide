package hrt.shgraph.nodes;

using hxsl.Ast;

@name("ObjectToWorld")
@description("Transform a position from object space to world space")
@group("Property")
class ObjectToWorld extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var input : Vec3;
		@sgoutput var output : Vec3;

		@global var global : { @perObject var modelView : Mat4; };

		function fragment() {
			output = input * global.modelView.mat3x4();
		}
	};
}

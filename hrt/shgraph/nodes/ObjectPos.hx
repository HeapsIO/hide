package hrt.shgraph.nodes;

using hxsl.Ast;

@name("ObjectPos")
@description("Returns the position of the object (in world space)")
@group("Property")
class ObjectPos extends ShaderNodeHxsl {

	static var SRC = {
		@sgoutput var output : Vec3;

		@global var global : { @perObject var modelView : Mat4; };

		function fragment() {
			output = vec3(0.0) * global.modelView.mat3x4();
		}
	};
}

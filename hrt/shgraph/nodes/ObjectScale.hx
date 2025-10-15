package hrt.shgraph.nodes;

using hxsl.Ast;

@name("ObjectScale")
@description("Returns the scale of the object")
@group("Property")
class ObjectScale extends ShaderNodeHxsl {

	static var SRC = {
		@sgoutput var output : Vec3;

		@global var global : { @perObject var modelView : Mat4; };

		function fragment() {
			var scaleX = length(vec3(global.modelView[0].x,global.modelView[1].x,global.modelView[2].x));
			var scaleY = length(vec3(global.modelView[0].y,global.modelView[1].y,global.modelView[2].y));
			var scaleZ = length(vec3(global.modelView[0].z,global.modelView[1].z,global.modelView[2].z));
			output = vec3(scaleX, scaleY, scaleZ);
		}
	};
}

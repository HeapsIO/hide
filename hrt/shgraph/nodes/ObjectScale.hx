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
			var objPos = vec3(0.0) * global.modelView.mat3x4();
			var xPos = vec3(1.0, 0.0, 0.0) * global.modelView.mat3x4();
			var x = length(xPos - objPos);
			var yPos = vec3(0.0, 1.0, 0.0) * global.modelView.mat3x4();
			var y = length(yPos - objPos);
			var zPos = vec3(0.0, 0.0, 1.0) * global.modelView.mat3x4();
			var z = length(zPos - objPos);
			output = vec3(x, y, z);
		}
	};
}

package hrt.shgraph.nodes;

using hxsl.Ast;

@name("ObjectToTangent")
@description("Transform a direction from object space to tangent space")
@group("Property")
class ObjectToTangent extends ShaderNodeHxsl {
	static var SRC = {
		@sginput var direction : Vec3;
		@sgoutput var output : Vec3;

		@input var input : {
			var normal : Vec3;
			var tangent : Vec3;
        };

		var transformedNormal : Vec3;
		function fragment() {
			var tangent = input.tangent;
			var signTangent = tangent.dot(tangent) > 0.5 ? -1. : 1.;
			var normal = input.normal;
			var bitangent = cross(normal, tangent) * signTangent;
			output = vec3(dot(direction, tangent), dot(direction, bitangent), dot(direction, normal));
		}
	};
}
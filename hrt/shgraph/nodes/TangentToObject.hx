package hrt.shgraph.nodes;

using hxsl.Ast;

@name("TangentToObject")
@description("Transform a direction from tangent space to world space")
@group("Property")
class TangentToObject extends ShaderNodeHxsl {
	static var SRC = {
		@sginput var direction : Vec3;
		@sgoutput var output : Vec3;

		@input var input : {
			var normal : Vec3;
			var tangent : Vec3;
        };

		function fragment() {
			var tangent = input.tangent;
			var signTangent = tangent.dot(tangent) > 0.5 ? -1. : 1.;
			var normal = input.normal;
			var bitangent = cross(normal, tangent) * signTangent;
			output = direction.x * tangent + direction.y * bitangent + direction.z * normal;
		}
	};
}
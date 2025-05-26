package hrt.shgraph.nodes;

using hxsl.Ast;

@name("WorldToTangent")
@description("Transform a direction from world space to tangent space")
@group("Property")
class WorldToTangent extends ShaderNodeHxsl {
	static var SRC = {
		@sginput var direction : Vec3;
		@sgoutput var output : Vec3;

		@global var global : {
             @perObject var modelViewInverse : Mat4;
        };

		@input var input : {
			var normal : Vec3;
			var tangent : Vec3;
        };

		var transformedNormal : Vec3;
		function fragment() {
			var directionObj = direction * global.modelViewInverse.mat3();
			var tangent = input.tangent;
			var signTangent = tangent.dot(tangent) > 0.5 ? -1. : 1.;
			var normal = input.normal;
			var bitangent = cross(normal, tangent) * signTangent;
			output = vec3(dot(directionObj, tangent), dot(directionObj, bitangent), dot(directionObj, normal));
		}
	};
}
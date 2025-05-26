package hrt.shgraph.nodes;

using hxsl.Ast;

@name("TangentToWorld")
@description("Transform a direction from tangent space to world space")
@group("Property")
class TangentToWorld extends ShaderNodeHxsl {
	static var SRC = {
		@sginput var direction : Vec3;
		@sgoutput var output : Vec3;

		@global var global : {
            @perObject var modelView : Mat4;
        };

		@input var input : {
			var tangent : Vec3;
        };

		var transformedNormal : Vec3;
		function fragment() {
			var tangentWS = vec4(input.tangent * global.modelView.mat3(),input.tangent.dot(input.tangent) > 0.5 ? 1. : -1.);
			var tanX = normalize(tangentWS.xyz);
			var tanY = cross(transformedNormal, tanX) * tangentWS.w;
			output = normalize(direction.x * tanX + direction.y * tanY + direction.z * transformedNormal);
		}
	};
}
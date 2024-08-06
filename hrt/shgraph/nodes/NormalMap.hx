package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Normal map")
@description("Returns normal in world space using a normal map")
@width(160)
@group("Math")
class NormalMap extends Sampler {

	static var SRC = {
		@sginput var texture : Sampler2D;
		@sginput(calculatedUV) var uv : Vec2;
		@sgoutput var normalWS : Vec3;

		@global var global : {
            @perObject var modelView : Mat4;
        };

		@input var input : {
			var tangent : Vec3;
        };

		var transformedNormal : Vec3;
		function fragment() {
			var tangentWS = vec4(input.tangent * global.modelView.mat3(),input.tangent.dot(input.tangent) > 0.5 ? 1. : -1.);
			var nf = unpackNormal(texture.get(uv));
			var tanX = tangentWS.xyz.normalize();
			var tanY = transformedNormal.cross(tanX) * -tangentWS.w;
			normalWS = (nf.x * tanX + nf.y * tanY + nf.z * transformedNormal).normalize();
		}
	};
}
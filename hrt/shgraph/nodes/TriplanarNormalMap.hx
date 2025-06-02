package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Triplanar normal map")
@description("Sample a normal map using triplanar params")
@width(160)
@group("Math")
class TriplanarNormalMap extends Sampler {

	static var SRC = {
		@sginput var texture : Sampler2D;
		@sginput var weight : Vec3;
		@sginput var uvX : Vec2;
		@sginput var uvY : Vec2;
		@sginput var uvZ : Vec2;
		@sgoutput var normalWS : Vec3;

		@global var global : {
            @perObject var modelView : Mat4;
        };

		@input var input : {
			var tangent : Vec3;
        };

		var transformedNormal : Vec3;
		function fragment() {
			var nx = unpackNormal(texture.get(uvX));
			nx.y *= -1.0;
			var ny = unpackNormal(texture.get(uvY));
			ny.y *= -1.0;
			var nz = unpackNormal(texture.get(uvZ));
			nz.y *= -1.0;

			nx = vec3(nx.xy + transformedNormal.zy, transformedNormal.x);
			ny = vec3(ny.xy + transformedNormal.xz, transformedNormal.y);
			nz = vec3(nz.xy + transformedNormal.xy, transformedNormal.z);

			normalWS = normalize(nx.zyx * weight.x + ny.xzy * weight.y + nz.xyz * weight.z);
		}
	};
}
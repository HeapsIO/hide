package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Triplanar params")
@description("Returns parameters useful to sample a texture using triplanar mapping")
@width(160)
@group("Math")
class TriplanarParams extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(2.0) var sharpness : Float;
		@sgoutput var weight : Vec3;
		@sgoutput var uvX : Vec2;
		@sgoutput var uvY : Vec2;
		@sgoutput var uvZ : Vec2;

		var transformedNormal : Vec3;
		var transformedPosition : Vec3;
		function fragment() {
			weight = pow(abs(transformedNormal), vec3(sharpness));
			weight = weight / (weight.x + weight.y + weight.z);
			uvX = transformedPosition.zy;
			uvY = transformedPosition.xz;
			uvZ = transformedPosition.xy;
		}
	};
}
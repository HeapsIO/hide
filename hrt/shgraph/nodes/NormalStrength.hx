package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Normal Strength")
@description("Adjusts the strength of a tangent space normal. A strength of one results in unaltered normal")
@width(120)
@group("Math")
class NormalStrength extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var normal : Vec3;
		@sginput(1.0) var strength : Float;
		@sgoutput var output : Vec3;
		function fragment() {
			output = vec3(normal.xy * strength, mix(1.0, normal.z, saturate(strength)));
		}
	};
}

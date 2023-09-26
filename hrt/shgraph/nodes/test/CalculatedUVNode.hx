package hrt.shgraph.nodes.test;

@name("Calculated UV")
@description("Testing only")
@width(80)
@group("Misc")
class CalculatedUVNode extends ShaderNodeHxsl {

	static var SRC = {
		@input var uv : Vec2;
		@sgoutput var output : Vec4;
		function fragment() {
			output = vec4(uv, 0.0,0.0);
		}
	}
}
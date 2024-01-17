package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Deg to Rad")
@description("Convert an angle in degree to an angle in radians")
@width(80)
@group("Math")
class Deg2Rad extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = a * 3.141592 / 180.0;
		}
	};
}
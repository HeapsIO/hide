package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Triangle Wave")
@description("A triangle wave of period 1 oscilating between -1 and 1")
@width(120)
@group("Math")
class TriangleWave extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = 2*2*abs(a-floor(a+0.5))-1;
		}
	};
}
package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Square Wave")
@description("A square wave of period 1 oscilating between -1 and 1")
@width(120)
@group("Math")
class SquareWave extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = 2*(2*floor(a)-floor(2*a))+1;
		}
	};
}
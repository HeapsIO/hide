package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Log")
@description("The output is the result of log(x)")
@width(80)
@group("Math")
class Log extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = log(a);
		}
	};

}
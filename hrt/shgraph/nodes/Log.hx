package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Log")
@description("The output is the result of log(x)")
@width(80)
@group("Math")
class Log extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var a : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = log(a);
		}
	};

}
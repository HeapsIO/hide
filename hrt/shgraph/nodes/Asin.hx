package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Arc Sinus")
@description("The output is the arc sinus of A")
@width(80)
@group("Math")
class Asin extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var a : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = asin(a);
		}
	};

}
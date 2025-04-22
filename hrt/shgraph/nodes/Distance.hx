package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Distance")
@description("")
@width(80)
@group("Math")
class Distance extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sginput(0.0) var b : Dynamic;
		@sgoutput var output : Float;
		function fragment() {
			output = distance(a,b);
		}
	};

}
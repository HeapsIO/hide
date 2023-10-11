package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Step")
@description("Generate a step function by comparing a[i] to edge[i]")
@width(80)
@group("Math")
class Step extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var edge : Dynamic;
		@sginput var fact : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = step(edge, fact);
		}
	};

}
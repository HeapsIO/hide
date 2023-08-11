package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Step")
@description("Generate a step function by comparing a[i] to edge[i]")
@width(80)
@group("Math")
class Step extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var edge : Vec4;
		@sginput var fact : Vec4;
		@sgoutput var output : Vec4;
		function fragment() {
			output = step(edge, fact);
		}
	};

}
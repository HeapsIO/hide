package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Contrast")
@description("Adjusts the contrast of input by the amount given, around the pivot value. An amount of one results in unaltered content")
@width(80)
@group("Math")
class Contrast extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sginput(1.0) var amount : Float;
		@sginput(0.5) var pivot : Float;

		@sgoutput var output : Dynamic;
		function fragment() {
			output = (a - pivot) * amount + pivot;
		}
	};
}

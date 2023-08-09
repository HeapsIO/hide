package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Exp")
@description("The output is the result of exp(x)")
@width(80)
@group("Math")
class Exp extends ShaderFunction {

	// @input("X") var x = SType.Number;
	// @input("P", true) var p = SType.Number;

	// public function new() {
	// 	super(Exp);
	// }

	// override public function computeOutputs() {
	// 	if (x != null && !x.isEmpty())
	// 		addOutput("output", x.getType());
	// 	else
	// 		removeOutput("output");
	// }
}
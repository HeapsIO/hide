package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Sqrt")
@description("The output is the squre root A")
@width(80)
@group("Math")
@:keep
class Sqrt extends ShaderFunction {

	// @input("A") var a = SType.Number;

	// public function new() {
	// 	super(Sqrt);
	// }

	// override public function computeOutputs() {
	// 	if (a != null && !a.isEmpty())
	// 		addOutput("output", a.getType());
	// 	else
	// 		removeOutput("output");
	// }

}
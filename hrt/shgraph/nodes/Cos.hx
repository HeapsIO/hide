package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Cosinus")
@description("The output is the cosinus of A")
@width(80)
@group("Math")
class Cos extends ShaderFunction {

	// @input("A") var a = SType.Float;

	// public function new() {
	// 	super(Cos);
	// }

	// override public function computeOutputs() {
	// 	if (a != null && !a.isEmpty())
	// 		addOutput("output", a.getType());
	// 	else
	// 		removeOutput("output");
	// }

}
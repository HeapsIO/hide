package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Sinus")
@description("The output is the sinus of A")
@width(80)
@group("Math")
class Sin extends ShaderFunction {

	// @input("A") var a = SType.Float;

	// public function new() {
	// 	super(Sin);
	// }

	// override public function computeOutputs() {
	// 	if (a != null && !a.isEmpty())
	// 		addOutput("output", a.getType());
	// 	else
	// 		removeOutput("output");
	// }

}
package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Smooth Step")
@description("Linear interpolation between A and B using Mix")
@width(100)
@group("Math")
class SmoothStep extends ShaderFunction {

	// @input("A") var x = SType.Number;
	// @input("B") var y = SType.Number;
	// @input("Mix") var a = SType.Number;

	// public function new() {
	// 	super(Smoothstep);
	// }

	// override public function computeOutputs() {
	// 	if (x != null && !x.isEmpty() && y != null && !y.isEmpty())
	// 		addOutput("output", x.getVar(y.getType()).t);
	// 	else if (x != null && !x.isEmpty() )
	// 		addOutput("output", x.getType());
	// 	else if (y != null && !y.isEmpty())
	// 		addOutput("output", y.getType());
	// 	else
	// 		removeOutput("output");
	// }

}
package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Log")
@description("The output is the result of log(x)")
@width(80)
@group("Math")
class Log extends ShaderFunction {

	@input("X") var x = SType.Number;
	@input("P", true) var p = SType.Number;

	public function new() {
		super(Log);
	}

	override public function computeOutputs() {
		if (x != null && !x.isEmpty())
			addOutput("output", x.getType());
		else
			removeOutput("output");
	}
}
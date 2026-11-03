package hrt.shgraph;

using hxsl.Ast;

@name("SubGraph Output")
@width(120)
@color("#A90707")
class ShaderSubGraphOutput extends ShaderNode {
	@prop() public var outputId : Int = -1;

	public function new() {

	}

	override function getInputs() : Array<ShaderNode.InputInfo> {
		var output = getOutput();
		return [{name: output.name, type: output.type, def: NoDefault}];
	}

	override function generate(ctx: NodeGenContext) {
		var input = ctx.getInput(0);
		if (input == null)
			return;
		ctx.setSubGraphOutput(outputId, input);
		if (input.t != TInt)
			ctx.addPreview(input);
	}

	function getOutput() : ShaderSubGraph.SubGraphOutput {
		return (cast graph.parent : ShaderSubGraph).subGraphOutputs.get(outputId);
	}
}

package hrt.shgraph;

using hxsl.Ast;

@name("SubGraph Output")
@width(120)
@color("#A90707")
class ShaderSubGraphOutput extends ShaderNode {
	@prop() public var outputId : Int = -1;

	public function new() {

	}

	override public function serializeToDynamic(forClipboard: Bool = false) : Dynamic {
		var data = super.serializeToDynamic(forClipboard);
		var output = getOutput();
		if (forClipboard && output != null) {
			data.outputName = output.name;
			data.outputType = ShaderGraph.serializeSgType(output.type);
		}
		return data;
	}

	override public function unserializeFromDynamic(data: Dynamic, forClipboard: Bool = false) : Void {
		super.unserializeFromDynamic(data, forClipboard);
		if (forClipboard && Std.isOfType(graph.parent, ShaderSubGraph)) {
			var output = Lambda.find((cast graph.parent : ShaderSubGraph).subGraphOutputs, (o) -> o.name == data.outputName);
			if (output == null)
				throw 'Missing output "${data.outputName}"';
			if (ShaderGraph.serializeSgType(output.type) != data.outputType)
				throw 'Output "${output.name}" has a different type';
			outputId = output.id;
		}
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

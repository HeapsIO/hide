package hrt.shgraph.nodes;


@name("Var Read")
@description("Read a value from a local variable")
@width(80)
@group("Variables")
class VarRead extends ShaderVar {

	public function new() {
	}

	var outputs: Array<ShaderNode.OutputInfo>;
	override public function getOutputs() : Array<ShaderNode.OutputInfo> {
		if (outputs == null) {
			// cache the output array to avoid multiple allocations
			outputs = [{name:"error", type: SgBool}];
		}
		// reassign name and type in case they have changed since the last getOutput
		outputs[0].name = graph.parent.variables[varId]?.name ?? "error";
		outputs[0].type = graph.parent.variables[varId]?.type ?? SgBool;
		return outputs;
	}

	override function generate(ctx:NodeGenContext) {
		var out = AstTools.makeVar(ctx.getShaderVariable(varId));
		ctx.setOutput(0, out);
		#if editor
		ctx.addPreview(out);
		#end
	}
}
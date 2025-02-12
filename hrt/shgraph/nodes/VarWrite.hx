package hrt.shgraph.nodes;

@name("Var Write")
@description("Write a value to a local variable")
@width(80)
@group("Variables")
class VarWrite extends ShaderVar {

	public function new() {
	}

	var inputs: Array<ShaderNode.InputInfo>;
	override public function getInputs() : Array<ShaderNode.InputInfo> {
		if (inputs == null) {
			inputs = [{name:"error", type: SgBool}];
		}
		// reassign name and type in case they have changed since the last getInput
		inputs[0].name = graph.parent.variables[varId]?.name ?? "error";
		inputs[0].type = graph.parent.variables[varId]?.type ?? SgBool;
		return inputs;
	}

	override function generate(ctx:NodeGenContext) {
		var input = ctx.getInput(0);
		var tVar = ctx.getShaderVariable(varId, input);
		ctx.addPreview(AstTools.makeVar(tVar));
	}
}
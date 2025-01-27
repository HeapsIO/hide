package hrt.shgraph.nodes;

@name("Write Var")
@description("Write a value to a local variable")
@width(80)
@group("Variables")
class VarWrite extends ShaderNode {
	@prop() public var varId : Int = 0;

	var inputs: Array<ShaderNode.InputInfo>;
	override public function getInputs() : Array<ShaderNode.InputInfo> {
		if (inputs == null) {
			inputs = [{name: "input", type: SgFloat(4)}];
		}
		return inputs;
	}

	override function generate(ctx:NodeGenContext) {
		var input = ctx.getInput(0);
		ctx.addExpr(AstTools.makeVarDecl(ctx.getLocalTVar("_sg_var_write", TVec(4, VFloat)), input));
		ctx.addPreview(input);
	}
}
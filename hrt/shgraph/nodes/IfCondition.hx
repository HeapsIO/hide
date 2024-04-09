package hrt.shgraph.nodes;

using hxsl.Ast;
import hrt.shgraph.AstTools.*;

@name("If")
@description("Return the correct input according to the condition")
@group("Condition")
class IfCondition extends ShaderNode {

	override function getOutputs() {
		static var output : Array<ShaderNode.OutputInfo> = [{name: "output", type: SgGeneric(0, ConstraintFloat)}];
		return output;
	}

	override function getInputs() {
		static var inputs : Array<ShaderNode.InputInfo> =
		[
			{name: "condition", type: SgBool},
			{name: "true", type: SgGeneric(0, ConstraintFloat)},
			{name: "false", type: SgGeneric(0, ConstraintFloat)},
		];
		return inputs;
	}

	override function generate(ctx: NodeGenContext) {
		var cond = ctx.getInput(0, ConstBool(true));
		var vTrue = ctx.getInput(1, Const(1.0));
		var vFalse = ctx.getInput(2, Const(0.0));

		var outType = ctx.getType(SgGeneric(0, ConstraintFloat));

		var test = makeIf(cond, vTrue, vFalse, null, outType);

		var v : TVar = {name: "output", id: Tools.allocVarId(), type: outType, kind: Local};
		var tmpvar = makeVarDecl(v, test);
		ctx.addExpr(tmpvar);
		ctx.setOutput(0, makeVar(v));
		ctx.addPreview(makeVar(v));
	}
}
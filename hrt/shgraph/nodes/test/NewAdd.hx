package hrt.shgraph.nodes.test;

using hxsl.Ast;
import hrt.shgraph.AstTools;

@name("NewAdd")
@description("New add, if this is in the final build come bonk Clement Espeute on the head plz")
@group("Property")
@color("#0e8826")
class NewAdd extends ShaderNode {


	override function generate(ctx: NodeGenContext) {
		var a = ctx.getInput(0, ShaderGraph.ShaderDefInput.Const(getDef("a", 0.0)));
		var b = ctx.getInput(1, ShaderGraph.ShaderDefInput.Const(getDef("b", 0.0)));

		var id = hxsl.Tools.allocVarId();
		var out = {id: id, name: 'output', kind: Local, type: ctx.getGenericType(0)};
		var add = AstTools.makeBinop(a, OpAdd, b);

		ctx.addExpr(AstTools.makeExpr(TVarDecl(out, add), out.type));
		ctx.setOutput(0, AstTools.makeVar(out));

		ctx.addPreview(AstTools.makeVar(out));
	}

	override function getInputs() : Array<ShaderNode.InputInfo> {
		static var inputs =
		[
			{name: "a", type: SgGeneric(0, ShaderGraph.ConstraintFloat), def: ShaderDefInput.Const(0.0)},
			{name: "b", type: SgGeneric(0, ShaderGraph.ConstraintFloat), def: ShaderDefInput.Const(0.0)}
		];
		return inputs;
	}

	override function getOutputs() : Array<ShaderNode.OutputInfo> {
		static var outputs = [{name: "output", type: SgGeneric(0, ShaderGraph.ConstraintFloat)}];
		return outputs;
	}

	override function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>) : ShaderGraph.ShaderNodeDef {
		throw "getShaderDef is not defined for class " + std.Type.getClassName(std.Type.getClass(this));
		return {expr: null, inVars: [], outVars: [], inits: [], externVars: []};
	}

	override function getOutputs2(domain: ShaderGraph.Domain, ?inputTypes: Array<Type>) : Map<String, {v: TVar, index: Int}> {
		return [
				"output" => {v: {id: 0, name: "a", type: TFloat, kind: Local}, index: 0},
			];
	}

	override function getInputs2(domain: ShaderGraph.Domain) : Map<String, {v: TVar, ?def: hrt.shgraph.ShaderGraph.ShaderDefInput, index: Int}> {
		return [for (id => i in getInputs())  i.name => {v: {id: 0, name: i.name, type: TFloat, kind: Local}, def: hrt.shgraph.ShaderGraph.ShaderDefInput.Const(0.0), index: id}];
	}

}
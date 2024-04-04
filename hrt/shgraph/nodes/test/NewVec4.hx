package hrt.shgraph.nodes.test;

using hxsl.Ast;
import hrt.shgraph.AstTools;

@name("NewVec4")
@description("New add, if this is in the final build come bonk Clement Espeute on the head plz")
@group("Property")
@color("#0e8826")
class NewVec4 extends ShaderNode {
	override function generate(ctx: NodeGenContext) {
		var a = ctx.getInput(0, SgHxslVar.ShaderDefInput.Const(getDef("a", 0.0)));
		var b = ctx.getInput(1, SgHxslVar.ShaderDefInput.Const(getDef("b", 0.0)));
		var c = ctx.getInput(2, SgHxslVar.ShaderDefInput.Const(getDef("c", 0.0)));
		var d = ctx.getInput(3, SgHxslVar.ShaderDefInput.Const(getDef("d", 0.0)));

		var id = hxsl.Tools.allocVarId();
		var out = {id: id, name: 'output', kind: Local, type: TVec(4, VFloat)};
		var ctor = AstTools.makeVecExpr([a,b,c,d]);

		ctx.addExpr(AstTools.makeExpr(TVarDecl(out, ctor), out.type));
		ctx.setOutput(0, AstTools.makeVar(out));

		ctx.addPreview(AstTools.makeVar(out));
	}

	override function getInputs() : Array<ShaderNode.InputInfo> {
		static var inputs =
		[
			{name: "a", type: SgFloat(1)},
			{name: "b", type: SgFloat(1)},
			{name: "c", type: SgFloat(1)},
			{name: "d", type: SgFloat(1)},
		];
		return inputs;
	}

	override function getOutputs() : Array<ShaderNode.OutputInfo> {
		static var outputs = [{name: "output", type: SgFloat(4)}];
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

	override function getInputs2(domain: ShaderGraph.Domain) : Map<String, {v: TVar, ?def: hrt.shgraph.SgHxslVar.ShaderDefInput, index: Int}> {
		return [for (id => i in getInputs())  i.name => {v: {id: 0, name: i.name, type: TFloat, kind: Local}, def: hrt.shgraph.SgHxslVar.ShaderDefInput.Const(0.0), index: id}];
	}

}
package hrt.shgraph.nodes.test;

using hxsl.Ast;
import hrt.shgraph.AstTools;

@name("NewTime")
@description("New add, if this is in the final build come bonk Clement Espeute on the head plz")
@group("Property")
@color("#0e8826")
class NewTime extends ShaderNode {
	function getDef(name: String, def: Float) {
		var defaultValue = Reflect.getProperty(defaults, name);
		if (defaultValue != null) {
			def = Std.parseFloat(defaultValue) ?? def;
		}
		return def;
	}

	override function generate(inputs: Array<TExpr>, ctx: NodeGenContext) {
		var time = ctx.getGlobalInputVar(Time);

		ctx.addOutput(AstTools.makeVar(time), 0);
		ctx.addPreview(AstTools.makeVar(time));
	}

	override function getOutputs() : Array<{name: String, ?type: Type}> {
		return [{name: "time", type: TFloat}];
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
		return [for (id => i in getInputs())  i.name => {v: {id: 0, name: i.name, type: i.type, kind: Local}, def: hrt.shgraph.ShaderGraph.ShaderDefInput.Const(0.0), index: id}];
	}

}
package hrt.shgraph.nodes.test;


using hxsl.Ast;

// Just pass the node around

@name("DynamicIdentity")
@description("Just for testing")
@width(80)
@group("Test")
class DynamicPass extends ShaderNode {

	override function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>):hrt.shgraph.ShaderGraph.ShaderNodeDef {
		var pos : Position = {file: "", min: 0, max: 0};

		var t = inputTypes != null ? inputTypes[0] : null;

		var input : TVar = {name: "in", id: getNewIdFn(), type: t, kind: Local, qualifiers: []};
		var output : TVar = {name: "out", id: getNewIdFn(), type: t, kind: Local, qualifiers: []};

		var finalExpr : TExpr = {e: TBinop(OpAssign, {e:TVar(output), p: pos, t:output.type}, {e:TVar(input), p: pos, t:output.type}), p: pos, t: output.type};

		return {expr: finalExpr, inVars: [{v: input, internal: false, isDynamic: t == null}], outVars: [{v: output, internal: false, isDynamic: t == null}], externVars: [], inits: []};
	}
}
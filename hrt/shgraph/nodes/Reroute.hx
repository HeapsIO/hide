package hrt.shgraph.nodes;

using hxsl.Ast;

#if editor
import hide.view.GraphInterface;
#end

/**
	Base class for the reroute nodes : forward its input to its output unchanged.
	Purely cosmetic, used to tidy up the graph. When the input is not connected,
	the output is left null so the nodes downstream behave as if they were not connected either.
**/
class Reroute extends ShaderNode {

	var inputs : Array<ShaderNode.InputInfo>;
	var outputs : Array<ShaderNode.OutputInfo>;

	function getRerouteType() : SgType {
		throw "getRerouteType is not defined for class " + std.Type.getClassName(std.Type.getClass(this));
	}

	override function getInputs() {
		inputs ??= [{name: "", type: getRerouteType(), def: NoDefault}];
		return inputs;
	}

	override function getOutputs() {
		outputs ??= [{name: "", type: getRerouteType()}];
		return outputs;
	}

	override function generate(ctx: NodeGenContext) {
		// Pass the input expression through directly so no extra variable is generated
		var input = ctx.getInput(0);
		if (input != null)
			ctx.setOutput(0, input);
		else
			@:privateAccess ctx.outputs[0] = null;
	}

	override function canHavePreview() : Bool {
		return false;
	}

	#if editor
	override function getInfo() : GraphNodeInfo {
		var info = super.getInfo();
		info.preview = null;
		info.noHeader = true;
		info.width = 20;
		return info;
	}
	#end
}

@name("Reroute Float")
@description("Forward a float or vector unchanged. Used to tidy up the graph")
@group("Other")
class RerouteFloat extends Reroute {
	override function getRerouteType() : SgType return SgGeneric(0, ConstraintFloat);
}

@name("Reroute Sampler")
@description("Forward a texture unchanged. Used to tidy up the graph")
@group("Other")
class RerouteSampler extends Reroute {
	override function getRerouteType() : SgType return SgSampler;
}

@name("Reroute Bool")
@description("Forward a bool unchanged. Used to tidy up the graph")
@group("Other")
class RerouteBool extends Reroute {
	override function getRerouteType() : SgType return SgBool;
}

@name("Reroute Int")
@description("Forward an int unchanged. Used to tidy up the graph")
@group("Other")
class RerouteInt extends Reroute {
	override function getRerouteType() : SgType return SgInt;
}

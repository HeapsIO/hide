package hrt.shgraph.nodes.test;

@name("NewSampler")
@description("New add, if this is in the final build come bonk Clement Espeute on the head plz")
@group("Property")
@color("#0e8826")
class NewSampler extends ShaderNode {

	override function generate(ctx: NodeGenContext) {
		var time = ctx.getGlobalInput(Time);
		var sampler = ctx.getInput(0);
		var uv = ctx.getInput(1) ?? ctx.getGlobalInput(CalculatedUV);
		var outExpr : TExpr = null;

		if (sampler != null) {
			outExpr = makeGlobalCall(Texture, [sampler, uv], TVec(4, VFloat));
		}
		else {
			outExpr = makeVec([1.0,0.0,1.0,1.0]);
		}

		ctx.setOutput(0, outExpr);
		ctx.addPreview(outExpr);
	}

	override function getInputs() : Array<ShaderNode.InputInfo> {
		static var i = [
			{name: "texture", type: SgSampler},
			{name: "uv", type: SgFloat(2)},
		];
		return i;
	}

	override function getOutputs() : Array<ShaderNode.OutputInfo> {
		static var o = [{name: "rgba", type: SgFloat(4)}];
		return o;
	}

}
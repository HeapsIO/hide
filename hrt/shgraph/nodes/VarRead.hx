package hrt.shgraph.nodes;


@name("Read Var")
@description("Read a value from a local variable")
@width(80)
@group("Variables")
class VarRead extends ShaderNode {
	@prop() public var varId : Int = 0;

	var outputs: Array<ShaderNode.OutputInfo>;
	override public function getOutputs() : Array<ShaderNode.OutputInfo> {
		if (outputs == null) {
			outputs  = [{name: "output", type: SgFloat(4)}];
		}
		return outputs;
	}

	override function generate(ctx:NodeGenContext) {
		var out = AstTools.makeVar(ctx.getLocalTVar("_sg_var_write", TVec(4, VFloat)));
		ctx.setOutput(0, out);
		#if editor
		ctx.addPreview(out);
		#end
	}

	#if editor
	override function getInfo():hide.view.GraphInterface.GraphNodeInfo {
		var info = super.getInfo();
		info.name = "Read: " + @:privateAccess (cast editor.editor: hide.view.shadereditor.ShaderEditor).currentGraph.variables[varId].name;
		return info;
	}
	#end
}
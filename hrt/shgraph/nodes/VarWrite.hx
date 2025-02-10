package hrt.shgraph.nodes;

@name("Write Var")
@description("Write a value to a local variable")
@width(130)
@group("Variables")
class VarWrite extends ShaderVar {

	public function new() {
	}

	var inputs: Array<ShaderNode.InputInfo>;
	override public function getInputs() : Array<ShaderNode.InputInfo> {
		if (inputs == null) {
			inputs = [{name: "input", type: graph.variables[varId].type}];
		}
		return inputs;
	}

	override function generate(ctx:NodeGenContext) {
		var input = ctx.getInput(0);
		var tVar = ctx.getLocalTVar(varId, input);
		ctx.addPreview(AstTools.makeVar(tVar));
	}

	#if editor
	override function getInfo():hide.view.GraphInterface.GraphNodeInfo {
		var info = super.getInfo();
		if (editor != null) {
			info.name = "Write: " + @:privateAccess (cast editor.editor: hide.view.shadereditor.ShaderEditor).currentGraph.variables[varId].name;
		}
		return info;
	}
	#end
}
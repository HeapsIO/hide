package hrt.shgraph;

using hxsl.Ast;
import hrt.shgraph.ShaderGraph.SgType;

@name("Parameter")
@width(120)
@color("#d6d6d6")
class ShaderParam extends ShaderNode {
	@prop() public var parameterId : Int;
	@prop() public var perInstance : Bool;

	public function new() {

	}

	override function getOutputs() : Array<ShaderNode.OutputInfo> {
		var variable = getVariable();
		var t = isGeneric() ? SgGeneric(0, ShaderGraph.ConstraintFloat) : ShaderGraph.typeToSgType(variable.type);
		return [{name: variable.name, type: t}];
	}

	override function generate(ctx: NodeGenContext) {
		var variable = getVariable();
		var v = ctx.getGlobalParam(variable.name, variable.type);

		// The type of a generic parameter is the type of the expression given by the parent graph
		if (isGeneric())
			@:privateAccess ctx.genericTypes[0] = v?.t;

		ctx.setOutput(0, v);
		switch(v?.t) {
			case TSampler(_,_):
				var uv = ctx.getGlobalInput(CalculatedUV);
				var sample = AstTools.makeGlobalCall(Texture, [v, uv], TVec(4, VFloat));
				ctx.addPreview(sample);
			default:
				ctx.addPreview(v);
		}
	}

	function getVariable() : TVar {
		return graph.parent.getParameter(parameterId).variable;
	}

	function isGeneric() : Bool {
		return graph.parent.getParameter(parameterId).generic ?? false;
	}

	override public function loadProperties(props : Dynamic) {
		parameterId = Reflect.field(props, "parameterId");
		perInstance = Reflect.field(props, "perInstance");
	}

	override public function saveProperties() : Dynamic {
		var parameters = {
			parameterId: parameterId,
			perInstance: perInstance
		};

		return parameters;
	}

	#if editor
	override function getInfo():hide.view.GraphInterface.GraphNodeInfo {
		var info = super.getInfo();

		info.contextMenu = (e: js.html.MouseEvent) -> {
			hide.comp.ContextMenu.createFromEvent(e, [
				{label: "Show in Parameters list", click: () -> {
					(cast editor.editor: hide.view.shadereditor.ShaderEditor).revealParameter(parameterId);
				}},
			]);
		}
		return info;
	}
	#end
}
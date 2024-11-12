package hrt.shgraph;

using hxsl.Ast;

@name("Parameter")
@width(120)
@color("#d6d6d6")
class ShaderParam extends ShaderNode {
	@prop() public var parameterId : Int;
	@prop() public var perInstance : Bool;

	public var shaderGraph : ShaderGraph;

	public function new() {

	}

	override function getOutputs() : Array<ShaderNode.OutputInfo> {
		var variable = getVariable();
		var t = switch(variable.type) {
			case TFloat:
				SgFloat(1);
			case TVec(n, _):
				SgFloat(n);
			case TSampler(_,_):
				SgSampler;
			default:
				throw "Unhandled var type " + variable.type;
		}
		return [{name: variable.name, type: t}];
	}

	override function generate(ctx: NodeGenContext) {
		var variable = getVariable();
		var v = ctx.getGlobalParam(variable.name, variable.type);

		ctx.setOutput(0, v);
		if (v.t.match(TSampler(_,_))) {
			var uv = ctx.getGlobalInput(CalculatedUV);
			var sample = AstTools.makeGlobalCall(Texture, [v, uv], TVec(4, VFloat));
			ctx.addPreview(sample);
		}
		else {
			ctx.addPreview(v);
		}
	}

	function getVariable() : TVar {
		return shaderGraph.getParameter(parameterId).variable;
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
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
		if (graph.parent.getParameter(parameterId) == null)
			return [{name: "error", type: SgBool}];
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
		var p = graph.parent.getParameter(parameterId);
		if (p == null)
			throw 'Missing parameter $parameterId';
		return p.variable;
	}

	function isGeneric() : Bool {
		return graph.parent.getParameter(parameterId)?.generic ?? false;
	}

	static function getTypeName(p: ShaderGraph.Parameter) : String {
		return p.generic == true ? "generic" : Std.string(p.type);
	}

	override public function serializeToDynamic(forClipboard: Bool = false) : Dynamic {
		var data = super.serializeToDynamic(forClipboard);
		var p = graph.parent.getParameter(parameterId);
		if (forClipboard && p != null) {
			data.parameterName = p.name;
			data.parameterType = getTypeName(p);
		}
		return data;
	}

	override public function unserializeFromDynamic(data: Dynamic, forClipboard: Bool = false) : Void {
		super.unserializeFromDynamic(data, forClipboard);
		if (forClipboard) {
			var p = Lambda.find(graph.parent.parametersAvailable, (p) -> p.name == data.parameterName);
			if (p == null)
				throw 'Missing parameter "${data.parameterName}"';
			if (getTypeName(p) != data.parameterType)
				throw 'Parameter "${p.name}" has a different type';
			parameterId = p.id;
		}
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

		info.contextMenu = () -> [
			{label: "Show in Parameters list", click: () -> {
				(cast editor.editor: hide.view.shadereditor.ShaderEditor).revealParameter(parameterId);
			}},
		];
		return info;
	}
	#end
}
package hrt.shgraph.nodes;

abstract class ShaderVar extends ShaderNode {
	@prop() public var varId : Int = 0;

	override public function serializeToDynamic(forClipboard: Bool = false) : Dynamic {
		var data = super.serializeToDynamic(forClipboard);
		var v = graph.parent.variables[varId];
		if (forClipboard && v != null) {
			data.varName = v.name;
			data.varType = ShaderGraph.serializeSgType(v.type);
		}
		return data;
	}

	override public function unserializeFromDynamic(data: Dynamic, forClipboard: Bool = false) : Void {
		super.unserializeFromDynamic(data, forClipboard);
		if (forClipboard) {
			var v = Lambda.find(graph.parent.variables, (v) -> v.name == data.varName);
			if (v == null)
				throw 'Missing variable "${data.varName}"';
			if (ShaderGraph.serializeSgType(v.type) != data.varType)
				throw 'Variable "${v.name}" has a different type';
			varId = graph.parent.variables.indexOf(v);
		}
	}

	#if editor
	override function getInfo():hide.view.GraphInterface.GraphNodeInfo {
		var info = super.getInfo();

		info.contextMenu = () -> [
			{label: "Show in Variable list", click: () -> {
				(cast editor.editor: hide.view.shadereditor.ShaderEditor).revealVariable(varId);
			}},
		];
		return info;
	}
	#end
}
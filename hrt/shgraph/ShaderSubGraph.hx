package hrt.shgraph;

using Lambda;
import hrt.shgraph.ShaderGraph;

typedef SubGraphOutput = {
	name : String,
	type : SgType,
	id : Int,
	index : Int,
};

/**
	Shader graph included in other graphs by SubGraph nodes. Has a single graph, not bound to a domain.
**/
@:prefabHideInAddMenu
class ShaderSubGraph extends ShaderGraph {

	public var subGraphOutputs : Map<Int, SubGraphOutput> = [];
	var currentOutputId = 0;

	static var _ = hrt.prefab.Prefab.register("subgraph", hrt.shgraph.ShaderSubGraph, "subgraph");

	override public function load(json : Dynamic) : Void {
		// Outputs must exist before the nodes referencing them are loaded
		subGraphOutputs = [];
		var outputs : Array<Dynamic> = json.outputs ?? [];
		outputs.sort((a, b) -> Reflect.compare(a.index, b.index));
		for (i => o in outputs) {
			subGraphOutputs.set(o.id, {name: o.name, type: unserializeSgType(o.type), id: o.id, index: i});
			currentOutputId = hxd.Math.imax(currentOutputId, o.id + 1);
		}

		super.load(json);
	}

	override public function copy(other: hrt.prefab.Prefab) : Void {
		super.copy(other);
	}

	override function save() {
		var json = super.save();
		Reflect.setField(json, "outputs", [
			for (i => o in getSortedOutputs()) { id : o.id, name : o.name, type : serializeSgType(o.type), index : i }
		]);
		return json;
	}

	override function loadGraphs(json : Dynamic) {
		var graph = new Graph(this, Fragment);
		if (json.graph != null)
			graph.load(json.graph);
		graphs.push(graph);
	}

	override function saveGraphs(json : Dynamic) {
		if (graphs.length > 0)
			json.graph = graphs[0].saveToDynamic();
	}

	override public function getGraph(domain : Domain) {
		return graphs[0];
	}

	override function createNodeGenContext() : NodeGenContext {
		return new NodeGenContext.NodeGenContextSubGraph(null, null);
	}

	public function getSortedParameters() : Array<Parameter> {
		var params = parametersAvailable.array();
		params.sort((a, b) -> Reflect.compare(a.index, b.index));
		return params;
	}

	public function getSortedOutputs() : Array<SubGraphOutput> {
		var outputs = subGraphOutputs.array();
		outputs.sort((a, b) -> Reflect.compare(a.index, b.index));
		return outputs;
	}
}

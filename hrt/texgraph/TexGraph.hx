package hrt.texgraph;

typedef Edge = {
	?inputNodeId : Int,
	?nameInput : String, // Fallback if name has changed
	?inputId : Int,
	?outputNodeId : Int,
	?nameOutput : String, // Fallback if name has changed
	?outputId : Int,
};

typedef Connection = {
	from : TexNode,
	outputId : Int,
};

class TexGraph extends hrt.prefab.Prefab {
	public static var CURRENT_NODE_ID = 0;

	public var cachedOutputs : Map<Int, Array<h3d.mat.Texture>> = [];
	public var nodes : Map<Int, TexNode> = [];

	// Base parameters that can be overrided by nodes
	@:s public var outputHeight = 256;
	@:s public var outputWidth = 256;
	@:s public var outputFormat = hxd.PixelFormat.RGBA;

	override function save() {
		var json = super.save();
		Reflect.setField(json, "graph", saveToDynamic());
		return json;
	}

	override function load(json : Dynamic) : Void {
		super.load(json);

		nodes = [];
		CURRENT_NODE_ID = 0;

		var graphJson = Reflect.getProperty(json, "graph");

		var nodesJson : Array<Dynamic> = Reflect.getProperty(graphJson, "nodes");
		for (n in nodesJson) {
			var node = TexNode.createFromDynamic(n, this);
			this.nodes.set(node.id, node);
			CURRENT_NODE_ID = hxd.Math.imax(CURRENT_NODE_ID, node.id+1);
		}

		var edgesJson : Array<Dynamic> = Reflect.getProperty(graphJson, "edges");
		for (e in edgesJson) {
			addEdge(e);
		}
	}

	override function copy(other: hrt.prefab.Prefab) : Void {
		throw "Texture graph is not meant to be put in a prefab tree. Use a dynamic shader that references this shadergraph instead";
	}

	public function saveToDynamic() : Dynamic {
		var edgesJson : Array<Edge> = [];
		for (n in nodes) {
			for (inputId => connection in n.connections) {
				if (connection == null) continue;
				var outputId = connection.outputId;
				edgesJson.push({ outputNodeId: connection.from.id, nameOutput: connection.from.getOutputs()[outputId].name, inputNodeId: n.id, nameInput: n.getInputs()[inputId].name, inputId: inputId, outputId: outputId });
			}
		}

		var json = {
			nodes: [
				for (n in nodes) n.serializeToDynamic(),
				],
				edges: edgesJson
			};

		return json;
	}

	public function saveToText() : String {
		return haxe.Json.stringify(save(), "\t");
	}


	public function addEdge(edge : Edge) {
		var node = this.nodes.get(edge.inputNodeId);
		var output = this.nodes.get(edge.outputNodeId);

		var inputs = node.getInputs();
		var outputs = output.getOutputs();

		var outputId = edge.outputId;
		var inputId = edge.inputId;

		{
			// Check if there is an output with that id and if it has the same name
			// else try to find the id of another output with the same name
			var output = outputs[outputId];
			if (output == null || output.name != edge.nameOutput) {
				for (id => o in outputs) {
					if (o.name == edge.nameOutput) {
						outputId = id;
						break;
					}
				}
			};
		}

		{
			var input = inputs[inputId];
			if (input == null || input.name != edge.nameInput) {
				for (id => i in inputs) {
					if (i.name == edge.nameInput) {
						inputId = id;
						break;
					}
				}
			}
		}

		node.connections[inputId] = { from: output, outputId: outputId };

		return true;
	}

	public function removeEdge(idNode : Int, inputId : Int, update : Bool = true) {
		var node = this.nodes.get(idNode);
		if (node.connections[inputId] == null) return;

		node.connections[inputId] = null;
	}

	public function hasCycle() {
		var visited : Array<Bool> = [for (n in nodes) false];
		var recStack : Array<Bool> = [for (n in nodes) false];

		function hasCycleUtil(current : Int, visited : Array<Bool>, recStack: Array<Bool>) {
			if (recStack[current])
				return true;

			if (visited[current])
				return false;

			visited[current] = true;
			recStack[current] = true;

			var children: Array<Int> = [];
			for (c in nodes[current].connections) {
				for (idx => n in nodes) {
					if (n == c.from)
						children.push(idx);
				}
			}

			for (idx in children) {
				if (hasCycleUtil(idx, visited, recStack))
					return true;
			}

			recStack[current] = false;
			return false;
		}

		for (idx => n in nodes)
			if (hasCycleUtil(idx, visited, recStack))
				return true;

		return false;
	}

	public function canAddEdge(edge : Edge) {
		var node = this.nodes.get(edge.inputNodeId);
		var output = this.nodes.get(edge.outputNodeId);

		var inputs = node.getInputs();
		var outputs = output.getOutputs();

		// Temp add edge to check for cycle, remove it after
		var prev = node.connections[edge.inputId];
		node.connections[edge.inputId] = {from: output, outputId: edge.outputId};
		var res = hasCycle();
		node.connections[edge.inputId] = prev;

		if(res)
			return false;

		return true;
	}

	public function addNode(texNode : TexNode) {
		this.nodes.set(texNode.id, texNode);
	}

	public function removeNode(idNode : Int) {
		this.nodes.remove(idNode);
	}

	public function getOutputNodes() : Array<hrt.texgraph.nodes.TexOutput> {
		var outputNodes : Array<hrt.texgraph.nodes.TexOutput> = [];
		for (n in nodes) {
			if (Std.downcast(n, hrt.texgraph.nodes.TexOutput) != null)
				outputNodes.push(cast n);
		}

		return outputNodes;
	}


	public function generate() : Map<String, h3d.mat.Texture> {
		var engine = h3d.Engine.getCurrent();
		if (engine == null)
			return null;

		cachedOutputs = [];

		function generateNode(node : TexNode) {
			for (c in node.connections) {
				if (c != null && cachedOutputs.get(c.from.id) == null)
					generateNode(c.from);
			}

			// Apply parameters before generation
			node.outputFormat = outputFormat;
			node.outputHeight = outputHeight;
			node.outputWidth = outputWidth;

			for (f in Reflect.fields(node.overrides))
				Reflect.setField(node, f, Reflect.field(node.overrides, f));

			var outputs = node.apply(cachedOutputs);
			cachedOutputs.set(node.id, outputs);
		}

		for (n in nodes) {
			if (cachedOutputs.get(n.id) != null)
				continue;

			generateNode(n);
		}

		var outputs : Map<String, h3d.mat.Texture> = [];
		for (o in getOutputNodes())
			outputs.set(o.label, cachedOutputs.get(o.id)[0]);

		return outputs;
	}

	static var _ = hrt.prefab.Prefab.register("texgraph", TexGraph, "texgraph");
}
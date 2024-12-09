package hrt.animgraph;

typedef Parameter = {
	name: String,
	defaultValue: Float,
};

typedef SerializedEdge = {
	input: Int,
	inputId : Int,
	output: Int,
	outputId: Int,
};
@:access(hrt.animgraph.AnimGraphInstance)
class AnimGraph extends hrt.prefab.Prefab {
	public var instance(default, null) : AnimGraphInstance;

	var nodes: Array<Node> = [];
	var parameters : Array<Parameter> = [];

	#if editor
	var nodeIdCount = 0;
	#end

	override function makeInstance() {
		throw "don't make this";
	}

	/**
		Get the animation "template" for this AnimGraph.
		This anim should be instanciated using getInstance() after that (or use the h3d.scene.Object.playAnimation() function that does this for you)
	**/
	public function getAnimation() : AnimGraphInstance {
		return instance ??= new AnimGraphInstance(this);
	}

	override function save() {
		var json = super.save();

		var nodeIdMapping : Map<{}, Int> = [];

		for (i => node in nodes) {
			nodeIdMapping.set(node, i);
		}

		var serializedNodes : Array<Dynamic> = [];
		var serializedEdges : Array<SerializedEdge> = [];

		for (id => node in nodes) {
			var nodeSer = node.serializeToDynamic();
			serializedNodes.push(nodeSer);


			for (inputId => input in node.inputEdges) {
				if (input == null)
					continue;
				var output = nodeIdMapping.get(input.target);
				if (output == null)
					throw "Invalid output";

				serializedEdges.push({
					input: id,
					inputId: inputId,
					output: output,
					outputId: input.outputIndex,
				});
			}
		}

		json.nodes = serializedNodes;
		json.edges = serializedEdges;
		json.parameters = haxe.Json.parse(haxe.Json.stringify(parameters));

		return json;
	}

	override function load(json: Dynamic) {
		super.load(json);
		nodes = [];
		nodeIdCount = 0;

		var unserializedNodes : Array<Node> = [];
		if (json.nodes != null) {
			for (nodeData in (json.nodes:Array<Dynamic>)) {
				try  {
					var node = Node.createFromDynamic(nodeData);
					node.id = nodeIdCount++;
					unserializedNodes.push(node);
				} catch (e) {
					unserializedNodes.push(null); // keep the serialization index in sync
					#if editor
					hide.Ide.inst.quickError('Missing node type ${nodeData.type} from graph.');
					#else
					throw 'Graph ${this.shared.path} contains unknown node ${nodeData.type}';
					#end
				}
			}
		}

		if (json.edges != null) {
			for (edgeData in (json.edges:Array<SerializedEdge>)) {
				var input = unserializedNodes[edgeData.input];
				if (input == null)
					continue;

				var output = unserializedNodes[edgeData.output];
				if (output == null)
					continue;

				input.inputEdges[edgeData.inputId] = {
					target: output,
					outputIndex: edgeData.outputId,
				};
			}
		}

		for (node in unserializedNodes) {
			if (node != null) {
				this.nodes.push(node);
			}
		}

		if (json.parameters != null) {
			for (parameter in (json.parameters:Array<Dynamic>)) {
				this.parameters.push(parameter);
			}
		}
	}

	override function copy(other: hrt.prefab.Prefab) {
		super.copy(other);
		var other : AnimGraph = cast other;

		var nodeCopy: Map<{}, Node> = [];

		for (id => node in other.nodes) {
			var copy = Node.createFromDynamic(node.serializeToDynamic());
			this.nodes.push(copy);
			nodeCopy.set(node, copy);
		}

		// restore edges
		for (node in other.nodes) {
			var ours = nodeCopy.get(node);
			for (id => edge in node.inputEdges) {
				if (edge == null)
					continue;
				ours.inputEdges[id] = {
					target: nodeCopy.get(edge.target),
					outputIndex: edge.outputIndex,
				};
			}
		}

		this.parameters = haxe.Json.parse(haxe.Json.stringify(other.parameters));
	}

	#if editor
	public function getNodeByEditorId(id: Int) : Node {
		return Lambda.find(nodes, (a) -> a.id == id);
	}
	#end

	static var _ = hrt.prefab.Prefab.register("animgraph", AnimGraph, "animgraph");
}
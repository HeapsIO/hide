package hrt.animgraph;


@:build(hrt.prefab.Macros.buildSerializable())
class Parameter {
	public function new() {};
	@:s public var name: String = null;
	@:s public var defaultValue: Float = 0.0;
	public var runtimeValue = 0.0;
}

typedef SerializedEdge = {
	input: Int,
	inputId : Int,
	output: Int,
	outputId: Int,
};

@:access(hrt.animgraph.AnimGraphInstance)
class AnimGraph extends hrt.prefab.Prefab {

	@:s var animFolder : String; // The folder to use as a base for the animation selection/loading

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
	public function getAnimation(previewNode: hrt.animgraph.nodes.AnimNode = null) : AnimGraphInstance {
		return AnimGraphInstance.fromAnimGraph(this, previewNode);
	}

	override function save() {
		var json = super.save();

		var nodeIdMapping : Map<{}, Int> = [];
		var parametersIdMapping : Map<{}, Int> = [];

		for (i => node in nodes) {
			nodeIdMapping.set(node, i);
		}

		var serializedNodes : Array<Dynamic> = [];
		var serializedEdges : Array<SerializedEdge> = [];
		var serializedParameters : Array<Parameter> = [];

		for (id => parameter in parameters) {
			var serializedParameter = @:privateAccess parameter.copyToDynamic({});
			parametersIdMapping.set(parameter, id);
			serializedParameters[id] = serializedParameter;
		}

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

			var param = Std.downcast(node, hrt.animgraph.nodes.FloatParameter);
			if (param != null) {
				nodeSer.parameter = parametersIdMapping.get(param.parameter);
				if (nodeSer.parameter == null) {
					throw "save impossible";
				}
			}
		}

		json.nodes = serializedNodes;
		json.edges = serializedEdges;
		json.parameters = serializedParameters;

		return json;
	}

	override function load(json: Dynamic) {
		super.load(json);
		nodes = [];
		nodeIdCount = 0;

		var unserializedParameters : Array<Parameter> = [];
		if (json.parameters != null) {
			for (parameter in (json.parameters:Array<Dynamic>)) {
				var copyParameter = new Parameter();
				@:privateAccess copyParameter.copyFromDynamic(parameter);
				unserializedParameters.push(copyParameter);
				copyParameter.runtimeValue = copyParameter.defaultValue;
			}
		}

		parameters = unserializedParameters;

		var unserializedNodes : Array<Node> = [];
		if (json.nodes != null) {
			for (nodeData in (json.nodes:Array<Dynamic>)) {
				try  {
					var node = Node.createFromDynamic(nodeData);
					node.id = nodeIdCount++;
					unserializedNodes.push(node);

					var param = Std.downcast(node, hrt.animgraph.nodes.FloatParameter);
					if (param != null) {
						param.parameter = parameters[nodeData.parameter];
					}
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
	}

	override function copy(other: hrt.prefab.Prefab) {
		load(other.save());
		// super.copy(other);
		// var other : AnimGraph = cast other;

		// var nodeCopy: Map<{}, Node> = [];
		// var parameterCopy: Map<{}, Parameter> = [];

		// this.nodes = [];
		// this.parameters = [];

		// for (parameter in other.parameters) {
		// 	var copy = new Parameter();
		// 	@:privateAccess copy.copyFromOther(parameter);
		// 	this.parameters.push(copy);
		// 	parameterCopy.set(parameter, copy);
		// }

		// for (node in other.nodes) {
		// 	var copy = Node.createFromDynamic(node.serializeToDynamic());
		// 	this.nodes.push(copy);
		// 	nodeCopy.set(node, copy);

		// 	var copyParam = Std.downcast(copy, hrt.animgraph.nodes.FloatParameter);
		// 	var nodeParam = Std.downcast(node, hrt.animgraph.nodes.FloatParameter);
		// 	if (copyParam != null) {
		// 		copyParam.parameter = parameterCopy.get(nodeParam.parameter);
		// 	}
		// }

		// // restore edges
		// for (node in other.nodes) {
		// 	var ours = nodeCopy.get(node);
		// 	for (id => edge in node.inputEdges) {
		// 		if (edge == null)
		// 			continue;
		// 		ours.inputEdges[id] = {
		// 			target: nodeCopy.get(edge.target),
		// 			outputIndex: edge.outputIndex,
		// 		};
		// 	}
		// }

		// this.parameters = haxe.Json.parse(haxe.Json.stringify(other.parameters));
	}

	#if editor
	public function getNodeByEditorId(id: Int) : Node {
		return Lambda.find(nodes, (a) -> a.id == id);
	}
	#end

	static var _ = hrt.prefab.Prefab.register("animgraph", AnimGraph, "animgraph");
}
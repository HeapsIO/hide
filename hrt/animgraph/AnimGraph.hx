package hrt.animgraph;

typedef Parameter = {
	name: String,
	defaultValue: Float,
};
@:access(hrt.animgraph.AnimGraphInstance)
class AnimGraph extends hrt.prefab.Prefab {
	public var instance(default, null) : AnimGraphInstance;

	var nodes: Map<Int, Node> = [];
	var parameters : Array<Parameter> = [];

	#if editor
	var nodeIdCount = 0;
	#end

	override function load(json: Dynamic) {
		super.load(json);
		nodes = [];

		var corruptedNodes : Map<Int,Bool> = [];
		if (json.nodes != null) {
			for (nodeData in (json.nodes:Array<Dynamic>)) {
				try  {
					var node = Node.createFromDynamic(nodeData);
					nodes.set(node.id, node);
					nodeIdCount = hxd.Math.imax(node.id+1, nodeIdCount);
				} catch (e) {
					corruptedNodes.set(nodeData.id, true);
					hide.Ide.inst.quickError('Missing node type ${nodeData.type} from graph.');
				}
			}
		}


		if (json.parameters != null) {
			for (parameter in (json.parameters:Array<Dynamic>)) {
				this.parameters.push(parameter);
			}
		}


		for (node in nodes) {
			var i = node.inputEdges.length-1;
			while (i >= 0) {
				if(corruptedNodes.get(node.inputEdges[i].nodeTarget) != null) {
					node.inputEdges.splice(i, 1);
				}
				i-=1;
			}
		}
	}

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

		json.nodes = [
			for (node in nodes) node.serializeToDynamic()
		];

		json.parameters = haxe.Json.parse(haxe.Json.stringify(parameters));

		return json;
	}

	override function copy(other: hrt.prefab.Prefab) {
		super.copy(other);
		var other : AnimGraph = cast other;
		this.nodes = [
			for (id => node in other.nodes) id => Node.createFromDynamic(node.serializeToDynamic())
		];

		this.parameters = haxe.Json.parse(haxe.Json.stringify(other.parameters));
	}

	static var _ = hrt.prefab.Prefab.register("animgraph", AnimGraph, "animgraph");
}
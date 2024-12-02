package hrt.animgraph;
@:access(hrt.animgraph.AnimGraphInstance)
class AnimGraph extends hrt.prefab.Prefab {
	public var instance(default, null) : AnimGraphInstance;

	var nodes: Map<Int, Node> = [];

	#if editor
	var nodeIdCount = 0;
	#end

	override function load(json: Dynamic) {
		super.load(json);
		nodes = [];

		for (nodeData in (json.nodes:Array<Dynamic>)) {
			var node = Node.createFromDynamic(nodeData);
			nodes.set(node.id, node);
			nodeIdCount = hxd.Math.imax(node.id+1, nodeIdCount);
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

		return json;
	}

	override function copy(other: hrt.prefab.Prefab) {
		super.copy(other);
		var other : AnimGraph = cast other;
		this.nodes = [
			for (id => node in other.nodes) id => Node.createFromDynamic(node.serializeToDynamic())
		];
	}

	static var _ = hrt.prefab.Prefab.register("animgraph", AnimGraph, "animgraph");
}
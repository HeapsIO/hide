package hrt.animgraph;

class AnimGraphAnimatedObject extends h3d.anim.Animation.AnimatedObject {
	public var id : Int;

	public function new (name, id) {
		super(name);
		this.id = id;
	}
}

@:access(hrt.animgraph.AnimGraph)
@:access(hrt.animgraph.Node)
class AnimGraphInstance extends h3d.anim.Animation {
	var animGraph : AnimGraph;
	var outputId : Int = -1;
	var workMatrix = new h3d.Matrix();

	var boneMap: Map<String, Int> = [];

	function new(animGraph:AnimGraph) {
		// Todo : Define a true length for the animation OR make so animations can have an undefined length
		super(animGraph.name, 1000, 1/60.0);
		this.animGraph = animGraph;
		this.outputId = Lambda.find(animGraph.nodes, (node) -> Std.downcast(node, hrt.animgraph.nodes.Output) != null)?.id ?? -1;
	}

	override function clone(?target: h3d.anim.Animation) : h3d.anim.Animation {
		if (target != null) throw "Unexpected";
		var newAnimGraph : AnimGraph = cast animGraph.clone();
		var inst = super.clone(new AnimGraphInstance(newAnimGraph));
		return inst;
	}

	public function getBones(ctx : hrt.animgraph.nodes.AnimNode.GetBoneContext) : Map<String, Int> {
		if (outputId == -1)
			return null;

		map(updateNodeInputs);

		var finalNode : hrt.animgraph.nodes.Output = cast animGraph.nodes.get(outputId);
		boneMap = finalNode.a.getBones(ctx);
		return boneMap;
	}

	override function bind(base:h3d.scene.Object) {
		objects = [];

		var ctx = new hrt.animgraph.nodes.AnimNode.GetBoneContext();
		ctx.targetObject = base;

		var bones = getBones(ctx);
		for (name => id in bones) {
			objects.push(new AnimGraphAnimatedObject(name, id));
		}
		super.bind(base);
	}

	override function sync(decompose : Bool = false ) {
		var finalNode : hrt.animgraph.nodes.Output = cast animGraph.nodes.get(outputId);

		for (obj in objects) {
			var obj : AnimGraphAnimatedObject = cast obj;
			workMatrix.identity();
			finalNode.a.getBoneTransform(obj.id, workMatrix);
			@:privateAccess

			var targetMatrix = if (obj.targetSkin != null) {
				obj.targetSkin.jointsUpdated = true;
				obj.targetSkin.currentRelPose[obj.targetJoint] ??= new h3d.Matrix();
			} else {
				obj.targetObject.defaultTransform ??= new h3d.Matrix();
			}

			if (!decompose) {
				decomposeMatrix(workMatrix, targetMatrix);
				if (obj.targetSkin != null) {
					var def = obj.targetSkin.getSkinData().allJoints[obj.targetJoint].defMat;
					targetMatrix._41 = def._41;
					targetMatrix._42 = def._42;
					targetMatrix._43 = def._43;
				}
			} else {
				targetMatrix.load(workMatrix);
			}
		}
	}

	static function decomposeMatrix(inMatrix: h3d.Matrix, outMatrix: h3d.Matrix) {
		var quat = inline new h3d.Quat(inMatrix._12, inMatrix._13, inMatrix._21, inMatrix._23);
		inline quat.toMatrix(outMatrix);
	}

	function updateNodeInputs(node: Node) : Void {
		var inputs = node.getInputs();
		for (inputId => edge in node.inputEdges) {
			if (edge == null) continue;
			var outputNode = animGraph.nodes.get(edge.nodeTarget);
			var outputs = outputNode.getOutputs();
			var output = outputs[edge.nodeOutputIndex];
			switch (inputs[inputId].type) {
				case TAnimation:
					Reflect.setField(node, inputs[inputId].name, outputNode);
				case TFloat:
					Reflect.setField(node, inputs[inputId].name, Reflect.getProperty(outputNode, output.name));
			}
		}
	}

	function map(cb: (node:Node) -> Void) {
		function rec (node: Node) {
			cb(node);
			for (inputId => edge in node.inputEdges) {
				if (edge == null) continue;
				var outputNode = animGraph.nodes.get(edge.nodeTarget);
				rec(outputNode);
			}
		}
		var finalNode = animGraph.nodes.get(outputId);
		rec(finalNode);
	}

	override function update(dt:Float):Float {
		var dt2 = super.update(dt);
		if (outputId == -1)
			return dt2;

		for (node in animGraph.nodes) {
			node.tickedThisFrame = false;
		}

		var finalNode : hrt.animgraph.nodes.Output = cast animGraph.nodes.get(outputId);
		tickRec(finalNode, dt);

		return dt2;
	}

	function tickRec(node: hrt.animgraph.Node, dt: Float) {
		var inputs = node.getInputs();

		for (inputId => edge in node.inputEdges) {
			if (edge == null) continue;
			var outputNode = animGraph.nodes.get(edge.nodeTarget);
			if (!outputNode.tickedThisFrame) {
				tickRec(outputNode, dt);
			}
		}

		updateNodeInputs(node);
		node.tick(dt);
		node.tickedThisFrame = true;
	}
}
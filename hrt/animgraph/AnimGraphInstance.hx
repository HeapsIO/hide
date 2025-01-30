package hrt.animgraph;
using Lambda;
using hrt.tools.MapUtils;
class AnimGraphAnimatedObject extends h3d.anim.Animation.AnimatedObject {
	public var id : Int;
	public var matrix : h3d.Matrix;

	public function new (name, id) {
		super(name);
		this.id = id;
		matrix = new h3d.Matrix();
	}
}

typedef AnimResolver = (instance: AnimGraphInstance, target: h3d.scene.Object, path: String ) -> Null<String>;

@:access(hrt.animgraph.AnimGraph)
@:access(hrt.animgraph.Node)
class AnimGraphInstance extends h3d.anim.Animation {
	var rootNode : hrt.animgraph.nodes.AnimNode;

	var boneMap: Map<String, Int> = [];
	var parameterMap: Map<String, hrt.animgraph.AnimGraph.Parameter> = [];

	var target : h3d.scene.Object = null;

	var syncCtx = new hrt.animgraph.nodes.AnimNode.GetBoneTransformContext();
	var defaultPoseNode = new hrt.animgraph.nodes.DefaultPose();

	var resolver : AnimResolver = null;

	var tmpMatrix : h3d.Matrix = new h3d.Matrix();

	#if editor
	var editorSkipClone : Bool = false;
	#end

	static function fromAnimGraph(animGraph:AnimGraph, outputNode: hrt.animgraph.nodes.AnimNode = null, resolver: AnimResolver) : AnimGraphInstance {
		outputNode ??= cast animGraph.nodes.find((node) -> Std.downcast(node, hrt.animgraph.nodes.Output) != null);
		if (outputNode == null)
			throw "Animgraph has no output node";

		var inst = new AnimGraphInstance(outputNode, resolver, animGraph.name, 1000, 1/60.0);
		return inst;
	}

	public function new(rootNode: hrt.animgraph.nodes.AnimNode, resolver: AnimResolver = null, name: String, framesCount: Int, sampling: Float) {
		// Todo : Define a true length for the animation OR make so animations can have an undefined length
		super(name, framesCount, sampling);
		this.rootNode = rootNode;
		this.resolver = resolver ?? defaultResolver;
		defaultPoseNode = new hrt.animgraph.nodes.DefaultPose();
	}

	static function defaultResolver(instance: AnimGraphInstance, target: h3d.scene.Object, path: String) : Null<String> {
		return path;
	}

	public function setParam(name: String, value: Float) {
		var param = parameterMap.get(name);
		if (param != null) {
			param.runtimeValue = value;
		}
	}

	public function getParam(name: String) : Null<Float> {
		return parameterMap.get(name)?.runtimeValue;
	}

	public function resetParam(name: String) {
		var param = parameterMap.get(name);
		if (param != null) {
			param.runtimeValue = param.defaultValue;
		}
	}

	public function resetParams() {
		for (p in parameterMap) {
			p.runtimeValue = p.defaultValue;
		}
	}

	override function clone(?target: h3d.anim.Animation) : h3d.anim.Animation {
		#if editor
		if (editorSkipClone) {
			return this;
		}
		#end
		if (target != null) throw "Unexpected";

		var inst = new AnimGraphInstance(null, resolver, name, frameCount, sampling);
		inst.rootNode = cast cloneRec(rootNode, inst);
		super.clone(inst);
		return inst;
	}

	static function cloneRec(node: hrt.animgraph.Node, inst: AnimGraphInstance) : hrt.animgraph.Node {
		var cloned = hrt.animgraph.Node.createFromDynamic(node.serializeToDynamic());

		var clonedParam = Std.downcast(cloned, hrt.animgraph.nodes.FloatParameter);
		if (clonedParam != null) {
			var nodeParam : hrt.animgraph.nodes.FloatParameter = cast node;
			if (nodeParam.parameter != null) {
				clonedParam.parameter = inst.parameterMap.getOrPut(nodeParam.parameter.name, {
					var newParam = new hrt.animgraph.AnimGraph.Parameter();
					@:privateAccess newParam.copyFromOther(nodeParam.parameter);
					newParam.runtimeValue = nodeParam.parameter.defaultValue;
					newParam;
				});
			}
		}

		for (id => edge in node.inputEdges) {
			if (edge?.target != null) {
				var targetClone = cloneRec(edge.target, inst);
				cloned.inputEdges[id] = {target: targetClone, outputIndex: edge.outputIndex};
			} else {
				cloned.inputEdges[id] = null;
			}
		}
		return cloned;
	}

	public function getBones(ctx : hrt.animgraph.nodes.AnimNode.GetBoneContext) : Map<String, Int> {
		if (rootNode == null)
			return null;

		map(rootNode, updateNodeInputs);

		boneMap = rootNode.getBones(ctx);
		return boneMap;
	}

	override function bind(base:h3d.scene.Object) {
		objects = [];
		target = base;

		var ctx = new hrt.animgraph.nodes.AnimNode.GetBoneContext();
		ctx.targetObject = base;
		ctx.resolver = resolver.bind(this, base);

		var bones = getBones(ctx);
		if (bones != null) {
			for (name => id in bones) {
				objects.push(new AnimGraphAnimatedObject(name, id));
			}
		}
		super.bind(base);
	}

	override function sync(decompose : Bool = false ) {
		if (rootNode == null)
			return;
		for (obj in objects) {
			var obj : AnimGraphAnimatedObject = cast obj;
			var workMatrix = obj.matrix;
			workMatrix.identity();
			syncCtx.reset(obj);

			rootNode.getBoneTransform(obj.id, workMatrix, syncCtx);



			if (!decompose) {
				Tools.recomposeMatrix(workMatrix, tmpMatrix);
				workMatrix.load(tmpMatrix);
				// keep in case if we need the def matrix ???
				// if (obj.targetSkin != null) {
				// 	var def = obj.targetSkin.getSkinData().allJoints[obj.targetJoint].defMat;
				// }
			}

			@:privateAccess
			var targetMatrix = if (obj.targetSkin != null) {
				obj.targetSkin.jointsUpdated = true;
				obj.targetSkin.currentRelPose[obj.targetJoint] = workMatrix;
			} else {
				obj.targetObject.defaultTransform = workMatrix;
			}
		}
	}

	function updateNodeInputs(node: Node) : Void {
		var inputs = node.getInputs();
		for (inputId => edge in node.inputEdges) {
			var outputNode = edge?.target;

			switch (inputs[inputId].type) {
				case TAnimation:
					if (outputNode != null && Std.downcast(outputNode, hrt.animgraph.nodes.DefaultPose) == null /* use our default pose node instead of the one in the graph*/) {
						Reflect.setProperty(node, inputs[inputId].name, outputNode);
					} else {
						Reflect.setProperty(node, inputs[inputId].name, defaultPoseNode);
					}
				case TFloat:
					if (outputNode != null) {
						var outputs = outputNode.getOutputs();
						var output = outputs[edge.outputIndex];
						Reflect.setProperty(node, inputs[inputId].name, Reflect.getProperty(outputNode, output.name));
					}
			}
		}
	}

	function map(root: Node, cb: (node:Node) -> Void) {
		function rec (node: Node) {
			cb(node);
			for (edge in node.inputEdges) {
				if (edge == null) continue;
				rec(edge.target);
			}
		}
		rec(root);
	}

	override function update(dt:Float):Float {
		var dt2 = super.update(dt);
		if (rootNode == null)
			return dt2;

		map(rootNode, (node) -> node.tickedThisFrame = false);
		tickRec(rootNode, dt);

		return dt2;
	}

	function tickRec(node: hrt.animgraph.Node, dt: Float) {
		for (edge in node.inputEdges) {
			if (edge == null) continue;
			var outputNode = edge.target;
			if (!outputNode.tickedThisFrame) {
				tickRec(outputNode, dt);
			}
		}

		updateNodeInputs(node);
		node.tick(dt);
		node.tickedThisFrame = true;
	}

	/**
		Set this function in your project to programaticaly return an animation path
	**/
	static var customAnimResolver : (instance: AnimGraphInstance, name: String) -> Null<String> = null;
}
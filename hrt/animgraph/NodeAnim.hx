package hrt.animgraph;

@:access(AnimNode)
class NodeAnim<T:hrt.animgraph.nodes.AnimNode> extends h3d.anim.Animation {
	public var node: T;
	var resolver: hrt.animgraph.AnimGraphInstance.AnimResolver;
	var modelCache: h3d.prim.ModelCache;
	var syncCtx = new hrt.animgraph.nodes.AnimNode.GetBoneTransformContext();
	var tmpMatrix : h3d.Matrix = new h3d.Matrix();


	public function new(resolver: hrt.animgraph.AnimGraphInstance.AnimResolver, modelCache: h3d.prim.ModelCache) {
		super(null, 100, 1/60);
		this.resolver = resolver;
		this.modelCache = modelCache ?? new h3d.prim.ModelCache();
	}

	override function bind(base) {
		var ctx = new hrt.animgraph.nodes.AnimNode.GetBoneContext();
		ctx.targetObject = base;
		ctx.resolver = resolver.bind(null, base);
		ctx.modelCache = modelCache;
		var bones = node.getBones(ctx);
		if (bones != null) {
			for (name => id in bones) {
				objects.push(new hrt.animgraph.AnimGraphInstance.AnimGraphAnimatedObject(name, id));
			}
		}
		super.bind(base);
	}

	override function sync(decompose:Bool = false) {
		for (obj in objects) {
			var obj : hrt.animgraph.AnimGraphInstance.AnimGraphAnimatedObject = cast obj;
			var workMatrix = obj.matrix;
			workMatrix.identity();

			syncCtx.reset(obj);
			node.getBoneTransform(obj.id, workMatrix, syncCtx);

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

	override function update(dt: Float) : Float {
		var dt2 = super.update(dt);
		node.tick(dt);
		return dt2;
	}
}
package hrt.animgraph;

@:structInit
@:build(hrt.prefab.Macros.buildSerializable())
class BlendSpacePoint {
	@:s public var x : Float = 0.0;
	@:s public var y : Float = 0.0;
	@:s public var speed: Float = 1.0;
	@:s public var animPath: String = null;
	@:s public var keepSync: Bool = true; // If true, the anim will be kept in sync with all the other anims in the graph marked as keepSync
}

class BlendSpace2D extends hrt.prefab.Prefab {
	@:s var points : Array<BlendSpacePoint> = [];
	@:s var animFolder : String = null; // The folder to use as a base for the animation selection/loading

	@:s var minX = -1.0;
	@:s var maxX = 1.0;
	@:s var smoothX = 0.0;

	@:s var minY = -1.0;
	@:s var maxY = 1.0;
	@:s var smoothY = 0.0;

	@:s var scaleSpeedOutOfBound: Bool = false;

	public function makeAnimation(?animSet: Map<String, String>, animCache: h3d.prim.ModelCache) : h3d.anim.BlendSpace2D {
		animSet = animSet ?? [];
		var instPoints : Array<h3d.anim.BlendSpace2D.BlendSpace2DPoint> = [];
		for (point in points) {
			var path = point.animPath;
			path = animSet[path] ?? path;
			if (path == "" || path == null)
				continue;
			var anim = animCache.loadAnimation(hxd.res.Loader.currentInstance.load(path).toModel());
			anim.speed = point.speed;
			instPoints.push(new h3d.anim.BlendSpace2D.BlendSpace2DPoint(point.x, point.y, anim, point.keepSync));
		}

		var blendSpace = new h3d.anim.BlendSpace2D(name, instPoints);

		blendSpace.xSmooth = smoothX;
		blendSpace.ySmooth = smoothY;
		blendSpace.scaleSpeedOutsideOfBounds = scaleSpeedOutOfBound;

		return blendSpace;
	}

	static var _ = hrt.prefab.Prefab.register("blendspace2d", BlendSpace2D, "bs2d");
}
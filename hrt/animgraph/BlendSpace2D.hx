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
	@:s var triangles : Array<Array<Int>> = [];
	@:s var animFolder : String = null; // The folder to use as a base for the animation selection/loading

	@:s var minX = 0.0;
	@:s var maxX = 1.0;
	@:s var smoothX = 0.0;

	@:s var minY = 0.0;
	@:s var maxY = 1.0;
	@:s var smoothY = 0.0;

	@:s var scaleSpeedOutOfBound: Bool = false;


	var instance : BlendSpace2DInstance;

	function getInstance() : BlendSpace2DInstance {
		return instance ??= @:privateAccess new BlendSpace2DInstance(this);
	}

	function triangulate() {
		triangles = [];

		var h2dPoints : Array<h2d.col.Point> = [];
		for (point in points) {
			// normalize x / y in range 0/1 so the triangulation is done in a square
			// this avoid the triangulation failing to create triangles when one axis is far larger than the other

			var x = (point.x - minX) / (maxX - minX);
			var y = (point.y - minY) / (maxY - minY);


			h2dPoints.push(new h2d.col.Point(x, y));
		}

		var triangulation = h2d.col.Delaunay.triangulate(h2dPoints);
		if (triangulation == null)
			return;

		for (triangle in triangulation) {
			triangles.push([h2dPoints.indexOf(triangle.p1), h2dPoints.indexOf(triangle.p2), h2dPoints.indexOf(triangle.p3)]);
		}
	}

	static var _ = hrt.prefab.Prefab.register("blendspace2d", BlendSpace2D, "bs2d");
}

typedef BlendSpaceInstancePoint = {
	x: Float,
	y: Float,
	?animation: h3d.anim.Animation, // Can be null if anim failed to load
	?proxy: hrt.animgraph.nodes.Input.AnimProxy,
}

@:access(hrt.animgraph.BlendSpace2D)
class BlendSpace2DInstance extends h3d.anim.Animation {
	var points : Array<BlendSpaceInstancePoint> = [];
	var triangles : Array<Array<BlendSpaceInstancePoint>> = [];
	var blendSpace : BlendSpace2D;

	function new (blendSpace: BlendSpace2D) {
		super(blendSpace.name, 1000, 1/60.0);
		this.blendSpace = blendSpace;
	}

	override function bind(base: h3d.scene.Object) {
		super.bind(base);

		for (blendSpacePoint in blendSpace.points) {
			var point : BlendSpaceInstancePoint = {x: blendSpacePoint.x, y: blendSpacePoint.y};
			try
			{
				var animBase = hxd.res.Loader.currentInstance.load(blendSpacePoint.animPath).toModel().toHmd().loadAnimation();
				point.proxy = new hrt.animgraph.nodes.Input.AnimProxy(null);
				point.animation = animBase.createInstance(point.proxy);
			} catch (e) {
				trace('Couldn\'t load anim ${blendSpacePoint.animPath} : $e');
			}
			points.push(point);
		}

		for (blendSpaceTriangle in blendSpace.triangles) {
			var ourTriangle : Array<BlendSpaceInstancePoint> = [];
			for (point in blendSpaceTriangle) {
				ourTriangle.push(points[point]);
			}
			triangles.push(ourTriangle);
		}
	}

	override function clone(?target: h3d.anim.Animation) : h3d.anim.Animation {
		if (target != null) throw "Unexpected";
		var newBlendSpace2D : BlendSpace2D = cast blendSpace.clone();
		var inst = super.clone(new BlendSpace2DInstance(newBlendSpace2D));
		return inst;
	}
}
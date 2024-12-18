package hrt.animgraph;

typedef BlendSpacePoint = {
	x : Float,
	y : Float,
	animPath: String,
};

class BlendSpace2D extends hrt.prefab.Prefab {
	@:s var points : Array<BlendSpacePoint> = [];
	@:s var triangles : Array<Array<Int>> = [];
	@:s var refModel : String = null;

	var instance : BlendSpace2DInstance;

	function getInstance() : BlendSpace2DInstance {
		return instance ??= @:privateAccess new BlendSpace2DInstance(this);
	}

	function reTriangulate() {
		triangles = [];

		var h2dPoints : Array<h2d.col.Point> = [];
		for (point in points) {
			h2dPoints.push(new h2d.col.Point(point.x, point.y));
		}

		var triangulation = h2d.col.Delaunay.triangulate(h2dPoints);
		for (triangle in triangulation) {
			triangles.push([h2dPoints.indexOf(triangle.p1), h2dPoints.indexOf(triangle.p2), h2dPoints.indexOf(triangle.p3)]);
		}
	}

	static var _ = hrt.prefab.Prefab.register("blendspace2d", BlendSpace2D, "blendspace2d");
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
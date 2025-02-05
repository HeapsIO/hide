package hrt.animgraph.anim;

@:access(hrt.animgraph.nodes.BlendSpace2D)
class BlendSpace2D extends NodeAnim<hrt.animgraph.nodes.BlendSpace2D> {
	public var x(get, set) : Float;
	public var y(get, set) : Float;
	public var blendSpacePath(get, set) : String;

	public function new(path: String, resolver: hrt.animgraph.AnimGraphInstance.AnimResolver, modelCache: h3d.prim.ModelCache) {
		node = new hrt.animgraph.nodes.BlendSpace2D();
		blendSpacePath = path;
		super(resolver, modelCache);
	}

	override function clone(?a:h3d.anim.Animation):h3d.anim.Animation {
		var a : BlendSpace2D = cast a;
		if (a == null)
			a = new BlendSpace2D(blendSpacePath, resolver, modelCache);
		return super.clone(a);
	}

	function get_x() : Float {
		return node.bsX;
	}

	function set_x(v) : Float {
		return node.bsX = v;
	}

	function get_y() : Float {
		return node.bsY;
	}

	function set_y(v) : Float {
		return node.bsY = v;
	}

	function get_blendSpacePath() : String {
		return node.path;
	}

	function set_blendSpacePath(v) : String {
		return node.path = v;
	}
}
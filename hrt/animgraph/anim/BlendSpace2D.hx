package hrt.animgraph.anim;

@:access(hrt.animgraph.nodes.BlendSpace2D)
class BlendSpace2D extends NodeAnim<hrt.animgraph.nodes.BlendSpace2D> {
	public var x(get, set) : Float;
	public var y(get, set) : Float;
	public var blendSpacePath(get, set) : String;

	function get_x() : Float {
		return instance.bsX;
	}

	function set_x(v) : Float {
		return instance.bsX = v;
	}

	function get_y() : Float {
		return instance.bsY;
	}

	function set_y(v) : Float {
		return instance.bsY = v;
	}

	function get_blendSpacePath() : String {
		return instance.path;
	}

	function set_blendSpacePath(v) : String {
		return instance.path = v;
	}
}
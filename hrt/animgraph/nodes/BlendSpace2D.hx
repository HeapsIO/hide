package hrt.animgraph.nodes;
import hrt.tools.MapUtils;

typedef BlendSpaceInstancePoint = {
	x: Float,
	y: Float,
	speed: Float,
	?animInfo: AnimInfo, // can be null if no animation could be loaded
}

typedef AnimInfo = {
	anim: h3d.anim.Animation,
	proxy: hrt.animgraph.nodes.Input.AnimProxy,
	indexRemap: Array<Null<Int>>,
	keepSync: Bool,
	selfSpeed: Float,
}

@:access(hrt.animgraph.BlendSpace2D)
class BlendSpace2D extends AnimNode {
	@:input var bsX(default, set): Float = 0.5;
	var realX : Float = 0.5;
	var vX : Float = 0.0;

	@:input var bsY(default, set): Float = 0.5;
	var realY : Float = 0.5;
	var vY : Float = 0.0;


	@:s var path : String = "";

	var dirtyPos: Bool = true;

	var prevAnimEventBind : h3d.anim.Animation;

	function set_bsX(v: Float) : Float {
		if (v != bsX)
			currentTriangle = -1;
		return bsX = v;
	}

	function set_bsY(v: Float) : Float {
		if (v != bsY)
			currentTriangle = -1;
		return bsY = v;
	}

	var currentTriangle : Int = -1;
	var weights : Array<Float> = [1.0,0.0,0.0];
	var currentAnimLenght = 1.0;

	var animInfos: Array<AnimInfo> = [];
	var points : Array<BlendSpaceInstancePoint> = [];
	var triangles : Array<Array<BlendSpaceInstancePoint>> = [];
	var blendSpace : hrt.animgraph.BlendSpace2D;

	var workQuat = new h3d.Quat();
	var workQuats : Array<h3d.Quat> = [new h3d.Quat(), new h3d.Quat(), new h3d.Quat()];
	var refQuat = new h3d.Quat();

	function setupAnimEvents() {

	}
}
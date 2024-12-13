package hrt.animgraph;

typedef BlendSpacePoint = {
	x : Float,
	y : Float,
	animPath: String,
};

class BlendSpace2D extends hrt.prefab.Prefab {
	@:s var points : Array<BlendSpacePoint>;

	public function getAnimation() {

	}
}

typedef BlendSpaceInstancePoint = {
	x: Float,
	y: Float,

}

class BlendSpace2DIntance extends h3d.anim.Animation {

}
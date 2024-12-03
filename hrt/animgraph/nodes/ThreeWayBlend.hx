package hrt.animgraph.nodes;

class Blend extends AnimNode {
	@:input var a : AnimNode;
	@:input var b : AnimNode;
	@:input var alpha : Float;

	override function getBoneTransform(boneId:Int, outMatrix:h3d.Matrix) {

	}
}
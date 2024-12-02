package hrt.animgraph.nodes;

/**
	The result of this node can be used as an animation by other systems
**/
class Output extends Node {

	@:input var a: AnimNode;

	override function tick(dt: Float) {
		// update out using inputs
	}

	override function getSize() : Int {
		return Node.SIZE_SMALL;
	}
}
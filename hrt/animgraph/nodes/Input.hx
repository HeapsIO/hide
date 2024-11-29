package hrt.animgraph.nodes;

class Input extends Node {
	@:output var pose: h3d.anim.Animation;

	override function getSize():Int {
		return Node.SIZE_SMALL;
	}
}
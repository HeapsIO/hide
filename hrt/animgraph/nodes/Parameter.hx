package hrt.animgraph.nodes;

class FloatParameter extends Node {
	@:output var value: Float;
	var paramId: Int;

	override function canCreateManually() : Bool {
		return false;
	}
}
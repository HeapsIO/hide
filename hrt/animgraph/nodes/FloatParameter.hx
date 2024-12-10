package hrt.animgraph.nodes;

class FloatParameter extends Node {
	@:output var value: Float;
	public var parameter: hrt.animgraph.AnimGraph.Parameter;

	override function canCreateManually() : Bool {
		return false;
	}

	override function tick(dt: Float) : Void {
		value = parameter.runtimeValue;
	}
}
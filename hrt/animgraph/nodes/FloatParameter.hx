package hrt.animgraph.nodes;

class FloatParameter extends Node {
	@:output var value: Float;
	public var parameter: hrt.animgraph.AnimGraph.Parameter;

	#if editor
	override function canCreateManually() : Bool {
		return false;
	}

	override function getOutputNameOverride(name: String) : String {
		return parameter?.name ?? "undefined";
	}
	#end

	override function tick(dt: Float) : Void {
		value = parameter?.runtimeValue ?? 0;
	}


}
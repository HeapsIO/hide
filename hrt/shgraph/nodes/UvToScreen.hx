package hrt.shgraph.nodes;

using hxsl.Ast;

@name("UV To Screen")
@description("")
@width(100)
@group("Math")
class UvToScreen extends ShaderFunction {

	@input("UV") var uv = SType.Vec2;

	public function new() {
		super(UvToScreen);
	}

	override public function computeOutputs() {
		if (uv != null && !uv.isEmpty())
			addOutput("output", uv.getType());
		else
			removeOutput("output");
	}

}
package hrt.shgraph.nodes;

using hxsl.Ast;

@name("uvToScreen")
@description("")
@width(80)
@group("Math")
class UvToScreen extends ShaderFunction {

	@input("uv") var uv = SType.Vec2;

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
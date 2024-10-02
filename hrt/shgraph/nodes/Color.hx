package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Color")
@description("Color property (static)")
@group("Property")
@width(100)
@noheader()
class Color extends ShaderConst {

	@prop() var r : Float = 0;
	@prop() var g : Float = 0;
	@prop() var b : Float = 0;
	@prop() var a : Float = 1;

	override function getOutputs() {
		static var output : Array<ShaderNode.OutputInfo> = [{name: "output", type: SgFloat(4)}];
		return output;
	}

	override function generate(ctx: NodeGenContext) {
		var expr = makeVec([r,g,b,a]);
		ctx.setOutput(0, expr);
		ctx.addPreview(expr);
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: 47px; height: 35px"></div>');
		var picker = new hide.comp.ColorPicker.ColorBox(element, true, true);


		var start = h3d.Vector.fromArray([r, g, b, a]);
		picker.value = start.toColor();

		picker.onChange = function(move) {
			var vec = h3d.Vector4.fromColor(picker.value);
			r = vec.x;
			g = vec.y;
			b = vec.z;
			a = vec.w;
			requestRecompile();
		};

		elements.push(element);

		return elements;
	}
	#end

}
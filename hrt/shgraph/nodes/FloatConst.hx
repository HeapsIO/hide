package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Value")
@description("Number input (static)")
@group("Property")
@width(100)
@noheader()
class FloatConst extends ShaderConst {

	override function getOutputs() {
		static var output : Array<ShaderNode.OutputInfo> = [{name: "output", type: SgFloat(1)}];
		return output;
	}

	override function generate(ctx: NodeGenContext) : Void {
		var output = makeExpr(TConst(CFloat(value)), TFloat);
		ctx.setOutput(0, output);
		ctx.addPreview(output);
	}

	@prop() var value : Float = 0.;

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: 75px; height: 30px"></div>');
		element.append(new hide.Element('<input type="text" id="value" style="width: ${width*0.5}px" value="${value}" />'));

		var input = element.children("input");
		input.on("keydown", function(e) {
			e.stopPropagation();
		});
		input.on("mousedown", function(e) {
			e.stopPropagation();
		});
		input.on("change", function(e) {
			var tmpValue = Std.parseFloat(input.val());
			if (Math.isNaN(tmpValue) ) {
				input.addClass("error");
			} else {
				this.value = tmpValue;
				input.val(tmpValue);
				input.removeClass("error");
			}
		});

		elements.push(element);

		return elements;
	}
	#end

}
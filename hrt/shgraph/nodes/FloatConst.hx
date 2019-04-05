package hrt.shgraph.nodes;

import hide.Element;
using hxsl.Ast;

@name("Float")
@description("Float input, it's static")
@group("Input")
@width(100)
class FloatConst extends ShaderConst {

	@output() var output = SType.Float;

	@param() var value : Float = 0.5;

	override public function getOutputTExpr(key : String) : TExpr {
		return {
					e: TConst(CFloat(value)),
					p: null,
					t: TFloat
				};
	}

	override public function build(key : String) : TExpr {
		return null;
	}

	#if editor
	override public function getParametersHTML(width : Float) : Array<Element> {
		var elements = super.getParametersHTML(width);
		var element = new Element('<div style="width: 75px; height: 30px"></div>');
		element.append(new Element('<input type="text" id="value" style="width: ${width*0.65}px" value="${value}" />'));

		var input = element.children("input");
		input.on("change", function(e) {
			try {
				value = Std.parseFloat(input.val());
			} catch (e : Dynamic) {

			}
		});

		elements.push(element);

		return elements;
	}
	#end

}
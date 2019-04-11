package hrt.shgraph;

import hide.Element;
import hxsl.*;

using hxsl.Ast;

@name("Param")
@description("Parameters inputs, it's dynamic")
@group("Input")
@noheader()
class ShaderParam extends ShaderNode {

	@output() var output = SType.Variant;

	@prop() public var parameterName : String;

	private var variable : TVar;

	override public function getOutput(key : String) : TVar {
		return variable;
	}

	override public function loadProperties(props : Dynamic) {
		parameterName = Reflect.field(props, "parameterName");
	}

	override public function saveProperties() : Dynamic {
		var parameters = {
			parameterName: parameterName
		};

		return parameters;
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new Element('<div style="width: 110px; height: 30px"></div>');
		element.append(new Element('<select class="variable"></select>'));

		var input = element.children("select");
		input.on("change", function(e) {
			this.variable = input.val();
		});


		elements.push(element);

		return elements;
	}
	#end

}
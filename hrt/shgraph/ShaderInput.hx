package hrt.shgraph;

import hide.Element;
import hxsl.*;

using hxsl.Ast;

@name("Inputs")
@description("Shader inputs of Heaps, it's dynamic")
@group("Input")
@noheader()
@color("#1F690A")
class ShaderInput extends ShaderNode {

	@output() var output = SType.Variant;

	@prop("Variable") public var variable : TVar;

	override public function getOutput(key : String) : TVar {
		return variable;
	}

	override public function build(key : String) : TExpr {
		return null;
	}

	static var availableInputs = [{
						parent: null,
						id: 0,
						kind: Global,
						name: "global.time",
						type: TFloat
					},
					{
						parent: null,
						id: 0,
						kind: Input,
						name: "uv",
						type: TVec(2, VFloat)
					}];

	override public function loadProperties(props : Dynamic) {
		var paramVariable : String = Reflect.field(props, "variable");

		for (c in ShaderNode.availableVariables) {
			if (c.name == paramVariable) {
				this.variable = c;
				return;
			}
		}
		for (c in ShaderInput.availableInputs) {
			if (c.name == paramVariable) {
				this.variable = c;
				return;
			}
		}
	}

	override public function saveProperties() : Dynamic {
		var parameters = {
			variable: variable.name
		};

		return parameters;
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new Element('<div style="width: 110px; height: 30px"></div>');
		element.append(new Element('<select id="variable"></select>'));

		if (this.variable == null) {
			this.variable = ShaderNode.availableVariables[0];
		}
		var input = element.children("select");
		var indexOption = 0;
		for (c in ShaderNode.availableVariables) {
			input.append(new Element('<option value="${indexOption}">${c.name}</option>'));
			if (this.variable.name == c.name) {
				input.val(indexOption);
			}
			indexOption++;
		}
		for (c in ShaderInput.availableInputs) {
			input.append(new Element('<option value="${indexOption}">${c.name}</option>'));
			if (this.variable.name == c.name) {
				input.val(indexOption);
			}
			indexOption++;
		}
		input.on("change", function(e) {
			var value = input.val();
			if (value < ShaderNode.availableVariables.length) {
				this.variable = ShaderNode.availableVariables[value];
			} else {
				this.variable = ShaderInput.availableInputs[value-ShaderNode.availableVariables.length];
			}
		});


		elements.push(element);

		return elements;
	}
	#end

}
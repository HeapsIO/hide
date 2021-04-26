package hrt.shgraph;

using hxsl.Ast;

@name("Global")
@description("Global Inputs")
@group("Property")
@color("#0e8826")
class ShaderGlobalInput extends ShaderInput {

	static public var globalInputs = [	{ parent: null, id: 0, kind: Global, name: "global.time", type: TFloat },
										{ parent: null, id: 0, kind: Global, name: "global.pixelSize", type: TVec(2, VFloat) },
										{ parent: null, id: 0, kind: Global, name: "global.modelView", type: TMat4 },
										{ parent: null, id: 0, kind: Global, name: "global.modelViewInverse", type: TMat4 } ];

	override public function loadProperties(props : Dynamic) {
		var paramVariable : String = Reflect.field(props, "variable");
		for (c in ShaderGlobalInput.globalInputs) {
			if (c.name == paramVariable) {
				this.variable = c;
				return;
			}
		}
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = [];
		var element = new hide.Element('<div style="width: 120px; height: 30px"></div>');
		element.append(new hide.Element('<select id="variable"></select>'));

		if (this.variable == null) 
			this.variable = ShaderGlobalInput.globalInputs[0];
		
		var input = element.children("select");
		var indexOption = 0;
		for (c in ShaderGlobalInput.globalInputs) {
			var name = c.name.split(".")[1];
			input.append(new hide.Element('<option value="${indexOption}">${name}</option>'));
			if (this.variable.name == c.name) {
				input.val(indexOption);
			}
			indexOption++;
		}
		input.on("change", function(e) {
			var value = input.val();
			this.variable = ShaderGlobalInput.globalInputs[value];
		});

		elements.push(element);

		return elements;
	}
	#end

}
package hrt.shgraph;

using hxsl.Ast;

@name("Global")
@description("Global Inputs")
@group("Property")
@color("#0e8826")
class ShaderGlobalInput extends ShaderNode {

	@prop("Variable") public var variable : TVar = globalInputs[0];


	static public var globalInputs = [	{ parent: null, id: 0, kind: Global, name: "global.time", type: TFloat },
										{ parent: null, id: 0, kind: Global, name: "global.pixelSize", type: TVec(2, VFloat) },
										{ parent: null, id: 0, kind: Global, name: "global.modelView", type: TMat4 },
										{ parent: null, id: 0, kind: Global, name: "global.modelViewInverse", type: TMat4 } ];

	override function getShaderDef():hrt.shgraph.ShaderGraph.ShaderNodeDef {
		var pos : Position = {file: "", min: 0, max: 0};

		var inVar : TVar = variable;
		var output : TVar = {name: "output", id:1, type: this.variable.type, kind: Local, qualifiers: [SgOutput]};
		var finalExpr : TExpr = {e: TBinop(OpAssign, {e:TVar(output), p:pos, t:output.type}, {e: TVar(inVar), p: pos, t: output.type}), p: pos, t: output.type};

		return {expr: finalExpr, inVars: [], outVars:[output], externVars: [inVar, output], inits: []};
	}

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
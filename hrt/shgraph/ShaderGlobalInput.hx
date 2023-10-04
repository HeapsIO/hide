package hrt.shgraph;

using hxsl.Ast;

@name("Global")
@description("Global Inputs")
@group("Property")
@color("#0e8826")
class ShaderGlobalInput extends ShaderNode {

	@prop("Variable") public var variableIdx : Int = 0;


	static public var globalInputs = [	{ parent: null, id: 0, kind: Global, name: "global.time", type: TFloat },
										{ parent: null, id: 0, kind: Global, name: "global.pixelSize", type: TVec(2, VFloat) },
										{ parent: null, id: 0, kind: Global, name: "global.modelView", type: TMat4 },
										{ parent: null, id: 0, kind: Global, name: "global.modelViewInverse", type: TMat4 } ];

	override function getShaderDef(domain: ShaderGraph.Domain):hrt.shgraph.ShaderGraph.ShaderNodeDef {
		var pos : Position = {file: "", min: 0, max: 0};

		var inVar : TVar = globalInputs[variableIdx];
		var output : TVar = {name: "output", id:1, type: inVar.type, kind: Local, qualifiers: []};
		var finalExpr : TExpr = {e: TBinop(OpAssign, {e:TVar(output), p:pos, t:output.type}, {e: TVar(inVar), p: pos, t: output.type}), p: pos, t: output.type};

		return {expr: finalExpr, inVars: [], outVars:[{v: output, internal: false}], externVars: [inVar], inits: []};
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = [];
		var element = new hide.Element('<div style="width: 120px; height: 30px"></div>');
		element.append(new hide.Element('<select id="variable"></select>'));

		var input = element.children("select");
		for (indexOption => c in ShaderGlobalInput.globalInputs) {
			var name = c.name.split(".")[1];
			input.append(new hide.Element('<option value="${indexOption}">${name}</option>'));
			if (this.variableIdx == indexOption) {
				input.val(indexOption);
			}
		}
		input.on("change", function(e) {
			var value = input.val();
			this.variableIdx = value;
		});

		elements.push(element);

		return elements;
	}
	#end

}
package hrt.shgraph;

using hxsl.Ast;

@name("Global")
@description("Global Inputs")
@group("Property")
@color("#0e8826")
class ShaderGlobalInput extends ShaderNode {

	@prop("Variable") public var variableIdx : Int = 0;

	static public var globalInputs = [	{display: "Time", v: { parent: null, id: 0, kind: Global, name: "global.time", type: TFloat }},
										{display: "Pixel Size", v: { parent: null, id: 0, kind: Global, name: "global.pixelSize", type: TVec(2, VFloat) }},
										//{display: "Model View", v: { parent: null, id: 0, kind: Global, name: "global.modelView", type: TMat4 }},
										//{display: "Model View Inverse", v: { parent: null, id: 0, kind: Global, name: "global.modelViewInverse", type: TMat4 }}
									];

	public function new(idx: Int) {
		variableIdx = idx;
	}

	override public function getAliases(name: String, group: String, description: String) {
		var aliases = [];
		for (i => input in globalInputs) {
			aliases.push({
				name : name + " - " + input.display,
				group: group,
				description: description,
				args: [i],
			});
		}
		return aliases;
	}

	override function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>):hrt.shgraph.ShaderGraph.ShaderNodeDef {
		var pos : Position = {file: "", min: 0, max: 0};

		var inVar : TVar = Reflect.copy(globalInputs[variableIdx].v);
		inVar.id = getNewIdFn();
		var output : TVar = {name: "output", id: getNewIdFn(), type: inVar.type, kind: Local, qualifiers: []};
		var finalExpr : TExpr = {e: TBinop(OpAssign, {e:TVar(output), p:pos, t:output.type}, {e: TVar(inVar), p: pos, t: output.type}), p: pos, t: output.type};

		return {expr: finalExpr, inVars: [], outVars:[{v: output, internal: false, isDynamic: false}], externVars: [inVar], inits: []};
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = [];
		var element = new hide.Element('<div style="width: 120px; height: 30px"></div>');
		element.append(new hide.Element('<select id="variable"></select>'));

		var input = element.children("select");
		for (indexOption => c in ShaderGlobalInput.globalInputs) {
			var name = c.display;
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
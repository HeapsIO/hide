package hrt.shgraph;

using hxsl.Ast;

@name("Particle Inputs")
@description("Particle specific shader inputs")
@group("Property")
@color("#0e8826")
class ShaderParticleInputs extends ShaderNode {
	@prop("Variable") public var variable : String = "life";

	// override public function getOutput(key : String) : TVar {
	// 	return variable;
	// }

	// override public function build(key : String) : TExpr {
	// 	return null;
	// }

	public function new(variable = "life") {
		this.variable = variable;
	}

	override public function getAliases(name: String, group: String, description: String) {
		var aliases = super.getAliases(name, group, description);
		for (key => input in hrt.shgraph.ShaderParticleInputs.availableInputs) {
			aliases.push({
				nameSearch : name + " - " + input.display,
				group: group,
				description: description,
				args: [key],
			});
		}
		return aliases;
	}


	override function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>):hrt.shgraph.ShaderGraph.ShaderNodeDef {
		var pos : Position = {file: "", min: 0, max: 0};

		var variable : ShaderNode.VariableDecl = availableInputs.get(this.variable);
		if (variable == null)
			throw "Unknown input variable " + this.variable;

		var inVar : TVar = Reflect.copy(variable.v);
		inVar.id = getNewIdFn();
		var output : TVar = {name: "output", id: getNewIdFn(), type: variable.v.type, kind: Local, qualifiers: []};
		var finalExpr : TExpr = {e: TBinop(OpAssign, {e:TVar(output), p:pos, t:output.type}, {e: TVar(inVar), p: pos, t: output.type}), p: pos, t: output.type};

		return {expr: finalExpr, inVars: [{v:inVar, internal: true, isDynamic: false}], outVars:[{v:output, internal: false, isDynamic: false}], externVars: [], inits: []};
	}

	override function loadProperties(props:Dynamic) {
		super.loadProperties(props);
		var ivar : ShaderNode.VariableDecl = availableInputs.get(this.variable);
		if (ivar == null) {
			for (k => v in availableInputs) {
				variable = k;
				break;
			}
		}
	}

	public static var availableInputs : Map<String, ShaderNode.VariableDecl> = [
		"life" => {display: "Particle Life", v: { parent: null, id: 0, kind: Local, name: "particleLife", type: TFloat }},
		"lifetime" => {display: "Particle Life Time", v: { parent: null, id: 0, kind: Local, name: "particleLifeTime", type: TFloat }},
		"random" => {display: "Particle Random", v: { parent: null, id: 0, kind: Local, name: "particleRandom", type: TFloat }},
	];

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: 120px; height: 30px"></div>');
		element.append(new hide.Element('<select id="variable"></select>'));

		if (variable == null) {
			variable = "position";
		}

		var input = element.children("select");
		var indexOption = 0;
		for (k => variable in availableInputs) {
			input.append(new hide.Element('<option value="${k}">${variable.display}</option>'));
		}
		input.val(variable);

		input.on("change", function(e) {
			variable = input.val();
		});

		elements.push(element);

		return elements;
	}
	#end

}
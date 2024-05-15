package hrt.shgraph;

using hxsl.Ast;

enum InputKind {
	IGlobal(g: Variables.Global);
	ICustom(gen:(ctx:NodeGenContext) -> TExpr, t: hxsl.Ast.Type);
}

@name("Inputs")
@description("Shader inputs of Heaps, it's dynamic")
@group("Property")
@color("#0e8826")
class ShaderInput extends ShaderNode {
	@prop("Variable") public var variable : String = "pixelColor";

	public function new(variable = "pixelColor") {
		this.variable = variable;
	}

	var outputs : Array<ShaderNode.OutputInfo>;
	override function getOutputs() {
		if (outputs == null) {
			var global = availableInputs[variable].k;
			var t = switch(global) {
				case IGlobal(g):
					Variables.Globals[g].type;
				case ICustom(_,t):
					t;
			}
			outputs = [{name: "output", type: ShaderGraph.typeToSgType(t)}];
		}
		return outputs;
	}

	override function generate(ctx: NodeGenContext) {
		var expr = switch(availableInputs[variable].k) {
			case IGlobal(g):
				ctx.getGlobalInput(g);
			case ICustom(gen, _):
				gen(ctx);
		}

		ctx.setOutput(0, expr);
		ctx.addPreview(expr);
	}

	override public function getAliases(name: String, group: String, description: String) {
		var aliases = super.getAliases(name, group, description);
		for (key => input in hrt.shgraph.ShaderInput.availableInputs) {
			aliases.push({
				nameSearch : name + " - " + input.display,
				group: group,
				description: description,
				args: [key],
			});
		}
		return aliases;
	}

	override function loadProperties(props:Dynamic) {
		super.loadProperties(props);
		var ivar = availableInputs.get(this.variable);
		if (ivar == null) {
			for (k => v in availableInputs) {
				variable = k;
				break;
			}
		}
	}


	public static var availableInputs : Map<String, {display: String, k: InputKind}> = [
		"pixelColor" => {display: "Pixel Color", k: ICustom((ctx:NodeGenContext) -> makeSwizzle(ctx.getGlobalInput(PixelColor), [X,Y,Z]), TVec(3, VFloat))},
		"alpha" => {display: "Alpha", k: ICustom((ctx:NodeGenContext) -> makeSwizzle(ctx.getGlobalInput(PixelColor), [W]), TFloat)},
		"calculatedUV" => {display: "UV", k: IGlobal(CalculatedUV)},
		"relativePosition" => {display: "Position (Object Space)", k: IGlobal(RelativePosition)},
		"transformedPosition" => {display: "Position (World Space)", k: IGlobal(TransformedPosition)},
		"projectedPosition" => {display: "Position (View Space)", k: IGlobal(ProjectedPosition)},
		"normal" => {display: "Normal (Object Space)", k: IGlobal(Normal)},
		"transformedNormal" => {display: "Normal (World Space)", k: IGlobal(TransformedNormal)},

		"depth" => {display: "Depth", k: IGlobal(Depth)},
		"metalness" => {display: "Metalness", k: IGlobal(Metalness)},
		"roughness" => {display: "Roughness", k: IGlobal(Roughness)},
		"emissive" => {display: "Emissive", k: IGlobal(Emissive)},
		"occlusion" => {display: "Occlusion", k: IGlobal(Occlusion)},

		"uv" => {display: "Source UV", k: IGlobal(UV)},
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
			outputs = null;
			requestRecompile();
		});

		elements.push(element);

		return elements;
	}
	#end

}
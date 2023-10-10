package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Bool")
@description("Boolean input (static)")
@group("Property")
@width(100)
@noheader()
class BoolConst extends ShaderConst {


	@prop() var value : Bool = true;

	override function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>):hrt.shgraph.ShaderGraph.ShaderNodeDef {
		var pos : Position = {file: "", min: 0, max: 0};

		var output : TVar = {name: "output", id: getNewIdFn(), type: TBool, kind: Local, qualifiers: []};
		var finalExpr : TExpr = {e: TBinop(OpAssign, {e:TVar(output), p:pos, t:output.type}, {e: TConst(CBool(value)), p: pos, t: output.type}), p: pos, t: output.type};

		return {expr: finalExpr, inVars: [], outVars:[{v: output, internal: false,  isDynamic: false}], externVars: [], inits: []};
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: 15px; height: 30px"></div>');
		element.append(new hide.Element('<input type="checkbox" id="value" />'));

		var input = element.children("input");
		input.on("change", function(e) {
			value = (input.is(":checked")) ? true : false;
		});
		if (this.value) {
			input.prop("checked", true);
		}

		elements.push(element);

		return elements;
	}
	#end

}
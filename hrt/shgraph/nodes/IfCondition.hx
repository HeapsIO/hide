package hrt.shgraph.nodes;

using hxsl.Ast;

@name("If")
@description("Return the correct input according to the condition")
@group("Condition")
class IfCondition extends ShaderNode {

	@input("condition") var condition = SType.Bool;
	@input("true") var trueVar = SType.Variant;
	@input("false") var falseVar = SType.Variant;

	@output() var output = SType.Variant;

	override public function checkValidityInput(key : String, type : ShaderType.SType) : Bool {

		if (key == "trueVar" && falseVar != null)
			return ShaderType.checkCompatibilities(type, ShaderType.getType(falseVar.getType()));

		if (key == "falseVar" && trueVar != null)
			return ShaderType.checkCompatibilities(type, ShaderType.getType(trueVar.getType()));

		return true;
	}

	override public function createOutputs() {
		if (trueVar != null && falseVar != null)
			addOutput("output", trueVar.getVar(falseVar.getType()).t);
		else if (trueVar != null)
			addOutput("output", trueVar.getType());
		else if (falseVar != null)
			addOutput("output", falseVar.getType());
		else
			removeOutput("output");
	}

	override public function build(key : String) : TExpr {
		return {
			p : null,
			t: output.type,
			e : TBinop(OpAssign, {
					e: TVar(output),
					p: null,
					t: output.type
				}, {
				e: TIf( condition.getVar(),
						trueVar.getVar(falseVar.getType()),
						falseVar.getVar(trueVar.getType())),
				p: null,
				t: output.type
			})
		};
	}

}
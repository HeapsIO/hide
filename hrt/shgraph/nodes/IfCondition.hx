package hrt.shgraph.nodes;

using hxsl.Ast;

@name("If")
@description("Return the correct input according to the condition")
@group("Condition")
class IfCondition extends ShaderNode {

	@input("Condition") var condition = SType.Bool;
	@input("True") var trueVar = SType.Variant;
	@input("False") var falseVar = SType.Variant;

	@output() var output = SType.Variant;

	override public function checkValidityInput(key : String, type : ShaderType.SType) : Bool {

		if (key == "trueVar" && falseVar != null && !falseVar.isEmpty())
			return ShaderType.checkCompatibilities(type, ShaderType.getSType(falseVar.getType()));

		if (key == "falseVar" && trueVar != null && !trueVar.isEmpty())
			return ShaderType.checkCompatibilities(type, ShaderType.getSType(trueVar.getType()));

		return true;
	}

	override public function computeOutputs() {
		if (trueVar != null && !trueVar.isEmpty() && falseVar != null && !falseVar.isEmpty())
			addOutput("output", trueVar.getVar(falseVar.getType()).t);
		else if (trueVar != null && !trueVar.isEmpty())
			addOutput("output", trueVar.getType());
		else if (falseVar != null && !falseVar.isEmpty())
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
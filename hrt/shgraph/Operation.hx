package hrt.shgraph;

import hxsl.*;

using hxsl.Ast;

class Operation extends ShaderNode {

	@input("A") var a = SType.Number;
	@input("B") var b = SType.Number;

	@output() var output = SType.Number;

	var operation : Binop;

	public function new(operation : Binop) {
		this.operation = operation;
	}

	override public function createOutputs() {
		if (a != null && b != null)
			addOutput("output", a.getVar(b.getType()).t);
		else if (a != null)
			addOutput("output", a.getType());
		else if (b != null)
			addOutput("output", b.getType());
		else
			removeOutput("output");
	}

	override public function build(key : String) : TExpr {

		return { e: TBinop(OpAssign, {
						e: TVar(output),
						p: null,
						t: output.type
					}, {
						e: TBinop(operation,
							a.getVar(b.getType()),
							b.getVar(a.getType())),
						p: null,
						t: output.type
					}),
					p: null,
					t: output.type
				};
	}

}
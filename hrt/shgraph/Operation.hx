package hrt.shgraph;

using hxsl.Ast;

class Operation extends ShaderNodeHxsl {

	// @input("A", true) var a = SType.Number;
	// @input("B", true) var b = SType.Number;


	// var operation : Binop;

	// public function new(operation : Binop) {
	// 	this.operation = operation;
	// }

	// override public function computeOutputs() {
	// 	if (a != null && !a.isEmpty() && b != null && !b.isEmpty())
	// 		addOutput("output", a.getVar(b.getType()).t);
	// 	else if (a != null && !a.isEmpty() )
	// 		addOutput("output", a.getType());
	// 	else if (b != null && !b.isEmpty())
	// 		addOutput("output", b.getType());
	// 	else
	// 		removeOutput("output");
	// }

	// override public function build(key : String) : TExpr {

	// 	return { e: TBinop(OpAssign, {
	// 					e: TVar(output),
	// 					p: null,
	// 					t: output.type
	// 				}, {
	// 					e: TBinop(operation,
	// 						a.getVar(b.getType()),
	// 						b.getVar(a.getType())),
	// 					p: null,
	// 					t: output.type
	// 				}),
	// 				p: null,
	// 				t: output.type
	// 			};
	// }

}
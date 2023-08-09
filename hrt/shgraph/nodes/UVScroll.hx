package hrt.shgraph.nodes;

using hxsl.Ast;

@name("UV Scroll")
@description("Scroll UV according to U & V speed")
@group("Specials")
class UVScroll extends ShaderNode {

	// @input("UV") var uv = SType.Vec2;
	// @input("USpeed", true) var uSpeed = SType.Number;
	// @input("VSpeed", true) var vSpeed = SType.Number;


	// var operation : Binop;

	// public function new(operation : Binop) {
	// 	this.operation = operation;
	// }

	// override public function computeOutputs() {
	// 	if (uv != null && !uv.isEmpty())
	// 		addOutput("output", uv.getType());
	// 	else
	// 		removeOutput("output");
	// }

	// override public function build(key : String) : TExpr {

	// 	var globalTime : TVar = @:privateAccess ShaderGlobalInput.globalInputs.filter(i -> i.name.indexOf("time") != -1)[0];
	// 	var timeExpr : TExpr = { e: TVar(globalTime), p: null, t: globalTime.type };

	// 	return { e: TBinop(OpAssign, {
	// 					e: TVar(output),
	// 					p: null,
	// 					t: output.type
	// 				}, {
	// 					// uv % 1 (wrap)
	// 					e: TCall({
	// 						e: TGlobal(Mod),
	// 						p: null,
	// 						t: TFun([
	// 							{
	// 								ret: output.type,
	// 								args: [
	// 									{ name: "uv", type : output.type },
	// 									{ name: "mod", type : TFloat }
	// 								]
	// 							}
	// 						])
	// 					}, [
	// 						{
	// 							// uv + speed * time
	// 							e: TBinop(OpAdd,
	// 								uv.getVar(),
	// 								{
	// 									e: TCall({
	// 										e: TGlobal(Vec2),
	// 										p: null,
	// 										t: TFun([
	// 											{
	// 												ret: output.type,
	// 												args: [
	// 													{ name: "u", type : TFloat },
	// 													{ name: "v", type : TFloat }
	// 												]
	// 											}
	// 										])
	// 									}, [
	// 										// uSpeed * time
	// 										{
	// 											e: TBinop(OpMult,
	// 												uSpeed.getVar(),
	// 												timeExpr),
	// 											p: null,
	// 											t: uSpeed.getType()
	// 										},
	// 										// vSpeed * time
	// 										{
	// 											e: TBinop(OpMult,
	// 												vSpeed.getVar(),
	// 												timeExpr),
	// 											p: null,
	// 											t: vSpeed.getType()
	// 										}
	// 									]
	// 									),
	// 									p: null,
	// 									t: output.type
	// 								}),
	// 							p: null,
	// 							t: uSpeed.getType()
	// 						},
	// 						{
	// 							e: TConst(CFloat(1)),
	// 							p: null,
	// 							t: TFloat
	// 						}
	// 					]),
	// 					p: null,
	// 					t: output.type
	// 				}),
	// 				p: null,
	// 				t: output.type
	// 			};
	// }

}
package hrt.shgraph;

enum ShaderDefInput {
	Var(name: String);
	Const(intialValue: Float);
	ConstBool(initialValue: Bool);
}

enum SgHxslVar {
	SgInput(isDynamic: Bool, defaultValue: ShaderDefInput);
	SgConst;
	SgOutput(isDynamic: Bool);
}
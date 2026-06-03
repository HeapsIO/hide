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
	SgInit; // @sginit : Make sure the variable is initialized in the __init__ part of the shader in case it's not assigned by a previous shader
}
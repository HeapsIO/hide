package hrt.shgraph;

using hxsl.Ast;

class NodeVar {

	public var node : ShaderNode;
	public var keyOutput : String;

	public function new ( n : ShaderNode, key : String ) {
		node = n;
		keyOutput = key;
	}

	public function getKey() : String {
		return keyOutput;
	}

	public function getTVar() {
		return node.getOutput(keyOutput);
	}

	public function getType() : Type {
		return node.getOutputType(keyOutput);
	}

	public function isEmpty() {
		return node.getOutputTExpr(keyOutput) == null;
	}

	public function getVar(?type: Type) : TExpr {
		var currentType = getType();
		if (type == null || currentType == type) {
			return node.getOutputTExpr(keyOutput);
		}

		switch(currentType) {
			case TBool:
				var tExprBool = node.getOutputTExpr(keyOutput);
				switch(type) {
					case TVec(size, VBool):
						if (size == 2) {
							return {
								e: TCall({
									e: TGlobal(Vec2),
									p: null,
									t: TFun([
										{
											ret: type,
											args: [
											{ name: "u", type : TBool },
											{ name: "v", type : TBool }]
										}
									])
								}, [tExprBool,
									tExprBool]),
								p: null,
								t: type
							};
						} else if (size == 3) {
							return {
								e: TCall({
									e: TGlobal(Vec3),
									p: null,
									t: TFun([
										{
											ret: type,
											args: [
											{ name: "x", type : TBool },
											{ name: "y", type : TBool },
											{ name: "z", type : TBool }]
										}
									])
								}, [tExprBool,
									tExprBool,
									tExprBool]),
								p: null,
								t: type
							};
						} else {
							return {
								e: TCall({
									e: TGlobal(Vec4),
									p: null,
									t: TFun([
										{
											ret: type,
											args: [
											{ name: "r", type : TBool },
											{ name: "g", type : TBool },
											{ name: "b", type : TBool },
											{ name: "a", type : TBool }]
										}
									])
								}, [tExprBool,
									tExprBool,
									tExprBool,
									tExprBool]),
								p: null,
								t: type
							};
						}
					default:
				};
			case TFloat:
				var tExprFloat = node.getOutputTExpr(keyOutput);
				switch(type) {
					case TVec(size, VFloat):
						if (size == 2) {
							return {
								e: TCall({
									e: TGlobal(Vec2),
									p: null,
									t: TFun([
										{
											ret: type,
											args: [
											{ name: "u", type : TFloat },
											{ name: "v", type : TFloat }]
										}
									])
								}, [tExprFloat,
									tExprFloat]),
								p: null,
								t: type
							};
						} else if (size == 3) {
							return {
								e: TCall({
									e: TGlobal(Vec3),
									p: null,
									t: TFun([
										{
											ret: type,
											args: [
											{ name: "x", type : TFloat },
											{ name: "y", type : TFloat },
											{ name: "z", type : TFloat }]
										}
									])
								}, [tExprFloat,
									tExprFloat,
									tExprFloat]),
								p: null,
								t: type
							};
						} else {
							return {
								e: TCall({
									e: TGlobal(Vec4),
									p: null,
									t: TFun([
										{
											ret: type,
											args: [
											{ name: "r", type : TFloat },
											{ name: "g", type : TFloat },
											{ name: "b", type : TFloat },
											{ name: "a", type : TFloat }]
										}
									])
								}, [tExprFloat,
									tExprFloat,
									tExprFloat,
									{
										e: TConst(CFloat(1.0)),
										p: null,
										t: TFloat
									}]),
								p: null,
								t: type
							};
						}
					default:
				};
			case TVec(sizeCurrentType, VFloat):
				var tExprFloat = node.getOutputTExpr(keyOutput);
				if (sizeCurrentType == 2) {
					switch(type) {
						case TVec(size, VFloat):
							if (size == 3) {
								return {
									e: TCall({
										e: TGlobal(Vec3),
										p: null,
										t: TFun([
											{
												ret: type,
												args: [
												{ name: "x", type : TFloat },
												{ name: "y", type : TFloat },
												{ name: "z", type : TFloat }]
											}
										])
									}, [{
											e: TSwiz(tExprFloat, [X]),
											p: null,
											t: TVec(1, VFloat)
										},
										{
											e: TSwiz(tExprFloat, [Y]),
											p: null,
											t: TVec(1, VFloat)
										},
										{
											e: TConst(CFloat(0.0)),
											p: null,
											t: TFloat
										}]),
									p: null,
									t: type
								};
							} else if (size == 4) {
								return {
									e: TCall({
										e: TGlobal(Vec4),
										p: null,
										t: TFun([
											{
												ret: type,
												args: [
												{ name: "r", type : TFloat },
												{ name: "g", type : TFloat },
												{ name: "b", type : TFloat },
												{ name: "a", type : TFloat }]
											}
										])
									}, [{
											e: TSwiz(tExprFloat, [X]),
											p: null,
											t: TVec(1, VFloat)
										},
										{
											e: TSwiz(tExprFloat, [Y]),
											p: null,
											t: TVec(1, VFloat)
										},
										{
											e: TConst(CFloat(0.0)),
											p: null,
											t: TFloat
										},
										{
											e: TConst(CFloat(0.0)),
											p: null,
											t: TFloat
										}]),
									p: null,
									t: type
								};
							}
						default:
					};
				} else if (sizeCurrentType == 3) {
					switch(type) {
						case TVec(size, VFloat):
							if (size == 4) {
								return {
									e: TCall({
										e: TGlobal(Vec4),
										p: null,
										t: TFun([
											{
												ret: type,
												args: [
												{ name: "r", type : TFloat },
												{ name: "g", type : TFloat },
												{ name: "b", type : TFloat },
												{ name: "a", type : TFloat }]
											}
										])
									}, [{
											e: TSwiz(tExprFloat, [X]),
											p: null,
											t: TVec(1, VFloat)
										},
										{
											e: TSwiz(tExprFloat, [Y]),
											p: null,
											t: TVec(1, VFloat)
										},
										{
											e: TSwiz(tExprFloat, [Z]),
											p: null,
											t: TVec(1, VFloat)
										},
										{
											e: TConst(CFloat(0.0)),
											p: null,
											t: TFloat
										}]),
									p: null,
									t: type
								};
							}
						default:
					};
				}

			default:
		}
		return node.getOutputTExpr(keyOutput);
	}

	public function getExpr() : Array<TExpr> {
		if (node.outputCompiled.get(keyOutput) != null)
			return [];
		node.outputCompiled.set(keyOutput, true);
		var res = [];
		var nodeBuild = node.build(keyOutput);
		if (getTVar() != null && getTVar().kind == Local)
			res.push({ e : TVarDecl(getTVar()), t : getType(), p : null });
		if (nodeBuild != null)
			res.push(nodeBuild);
		return res;
	}

}
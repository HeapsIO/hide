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
		return null;//node.getOutput(keyOutput);
	}

	public function getType() : Type {
		return TVoid;//node.getOutputType(keyOutput);
	}

	public function isEmpty() {
		return true;//node.getOutputTExpr(keyOutput) == null;
	}

	public function getVar(?type: Type) : TExpr {
		var currentType = getType();
		if (type == null || currentType == type) {
			return null;//node.getOutputTExpr(keyOutput);
		}

		return null;
	}

	public function getExpr() : Array<TExpr> {
		if (node.outputCompiled.get(keyOutput) != null)
			return [];
		node.outputCompiled.set(keyOutput, true);
		var res = [];
		var nodeBuild = node.build(keyOutput);
		var tvar = getTVar();
		if (tvar != null && tvar.kind == Local && ShaderInput.availableInputs.indexOf(tvar) < 0)
			res.push({ e : TVarDecl(getTVar()), t : getType(), p : null });
		if (nodeBuild != null)
			res.push(nodeBuild);
		return res;
	}

}
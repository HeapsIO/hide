package hrt.shgraph;

using hxsl.Ast;


class AstTools {

	public static var defPos : Position = {file: "", min: 0, max: 0};

	public inline static function makePos() : Position {
		return {file: "", min: 0, max: 0};
	}

	public inline static function makeIf(cond: TExpr, inner: TExpr, ?other: TExpr, ?pos: Position, type: Type = TVoid) : TExpr {
		return makeExpr(
			TIf(
				cond,
				inner,
				other
			),
			type,
			pos ?? defPos,
		);
	}

	public inline static function makeAssign(to: TExpr, from: TExpr) : TExpr {
		return makeExpr(TBinop(OpAssign, to, from), to.t);
	}

	public inline static function makeInt(int: Int) : TExpr {
		return makeExpr(TConst(CInt(int)), TInt);
	}

	public inline static function makeFloat(float: Float) : TExpr {
		return makeExpr(TConst(CFloat(float)), TFloat);
	}

	public inline static function makeVec(values : Array<Float>) : TExpr {
		var ctor = switch(values.length) {
			case 2: Vec2;
			case 3: Vec3;
			case 4: Vec4;
			default: throw "Can't create a vector of size " + values.length;
		}
		var params = [for (v in values) makeExpr(TConst(CFloat(v)), TFloat)];
		return makeExpr(TCall(makeExpr(TGlobal(ctor), TVoid), params), TVec(values.length, VFloat));
	}

	public inline static function makeVecExpr(values: Array<TExpr>) : TExpr {
		var ctor = switch(values.length) {
			case 2: Vec2;
			case 3: Vec3;
			case 4: Vec4;
			default: throw "Can't create a vector of size " + values.length;
		}
		return makeExpr(TCall(makeExpr(TGlobal(ctor), TVoid), values), TVec(values.length, VFloat));
	}

	public inline static function makeVar(v: TVar, ?pos: Position) : TExpr {
		return makeExpr(TVar(v), v.type, pos);
	}

	public inline static function makeExpr(def: TExprDef, type: Type, ?pos: Position) : TExpr {
		return {e: def, p: (pos ?? defPos), t: type}
	}

	// Expect a.t == b.t
	public inline static function makeBinop(a: TExpr, op: Binop, b: TExpr) : TExpr {
		return makeExpr(TBinop(op, a, b), a.t);
	}

	public inline static function makeEq(a: TExpr, b: TExpr) : TExpr {
		return makeExpr(TBinop(OpEq, a, b), TBool);
	}
}
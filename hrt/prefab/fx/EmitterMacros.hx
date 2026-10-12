package hrt.prefab.fx;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

enum ParamKind {
	KScalar;
	KVec( n : Int );
	KEnum( e : Expr );
	KGradient;
}

typedef Param = {
	var name : String;
	var kind : ParamKind;
	var def : Expr;
	var pos : Position;
}
#end

class EmitterMacros {

	#if macro

	static function metaObj( f : Field, name : String ) : Null<Array<ObjectField>> {
		if( f.meta == null )
			return null;
		for( m in f.meta )
			if( m.name == name ) {
				if( m.params.length != 1 )
					Context.error(name + " expects one object argument", m.pos);
				return switch( m.params[0].expr ) {
					case EObjectDecl(fl): fl;
					default: Context.error(name + " expects an object argument", m.pos);
				}
			}
		return null;
	}

	static function field( fl : Array<ObjectField>, name : String ) : Null<Expr> {
		for( f in fl )
			if( f.field == name )
				return f.expr;
		return null;
	}

	static function kindOf( t : Expr ) : ParamKind {
		return switch( t.expr ) {
			case ECall({expr: EConst(CIdent("PVec"))}, args):
				switch( args[0].expr ) {
					case EConst(CInt(v)): KVec(Std.parseInt(v));
					default: Context.error("PVec size must be a constant", t.pos);
				}
			case ECall({expr: EConst(CIdent("PEnum"))}, args): KEnum(args[0]);
			case EConst(CIdent("PGradient")): KGradient;
			default: KScalar;
		}
	}

	public static function build() : Array<Field> {
		var fields = Context.getBuildFields();
		var pos = Context.currentPos();
		var params : Array<Param> = [];
		var emitterDecls : Array<Expr> = [];
		var extra : Array<Field> = [];

		for( f in fields ) {
			var meta = metaObj(f, ":param");
			if( meta == null )
				continue;

			var fdef = null;
			switch( f.kind ) {
				case FVar(_, e): fdef = e;
				default: Context.error("Emitter param must be a variable", f.pos);
			}

			var t = field(meta, "t");
			if( t == null )
				Context.error("Missing param type", f.pos);
			var kind = kindOf(t);
			var def = fdef ?? macro @:pos(f.pos) null;

			var decl : Array<ObjectField> = [
				{ field: "name", expr: macro @:pos(f.pos) $v{f.name} },
				{ field: "t", expr: t },
				{ field: "def", expr: macro @:pos(f.pos) ($def : Dynamic) },
			];
			var disp = field(meta, "disp");
			if( disp != null ) decl.push({ field: "disp", expr: disp });
			var group = field(meta, "group");
			if( group != null ) decl.push({ field: "groupName", expr: group });
			decl.push({ field: "animate", expr: field(meta, "animate") ?? macro false });

			var declExpr : Expr = { expr: EObjectDecl(decl), pos: f.pos };
			var declName = "P_" + f.name;
			extra.push({
				name: declName,
				access: [AStatic, AFinal],
				kind: FVar(macro : hrt.prefab.fx.EmitterHelper.ParamDef, declExpr),
				pos: f.pos,
			});
			emitterDecls.push(macro @:pos(f.pos) $i{declName});
			params.push({ name: f.name, kind: kind, def: def, pos: f.pos });
		}

		var load : Array<Expr> = [];
		var save : Array<Expr> = [];
		var copy : Array<Expr> = [];

		for( p in params ) {
			var n = p.name;
			var def = p.def;
			var pos = p.pos;

			var src = macro @:pos(pos) props.$n;
			load.push(switch( p.kind ) {
				case KEnum(e):
					macro @:pos(pos) this.$n = hrt.prefab.Macros.enumOrNullByName($e, $src, null, $def);
				case KGradient:
					macro @:pos(pos) this.$n = $src;
				case KVec(_):
					macro @:pos(pos) { var v = $src; this.$n = v == null ? $def : hrt.prefab.fx.EmitterHelper.toArray(v); };
				default:
					macro @:pos(pos) { var v = $src; this.$n = v == null ? $def : v; };
			});

			var set = macro @:pos(pos) Reflect.setField(props, $v{n}, this.$n);
			var changed = switch( p.kind ) {
				case KVec(_): macro @:pos(pos) !hrt.prefab.fx.EmitterHelper.sameArray(this.$n, $def);
				case KGradient: macro @:pos(pos) true;
				default: macro @:pos(pos) this.$n != $def;
			}
			switch( p.kind ) {
				case KEnum(_): set = macro @:pos(pos) Reflect.setField(props, $v{n}, Type.enumConstructor(this.$n));
				default:
			}
			save.push(p.kind.match(KGradient)
				? macro @:pos(pos) if( this.$n != null && $changed ) $set
				: macro @:pos(pos) if( $changed ) $set);

			copy.push(switch( p.kind ) {
				case KVec(_): macro @:pos(pos) this.$n = from.$n == null ? null : from.$n.copy();
				default: macro @:pos(pos) this.$n = from.$n;
			});
		}

		var selfType = Context.toComplexType(Context.getLocalType());

		extra.push({
			name: "emitterParams",
			access: [APublic, AStatic],
			kind: FVar(macro : Array<hrt.prefab.fx.EmitterHelper.ParamDef>, { expr: EArrayDecl(emitterDecls), pos: pos }),
			pos: pos,
		});
		extra.push({
			name: "PARAMS",
			access: [APublic, AStatic],
			kind: FVar(macro : Map<String, hrt.prefab.fx.EmitterHelper.ParamDef>, macro {
				var m = new Map();
				for( p in emitterParams ) m.set(p.name, p);
				m;
			}),
			pos: pos,
		});

		extra.push({
			name: "loadParams",
			access: [],
			kind: FFun({
				args: [{ name: "props", type: macro : Dynamic }],
				expr: macro { if( props == null ) props = {}; $b{load}; },
			}),
			pos: pos,
		});
		extra.push({
			name: "saveParams",
			access: [],
			kind: FFun({
				args: [],
				ret: macro : Dynamic,
				expr: macro { var props : Dynamic = {}; $b{save}; return props; },
			}),
			pos: pos,
		});
		extra.push({
			name: "copyParams",
			access: [],
			kind: FFun({
				args: [{ name: "from", type: selfType }],
				expr: { expr: EBlock(copy), pos: pos },
			}),
			pos: pos,
		});

		for( f in extra )
			fields.push(f);
		return fields;
	}
	#end
}

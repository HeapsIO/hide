package hrt.impl;
import haxe.macro.Context;
import haxe.macro.Expr;

class Macros {

	#if macro
	public static function buildPrefab() {
		var fields = Context.getBuildFields();
		var toSerialize = [];
		for( f in fields ) {
			if( f.meta == null ) continue;
			for( m in f.meta )
				if( m.name == ":s" )
					toSerialize.push(f);
		}
		if( toSerialize.length == 0 )
			return null;
		var ser = [], unser = [];
		var pos = Context.currentPos();
		for( f in toSerialize ) {
			switch( f.kind ) {
			case FProp(_, _, t, e), FVar(t,e):
				var name = f.name;
				var serCond = null;
				if( e == null ) {
					var setDef = true;
					var c : Constant = switch( t ) {
					case null: Context.error("Invalid var decl", f.pos);
					case TPath({ pack : [], name : "Int"|"Float" }): CInt("0");
					case TPath({ pack : [], name : "Bool" }): CIdent("false");
					default: setDef = false; CIdent("null");
					}
					e = { expr : EConst(c), pos : f.pos };
					if( setDef ) {
						f.kind = switch( f.kind ) {
						case FVar(t,_): FVar(t,e);
						case FProp(get,set,t,_): FProp(get,set,t,e);
						default: throw "assert";
						}
					}
				} else {
					var echeck = e;
					if( e.expr.match(EArrayDecl([])) )
						serCond = macro @:pos(f.pos) this.$name.length != 0;
				}

				if( serCond == null ) {
					var defVal = e.expr.match(EConst(_) | EBinop(_) | EUnop(_)) ? e : macro @:pos(f.pos) null;
					serCond = macro @:pos(pos) this.$name != $defVal;
				}

				ser.push(macro @:pos(pos) if( $serCond ) obj.$name = this.$name);
				unser.push(macro @:pos(pos) this.$name = obj.$name == null ? $e : obj.$name);
			default:
				Context.error("Invalid serialization field", f.pos);
			}
		}
		var isRoot = Context.getLocalClass().toString() == "hrt.prefab.Prefab";
		if( !isRoot ) {
			ser.unshift(macro @:pos(pos) super.saveSerializedFields(obj));
			unser.unshift(macro @:pos(pos) super.loadSerializedFields(obj));
		}
		function makeFun(name,block) : Field {
			return {
				name : name,
				kind : FFun({
					ret : null,
					expr : { expr : EBlock(block), pos : pos },
					args : [{ name : "obj", type : macro : Dynamic }],
				}),
				meta : [{ name : ":noCompletion", pos : pos }],
				access : isRoot ? [] : [AOverride],
				pos : pos,
			};
		}
		fields.push(makeFun("saveSerializedFields",ser));
		fields.push(makeFun("loadSerializedFields",unser));
		return fields;
	}
	#end

}
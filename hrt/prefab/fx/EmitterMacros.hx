package hrt.prefab.fx;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	Builds the params of an emitter from its fields:

	- the `@:s` fields are its settings, serialized like any prefab field: `@:range(min, max)` for the
	  inspector, `@:animate` when an animation curve can set it;
	- `@:param(PFloat(0, 2), Particle, 1.)` on a `ParamValue`: a param with modes, of a `ParamGroup`, with
	  its default (0 when not given), saved in `params` (under `@:name("x")` when the field cannot be named so);
	- `@:group("Name")`: the inspector group of the field and of the next ones.

	Generates `emitterParams` (the settings), `MODE_PARAMS`, `loadParams` / `saveParams` / `copyParams`,
	`getParam` / `setParam` by name, and `makeValues`, which builds the values into the emitter object
	`objectType`: per particle params first, then the settings, then the spawn params, the order their
	random slots are allocated in.
**/
class EmitterMacros {

	#if macro

	static function metaArgs( f : Field, name : String ) : Null<Array<Expr>> {
		for( m in f.meta ?? [] )
			if( m.name == name )
				return m.params;
		return null;
	}

	static function typePath( e : Expr ) : ComplexType {
		var parts = haxe.macro.ExprTools.toString(e).split(".");
		var i = 0;
		while( i < parts.length && parts[i].charAt(0) == parts[i].charAt(0).toLowerCase() ) i++;
		return TPath({ pack: parts.slice(0, i), name: parts[i], sub: parts[i + 1] });
	}

	/** The inspector type of a setting, from its type **/
	static function propType( f : Field, t : ComplexType, init : Null<Expr> ) : Expr {
		var r = metaArgs(f, ":range") ?? [];
		var min = r[0] ?? macro null, max = r[1] ?? macro null;
		var name = switch( t ) { case TPath(p): p.sub ?? p.name; default: Context.error("Unsupported setting type", f.pos); };
		return switch( name ) {
			case "Float": macro PFloat($min, $max);
			case "Int": macro PInt($min, $max);
			case "Bool": macro PBool;
			case "String": macro PTexture;
			case "GradientData": macro PGradient;
			case "Array":
				var n = switch( init?.expr ) { case EArrayDecl(v): v.length; default: Context.error("A vector setting needs its default", f.pos); };
				macro PVec($v{n}, $min, $max);
			default: macro PEnum($i{name});
		}
	}

	public static function build( objectType : Expr ) : Array<Field> {
		var fields = Context.getBuildFields();
		var pos = Context.currentPos();
		var selfType = Context.toComplexType(Context.getLocalType());
		var statics : Array<Field> = [];
		var settings = [], modeDecls = [];
		var load = [], save = [], copy = [], getCases = [], setCases = [];
		var particleValues = [], settingValues = [], spawnValues = [];
		var group = "Params";

		for( f in fields ) {
			var g = metaArgs(f, ":group");
			if( g != null )
				group = switch( g[0].expr ) { case EConst(CString(s)): s; default: Context.error("@:group expects a string", f.pos); };
			var p = f.pos;
			var n = f.name;

			if( metaArgs(f, ":s") != null ) {
				switch( f.kind ) {
				case FVar(t, init):
					var animate = metaArgs(f, ":animate") != null;
					settings.push(macro @:pos(p) ({ name: $v{n}, t: ${propType(f, t, init)}, def: (${init ?? macro null} : Dynamic), groupName: $v{group}, animate: $v{animate} }
						: hrt.prefab.fx.EmitterHelper.ParamDef));
					if( animate )
						settingValues.push(macro @:pos(p) obj.$n = b.animated(hrt.prefab.fx.Evaluator.vVal(this.$n), $v{n}));
				default:
				}
				continue;
			}

			var a = metaArgs(f, ":param");
			if( a == null )
				continue;
			var t = a[0];
			var modeGroup = switch( a[1]?.expr ) {
				case EConst(CIdent(g)) if( ["Spawn", "Particle", "Multiplier"].indexOf(g) >= 0 ): g;
				default: Context.error("@:param(type, Spawn | Particle | Multiplier, ?default)", p);
			}
			var nameArg = metaArgs(f, ":name");
			var key = switch( nameArg == null ? null : nameArg[0].expr ) {
				case null: n;
				case EConst(CString(k)): k;
				default: Context.error("@:name expects a string", p);
			}
			var dim = switch( t.expr ) {
				case ECall({expr: EConst(CIdent("PVec"))}, args): switch( args[0].expr ) { case EConst(CInt(v)): Std.parseInt(v); default: 1; };
				default: 1;
			}
			var defs = switch( a[2]?.expr ) {
				case null: [for( _ in 0...dim ) macro 0.];
				case EArrayDecl(values): values;
				default: [a[2]];
			}
			var defName = "MP_" + key;
			statics.push({ name: defName, access: [APublic, AStatic, AFinal], pos: p, kind: FVar(macro : hrt.prefab.fx.EmitterParam.ModeParamDef,
				macro @:pos(p) { name: $v{key}, t: $t, def: ${{ expr: EArrayDecl([for( d in defs ) macro ($d : Float)]), pos: p }},
					group: hrt.prefab.fx.EmitterParam.ParamGroup.$modeGroup, category: $v{group} }) });
			modeDecls.push(macro @:pos(p) $i{defName});
			load.push(macro @:pos(p) this.$n = hrt.prefab.fx.EmitterParam.parse(params.$key, $v{dim}));
			save.push(macro @:pos(p) { var v = hrt.prefab.fx.EmitterParam.save(this.$n); if( v != null ) { params.$key = v; any = true; } });
			copy.push(macro @:pos(p) this.$n = from.$n?.copy());
			getCases.push({ values: [macro $v{key}], expr: macro this.$n });
			setCases.push({ values: [macro $v{key}], expr: macro this.$n = v });
			var def = macro @:pos(p) $i{defName};
			if( modeGroup != "Spawn" )
				particleValues.push(macro @:pos(p) d.$key = b.param($def, this.$n));
			else if( dim > 1 )
				spawnValues.push(macro @:pos(p) obj.$key = b.param($def, this.$n));
			else {
				// a scalar spawn param is drawn from the emitter random stream when a particle spawns
				var rand = key + "Rand", min = key + "Min", max = key + "Max";
				spawnValues.push(macro @:pos(p) {
					var s = b.span($def, this.$n);
					obj.$key = s.mid;
					obj.$rand = s.rand;
					obj.$min = s.min;
					obj.$max = s.max;
				});
			}
		}

		statics.push({ name: "emitterParams", access: [APublic, AStatic], pos: pos,
			kind: FVar(macro : Array<hrt.prefab.fx.EmitterHelper.ParamDef>, { expr: EArrayDecl(settings), pos: pos }) });
		statics.push({ name: "PARAMS", access: [APublic, AStatic], pos: pos,
			kind: FVar(macro : Map<String, hrt.prefab.fx.EmitterHelper.ParamDef>, macro [for( p in emitterParams ) p.name => p]) });
		statics.push({ name: "MODE_PARAMS", access: [APublic, AStatic], pos: pos,
			kind: FVar(macro : Array<hrt.prefab.fx.EmitterParam.ModeParamDef>, { expr: EArrayDecl(modeDecls), pos: pos }) });
		statics.push({ name: "MODE_PARAMS_BY_NAME", access: [APublic, AStatic], pos: pos,
			kind: FVar(macro : Map<String, hrt.prefab.fx.EmitterParam.ModeParamDef>, macro [for( p in MODE_PARAMS ) p.name => p]) });
		statics.push({ name: "instanceParams", doc: "The spawn and multiplier params, as tracks of the FX timeline", access: [APublic, AStatic], pos: pos,
			kind: FVar(macro : Array<hrt.prefab.fx.EmitterHelper.ParamDef>, macro hrt.prefab.fx.EmitterParam.timelineTracks(MODE_PARAMS)) });

		var methods : Array<Field> = [
			{ name: "animCurves", access: [APublic], pos: pos, kind: FVar(macro : hrt.prefab.fx.EmitterParam.AnimCurves, macro []) },
			{ name: "loadParams", pos: pos, kind: FFun({ args: [{ name: "data", type: macro : Dynamic }], expr: macro {
				var params : Dynamic = data.params ?? {};
				$b{load};
				animCurves = hrt.prefab.fx.EmitterParam.parseAnimCurves(data.animCurves);
			} }) },
			{ name: "saveParams", pos: pos, kind: FFun({ args: [{ name: "data", type: macro : Dynamic }], expr: macro {
				var params : Dynamic = {}, any = false;
				$b{save};
				if( any ) data.params = params;
				var anim = hrt.prefab.fx.EmitterParam.saveAnimCurves(animCurves);
				if( anim != null ) data.animCurves = anim;
			} }) },
			{ name: "copyParams", pos: pos, kind: FFun({ args: [{ name: "from", type: selfType }], expr: macro {
				$b{copy};
				animCurves = from.animCurves.copy();
			} }) },
			{ name: "getParam", access: [APublic], pos: pos, kind: FFun({ args: [{ name: "name", type: macro : String }],
				ret: macro : Null<hrt.prefab.fx.EmitterParam.ParamValue>,
				expr: { expr: EReturn({ expr: ESwitch(macro name, getCases, macro null), pos: pos }), pos: pos } }) },
			{ name: "setParam", doc: "Null unsets every component", access: [APublic], pos: pos, kind: FFun({
				args: [{ name: "name", type: macro : String }, { name: "v", type: macro : Null<hrt.prefab.fx.EmitterParam.ParamValue> }],
				expr: macro {
					if( hrt.prefab.fx.EmitterParam.isUnset(v) ) v = null;
					${{ expr: ESwitch(macro name, setCases, macro throw "No param " + name), pos: pos }};
				} }) },
			{ name: "makeValues", access: [APublic], pos: pos, kind: FFun({ args: [{ name: "obj", type: typePath(objectType) }],
				ret: macro : hrt.prefab.fx.EmitterParam.ParamBuilder,
				expr: macro {
					var b = new hrt.prefab.fx.EmitterParam.ParamBuilder(this, animCurves);
					var d = new hrt.prefab.fx.Emitter.InstanceDef();
					obj.instDef = d;
					$b{particleValues};
					$b{settingValues};
					$b{spawnValues};
					return b;
				} }) },
		];
		// the statics first: the ones of the class can use them in their initialization
		for( i => f in statics )
			fields.insert(i, f);
		return fields.concat(methods);
	}
	#end
}

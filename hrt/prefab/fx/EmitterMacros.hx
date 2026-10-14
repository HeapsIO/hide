package hrt.prefab.fx;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	Emitter fields:
	- `@:s` settings, `@:range(min, max)`, `@:animate` when an animation curve can set them, `@:disp("Label")`;
	- `@:param(PVec(3, -10, 10), Particle, default)` params with modes (`EmitterParam`), saved in `params`,
	  under `@:name("key")` when given;
	- `@:group("Name")`: the inspector group of the field and of the next ones.
	The random slots are allocated in the order of `makeValues`: particle params, settings, spawn params.
**/
class EmitterMacros {

	#if macro

	static function meta( f : Field, name : String ) : Null<Array<Expr>> {
		for( m in f.meta )
			if( m.name == name )
				return m.params;
		return null;
	}

	static function propType( f : Field, t : ComplexType, init : Null<Expr> ) : Expr {
		var r = meta(f, ":range") ?? [];
		var min = r[0] ?? macro null, max = r[1] ?? macro null;
		return switch( t ) {
		case TPath({ name: "Float" }): macro PFloat($min, $max);
		case TPath({ name: "Int" }): macro PInt($min, $max);
		case TPath({ name: "Bool" }): macro PBool;
		case TPath({ name: "String" }): macro PTexture;
		case TPath({ name: "Array" }):
			switch( init?.expr ) {
			case EArrayDecl(v): macro PVec($v{v.length}, $min, $max);
			default: Context.error("A vector setting needs its default", f.pos);
			}
		case TPath({ sub: "GradientData" }): macro PGradient;
		case TPath(p): macro PEnum($i{p.sub ?? p.name});
		default: Context.error("Unsupported setting type", f.pos);
		}
	}

	public static function build( objectType : Expr ) : Array<Field> {
		var fields = Context.getBuildFields();
		var pos = Context.currentPos();
		var settings = [], modeParams = [];
		var load = [], unset = [], save = [], copy = [], getCases = [], setCases = [];
		var particleValues = [], settingValues = [], spawnValues = [];
		var group = "Params";

		for( f in fields ) {
			var g = meta(f, ":group");
			if( g != null )
				group = haxe.macro.ExprTools.getValue(g[0]);
			var p = f.pos, n = f.name;
			var disp = meta(f, ":disp");

			if( meta(f, ":s") != null ) {
				switch( f.kind ) {
				case FVar(t, init):
					var animate = meta(f, ":animate") != null;
					settings.push(macro @:pos(p) { name: $v{n}, t: ${propType(f, t, init)}, def: (${init ?? macro null} : Dynamic), groupName: $v{group},
						animate: $v{animate}, disp: ${disp == null ? macro null : disp[0]} });
					if( init != null && init.expr.match(EArrayDecl(_)) )
						save.push(macro @:pos(p) if( haxe.Json.stringify(this.$n) == haxe.Json.stringify($init) ) Reflect.deleteField(data, $v{n}));
					if( animate )
						settingValues.push(macro @:pos(p) obj.$n = b.animated($v{n}, hrt.prefab.fx.Evaluator.vVal(this.$n)));
				default:
				}
				continue;
			}

			var a = meta(f, ":param");
			if( a == null )
				continue;
			var key = n;
			var nameArg = meta(f, ":name");
			if( nameArg != null )
				key = haxe.macro.ExprTools.getValue(nameArg[0]);
			var dim = switch( a[0].expr ) {
				case ECall({ expr: EConst(CIdent("PVec")) }, args): Std.parseInt(haxe.macro.ExprTools.toString(args[0]));
				default: 1;
			}
			var kind = haxe.macro.ExprTools.toString(a[1]);
			var defs = switch( a[2]?.expr ) {
				case null: [for( _ in 0...dim ) macro 0.];
				case EArrayDecl(values): values;
				default: [a[2]];
			}
			var def = macro @:pos(p) MODE_PARAMS[$v{modeParams.length}];
			modeParams.push(macro @:pos(p) { name: $v{key}, t: ${a[0]}, def: ($a{defs} : Array<Float>), kind: hrt.prefab.fx.EmitterParam.ParamKind.$kind,
				groupName: $v{group}, disp: ${disp == null ? macro null : disp[0]} });
			load.push(macro @:pos(p) this.$n = hrt.prefab.fx.EmitterParam.parse(params.$key, $v{dim}));
			unset.push(macro @:pos(p) this.$n = null);
			save.push(macro @:pos(p) { var v = hrt.prefab.fx.EmitterParam.save(this.$n); if( v != null ) { params.$key = v; any = true; } });
			copy.push(macro @:pos(p) this.$n = from.$n?.copy());
			getCases.push({ values: [macro $v{key}], expr: macro this.$n });
			setCases.push({ values: [macro $v{key}], expr: macro this.$n = v });
			switch( kind ) {
			case "Spawn" if( dim == 1 ):
				// drawn by the emitter when a particle spawns
				var min = key + "Min", max = key + "Max";
				spawnValues.push(macro @:pos(p) { var s = b.bounds($def, this.$n, 0); obj.$min = s.min; obj.$max = s.max; });
			case "Spawn": spawnValues.push(macro @:pos(p) obj.$key = b.param($def, this.$n));
			default: particleValues.push(macro @:pos(p) d.$key = b.param($def, this.$n));
			}
		}

		var objPath = haxe.macro.ExprTools.toString(objectType).split(".");
		var objCT = TPath({ pack: objPath.slice(0, objPath.length - 2), name: objPath[objPath.length - 2], sub: objPath[objPath.length - 1] });
		var selfType = Context.toComplexType(Context.getLocalType());
		var add : Array<Field> = (macro class {
			public static var emitterParams : Array<hrt.prefab.fx.EmitterHelper.ParamDef> = $a{settings};
			public static var MODE_PARAMS : Array<hrt.prefab.fx.EmitterParam.ModeParamDef> = $a{modeParams};
			public var animCurves : Null<hrt.prefab.fx.EmitterParam.AnimCurves>;
			function loadParams( data : Dynamic ) {
				var params : Dynamic = data.params;
				if( params == null ) $b{unset} else $b{load};
				var anim : Dynamic = data.animCurves;
				animCurves = anim == null ? null : hrt.prefab.fx.EmitterParam.parseAnimCurves(anim);
			}
			function saveParams( data : Dynamic ) {
				var params : Dynamic = {}, any = false;
				$b{save};
				if( any ) data.params = params;
				var anim = hrt.prefab.fx.EmitterParam.saveAnimCurves(animCurves);
				if( anim != null ) data.animCurves = anim;
			}
			function copyParams( from : $selfType ) {
				$b{copy};
				animCurves = from.animCurves?.copy();
			}
			public function getParam( name : String ) : Null<hrt.prefab.fx.EmitterParam.ParamValue> {
				return ${{ expr: ESwitch(macro name, getCases, macro null), pos: pos }};
			}
			public function setParam( name : String, v : Null<hrt.prefab.fx.EmitterParam.ParamValue> ) {
				${{ expr: ESwitch(macro name, setCases, macro throw "No param " + name), pos: pos }};
			}
			public function makeValues( obj : $objCT ) : hrt.prefab.fx.EmitterParam.ParamBuilder {
				var b = new hrt.prefab.fx.EmitterParam.ParamBuilder(this, animCurves);
				var d = new hrt.prefab.fx.Emitter.InstanceDef();
				obj.instDef = d;
				$b{particleValues};
				$b{settingValues};
				$b{spawnValues};
				return b;
			}
		}).fields;
		// the statics first, the ones of the class can use them
		return add.slice(0, 2).concat(fields).concat(add.slice(2));
	}
	#end
}

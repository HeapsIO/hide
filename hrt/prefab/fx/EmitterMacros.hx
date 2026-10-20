package hrt.prefab.fx;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	Emitter fields:
	- `@:s` settings, `@:range(min, max)`, `@:animate` when an animation curve can set them, `@:disp("Label")`,
	  `@:t(PFile([...]))` for a type other than the one of the field;
	- `@:param(PVec(3, -10, 10), Particle, default)` params with modes (`EmitterParam`), saved in `params`,
	  under `@:name("key")` when given;
	- `@:group("Name")`: the inspector group of the field and of the next ones.
	The random slots are allocated in the order of `makeValues`: particle params, settings, spawn params.
**/
class EmitterMacros {

	#if macro

	static function meta( f : Field, name : String ) : Array<Expr> {
		for( m in f.meta )
			if( m.name == name )
				return m.params;
		return null;
	}

	static function propType( f : Field, t : ComplexType, init : Expr ) : Expr {
		var explicit = meta(f, ":t");
		if( explicit != null )
			return explicit[0];
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
		case TPath({ name: "GradientData" } | { sub: "GradientData" }): macro PGradient;
		case TPath(p): macro PEnum($i{p.sub ?? p.name});
		default: Context.error("Unsupported setting type", f.pos);
		}
	}

	/** `objectType`: the path of the class of the emitter object **/
	public static function build( objectType : String ) : Array<Field> {
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
			if( dim == 1 ) {
				load.push(macro @:pos(p) this.$n = hrt.prefab.fx.EmitterParam.parseMode(params.$key));
				save.push(macro @:pos(p) { var v = hrt.prefab.fx.EmitterParam.saveMode(this.$n); if( v != null ) { params.$key = v; any = true; } });
				getCases.push({ values: [macro $v{key}], expr: macro this.$n });
				setCases.push({ values: [macro $v{key}], expr: macro this.$n = m });
			} else {
				load.push(macro @:pos(p) this.$n = hrt.prefab.fx.EmitterParam.parseVec(params.$key));
				save.push(macro @:pos(p) { var v = hrt.prefab.fx.EmitterParam.saveVec(this.$n); if( v != null ) { params.$key = v; any = true; } });
				getCases.push({ values: [macro $v{key}], expr: macro hrt.prefab.fx.EmitterParam.comp(this.$n, comp) });
				setCases.push({ values: [macro $v{key}], expr: macro this.$n = hrt.prefab.fx.EmitterParam.withComp(this.$n, comp, m) });
			}
			unset.push(macro @:pos(p) this.$n = null);
			copy.push(macro @:pos(p) this.$n = from.$n);
			if( kind == "Spawn" )
				spawnValues.push(dim == 1 ? macro @:pos(p) obj.$key = b.spawn($def)[0] : macro @:pos(p) obj.$key = b.spawn($def));
			else
				particleValues.push(macro @:pos(p) d.$key = b.param($def));
		}

		var objCT = Context.toComplexType(Context.getType(objectType));
		var selfType = Context.toComplexType(Context.getLocalType());
		// the statics first, the ones of the class can use them
		var statics = (macro class {
			public static var emitterParams : Array<hrt.prefab.fx.EmitterHelper.ParamDef> = $a{settings};
			public static var MODE_PARAMS : Array<hrt.prefab.fx.EmitterParam.ModeParamDef> = $a{modeParams};
		}).fields;
		var methods = (macro class {
			function loadParams( data : Dynamic ) {
				var params : Dynamic = data.params;
				if( params == null ) $b{unset} else $b{load};
			}
			function saveParams( data : Dynamic ) {
				var params : Dynamic = {}, any = false;
				$b{save};
				if( any ) data.params = params;
			}
			function copyParams( from : $selfType ) {
				$b{copy};
			}
			public function getSettings() return emitterParams;
			public function getModeParams() return MODE_PARAMS;
			public function getMode( name : String, comp : Int ) : hrt.prefab.fx.EmitterParam.ParamMode {
				return ${{ expr: ESwitch(macro name, getCases, macro null), pos: pos }};
			}
			public function setMode( name : String, comp : Int, m : hrt.prefab.fx.EmitterParam.ParamMode ) {
				${{ expr: ESwitch(macro name, setCases, macro throw "No param " + name), pos: pos }};
			}
			public function makeValues( obj : $objCT ) : hrt.prefab.fx.EmitterParam.ParamBuilder {
				var b = new hrt.prefab.fx.EmitterParam.ParamBuilder(this, this);
				var d = new hrt.prefab.fx.Emitter.InstanceDef();
				obj.instDef = d;
				$b{particleValues};
				$b{settingValues};
				$b{spawnValues};
				return b;
			}
		}).fields;
		return statics.concat(fields).concat(methods);
	}
	#end
}

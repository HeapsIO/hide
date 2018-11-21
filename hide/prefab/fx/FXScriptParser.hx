package hide.prefab.fx;
import  hide.prefab.fx.FXScript;

@:access(hide.view.FXEditor)
class FXScriptParser {

	public var firstParse = false;

	public function new(){
	}

	inline function getExpr( e : hscript.Expr ) {
		#if hscriptPos
		return e.e;
		#else
		return e;
		#end
	}

	public function createFXScript( s : String, fx : hide.prefab.fx.FX.FXAnimation ) : FXScript {
		var parser = new hscript.Parser();
		parser.allowMetadata = true;
		parser.allowTypes = true;
		parser.allowJSON = true;
		var expr : hscript.Expr = null;
		var script = new hide.prefab.fx.FXScript();
		script.fx = fx;

		function parse( expr : hscript.Expr ) {
			if( expr == null ) return;
			switch(getExpr(expr)){
				case EMeta(name, args, e):
					parse(e);
					switch(name){
						case "param" :
							script.params.push(createFXParam(e));
					}

				case EBlock(e):
					for(expr in e)
						parse(expr);

				case EVar(n, t, e):
					script.myVars.set(n, createFXVar(expr));

				default:
			}
		}
		try {
			expr = parser.parseString(s, "");
		} catch( e : hscript.Expr.Error ) { }
		parse(expr);

		function convert( expr : hscript.Expr ) : FxAst {
			if( expr == null ) return null;

			function getPath( expr : hscript.Expr ) : String {
					return switch(getExpr(expr)){
						case EField(e,f): getPath(e) + "." + f;
						case EIdent(v): v;
						default: null;
					}
				}

			function getSetField( expr : hscript.Expr ){
				return script.getSetter(getPath(expr));
			}

			function getGetField( expr : hscript.Expr ){
				return script.getGetter(getPath(expr));
			}

			switch(getExpr(expr)){

				case EBlock(e):
					return Block( [for(expr in e) convert(expr)] );

				case ECall( e, params ):
					var name = switch(getExpr(e)){
						case EIdent(v): v;
						default: null;
					}
					return Call( name, [for(a in params) convert(a)]);

				case EFunction(args, e, name, ret):
					return null; // TO DO

				case EVar(n, t, e):
					if(e != null ) return Set(function(v){ script.setVar(n, v); }, convert(e));
					else return Var( function(){ return script.getVar(n); });

				case EField(e, f):
					return Var( script.getGetter(f) );

				case EIf( cond, e1, e2):
					return If(convert(cond), convert(e1), convert(e2));

				case EIdent(v):
					return switch(v) {
								case "true": Const(1);
								case "false": Const(0);
								default: Var( function(){ return script.getVar(v); });
							}

				case EConst( c ):
					return switch(c){
						case CInt(v): Const(v);
						case CFloat(f): Const(f);
						default: null;
					}

				case EBinop(op, e1, e2):
					switch(op){
						case "%": return Op( convert(e1), convert(e2), function(a,b) { return a % b; });
						case "*": return Op( convert(e1), convert(e2), function(a,b) { return a * b; });
						case "/": return Op( convert(e1), convert(e2), function(a,b) { return a / b; });
						case "+": return Op( convert(e1), convert(e2), function(a,b) { return a + b; });
						case "-": return Op( convert(e1), convert(e2), function(a,b) { return a - b; });
						case "=": 	switch(getExpr(e1)){
											case EIdent(v): return Set(function(val){ script.setVar(v, val); }, convert(e2));
											case EField(e,f): return Set( getSetField(e1), convert(e2));
											default: return null;
										}
						case "+=":  switch(getExpr(e1)){
										case EIdent(v): return Set(function(val){ script.setVar(v, val); }, Op( convert(e1), convert(e2), function(a,b) { return a + b; }));
										case EField(e,f): return Set( getSetField(e1), Op( convert(e1), convert(e2), function(a,b) { return a + b; }));
										default: return null;
									}

						case "-=":	switch(getExpr(e1)){
										case EIdent(v): return Set(function(val){ script.setVar(v, val); }, Op( convert(e1), convert(e2), function(a,b) { return a - b; }));
										case EField(e,f): return Set( getSetField(e1), Op( convert(e1), convert(e2), function(a,b) { return a - b; }));
										default: return null;
									}
						case "==": return Op( convert(e1), convert(e2), function(a,b) { return a == b ? 1.0 : 0.0; });
						case "!=": return Op( convert(e1), convert(e2), function(a,b) { return a != b ? 1.0 : 0.0; });
						case ">": return Op( convert(e1), convert(e2), function(a,b) { return a > b ? 1.0 : 0.0; });
						case "<": return Op( convert(e1), convert(e2), function(a,b) { return a < b ? 1.0 : 0.0; });
						case ">=": return Op( convert(e1), convert(e2), function(a,b) { return a >= b ? 1.0 : 0.0; });
						case "<=": return Op( convert(e1), convert(e2), function(a,b) { return a <= b ? 1.0 : 0.0; });
						default: return null;
					}

				case EUnop(op, prefix, e):
					switch(getExpr(e)){
						case EIdent(v):
							return switch(op){
								case "++": Set( function(val){ script.setVar(v, val); }, Unop(convert(e), function(a){ return prefix ? ++a : a++; }));
								case "--": Set( function(val){ script.setVar(v, val); }, Unop(convert(e), function(a){ return prefix ? --a : a--; }));
								case "-": Unop( convert(e), function(a){ return -a;});
								default: null;
							}
						case EField(e,f):
							return switch(op){
								case "++": Set( getSetField(e), Unop(convert(e), function(a){ return prefix ? ++a : a++; }));
								case "--": Set( getSetField(e), Unop(convert(e), function(a){ return prefix ? --a : a--; }));
								case "-": Unop( convert(e), function(a){ return -a;});
								default : null;
							}
						default: return null;
					}

				default:
					return null;
			}
		}
		script.ast = convert(expr);
		return script;
	}

	function createFXVar( expr : hscript.Expr ) {
		function parse(expr : hscript.Expr) : FXVar {
			return switch(getExpr(expr)){
				case EMeta(name, args, e):
					return parse(e);
				case EVar(n, t, e):
					var r : FXVar = null;
					if(t != null){
						switch(t){
							case CTPath(path, params):
								switch(path){
									case ["Int"]: r = FXVar.Int(0);
									case ["Float"]: r = FXVar.Float(0.0);
									case ["Bool"]: r = FXVar.Bool(false);
									default:
								}
							default: null;
						}
					}
					if(e != null){
						switch(getExpr(e)){
							case EIdent(v):
								if(r != null){
									switch(r){
										case Float(value):
											switch(v) {
												case "true": r = FXVar.Float(1.0);
												case "false": r = FXVar.Float(0.0);
												default:
											}
										case Int(value):
											switch(v) {
												case "true": r = FXVar.Int(1);
												case "false": r = FXVar.Int(0);
												default:
											}
										case Bool(value):
											switch(v) {
												case "true": r = FXVar.Bool(true);
												case "false": r = FXVar.Bool(false);
												default:
											}
									}
								}else{
									switch(v) {
										case "true": r = FXVar.Bool(true);
										case "false": r = FXVar.Bool(false);
										default:
									}
							}
							case EConst(c):
								if(r != null){
									switch(r){
										case Float(value):
											switch(c){
												case CInt(v): r = FXVar.Float(v);
												case CFloat(f): r = FXVar.Float(f);
												default:
											}
										case Int(value):
											switch(c){
												case CInt(v): r = FXVar.Int(v);
												case CFloat(f): r = FXVar.Int(Std.int(f));
												default:
											}
										case Bool(value):
											switch(c){
												case CInt(v): r = FXVar.Bool(v > 0);
												case CFloat(f): r = FXVar.Bool(f > 0);
												default:
											}
									}
								}
								else{
									switch(c){
										case CInt(v): r = FXVar.Int(v);
										case CFloat(f): r = FXVar.Float(f);
										default:
									}
								}
							default: null;
						}
					}
					return r;

				default: null;
			}
		}
		return parse(expr);
	}

	function createFXParam( expr : hscript.Expr ) : FXParam {
		var options : Array<ParamOption> = [];
		function parse(expr : hscript.Expr) : FXParam {
			if( expr == null ) return null;
			switch(getExpr(expr)){
				case EMeta(name, args, e):
					switch(name){
						case "range":
						var min = 	switch(getExpr(args[0])){
										case EConst(c):
											switch(c){
												case CInt(v): v;
												case CFloat(f): f;
												default: null;
											}
										default: null;
									}
						var max = 	switch(getExpr(args[1])){
										case EConst(c):
											switch(c){
												case CInt(v): v;
												case CFloat(f): f;
												default: null;
											}
										default: null;
									}
						options.push(Range(min, max));
						default:
					}
					return parse(e);

				case EVar(n, t, e):
					var r : FXParam = null;
					if(t != null){
						switch(t){
							case CTPath(path, params):
								switch(path){
									case ["Int"]: r =  FXParam.Int(n, 0, options);
									case ["Float"]: r = FXParam.Float(n, 0.0, options);
									case ["Bool"]: r = FXParam.Bool(n, false, options);
									default:
								}
							default: null;
						}
					}
					if(e != null){
						switch(getExpr(e)){
							case EIdent(v):
								if(r != null){
									switch(r){
										case Float(name, value, options):
											switch(v) {
												case "true": r = FXParam.Float(n, 1.0, options);
												case "false": r = FXParam.Float(n, 0.0, options);
												default:
											}
										case Int(name, value, options):
											switch(v) {
												case "true": r = FXParam.Int(n, 1, options);
												case "false": r = FXParam.Int(n, 0, options);
												default:
											}
										case Bool(name, value, options):
											switch(v) {
												case "true": r = FXParam.Bool(n, true, options);
												case "false": r = FXParam.Bool(n, false, options);
												default:
											}
										}
								}else{
									switch(v) {
										case "true": r = FXParam.Bool(n, true, options);
										case "false": r = FXParam.Bool(n, false, options);
										default:
									}
							}
							case EConst(c):
								if(r != null){
									switch(r){
										case Float(name, value, options):
											switch(c){
												case CInt(v): r = FXParam.Float(n, v, options);
												case CFloat(f): r = FXParam.Float(n, f, options);
												default:
											}
										case Int(name, value, options):
											switch(c){
												case CInt(v): r = FXParam.Int(n, v, options);
												case CFloat(f): r = FXParam.Int(n, Std.int(f), options);
												default:
											}
										case Bool(name, value, options):
											switch(c){
												case CInt(v): r = FXParam.Bool(n, v > 0, options);
												case CFloat(f): r = FXParam.Bool(n, f > 0, options);
												default:
											}
									}
								}
								else{
									switch(c){
										case CInt(v): r = FXParam.Int(n, v, options);
										case CFloat(f): r =  FXParam.Float(n, f, options);
										default:
									}
								}
							default: null;
						}
					}
					return r;

				default:
					return null;
			}
			return null;
		}
		return parse(expr);
	}

	#if editor

	public function generateUI( s : FXScript, editor : hide.view.FXEditor ){
		var elem = editor.element.find(".fx-scriptParams");
		elem.empty();
		if(s == null) return;
		var root = new Element('<div class="group" name="Params"></div>');
		for(p in s.params){
			if(p == null) continue;
			switch(p){
				case Float(name, value, options):
					var sliderMin = 0.0;
					var sliderMax = 1.0;
					for(o in options){
						switch(o){
							case Range(min, max):
								sliderMin = min;
								sliderMax = max;
							default:
						}
					}
					root.append(createSlider(s, name, sliderMin, sliderMax, 0.1, value));
				case Int(name, value, options):
					var sliderMin = 0.0;
					var sliderMax = 1.0;
					for(o in options){
						switch(o){
							case Range(min, max):
								sliderMin = min;
								sliderMax = max;
							default:
						}
					}
					root.append(createSlider(s, name, sliderMin, sliderMax, 1.0, value));
				case Bool(name, value, options):
					root.append(createChekbox(s, name, value));
			}
		}
		elem.append(root);
	}

	function createSlider( s : FXScript, name : String, min : Float, max : Float, step : Float, defaultVal : Float ) : Element {
		var root = new Element('<div class="slider"></div>');
		var label = new Element('<label> $name : </label>');
		var slider = new Element('<input type="range" min="$min" max="$max" step="$step" value="$defaultVal"/>');
		root.append(label);
		var range = new hide.comp.Range(root, slider);
		range.onChange = function(b){
			s.setVar(name, range.value);
		}
		return root;
	}

	function createChekbox( s : FXScript, name : String, defaultVal : Bool ) : Element {
		var root = new Element('<div class="checkBox"></div>');
		var label = new Element('<label> $name : </label>');
		var checkbox = new Element('<input type="checkbox" value="$defaultVal"/>');
		checkbox.on("input", function(_) {
			s.setVar(name, checkbox.val() );
		});
		root.append(label);
		root.append(checkbox);
		return root;
	}

	#end
}
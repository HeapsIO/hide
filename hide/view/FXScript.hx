package hide.view;

enum FxAst {
	Block( a : Array<FxAst> );
	Var( get : Void -> Float );
	Const( v : Float );
	Set( set : Float -> Void, a : FxAst );
	Op( a : FxAst, b : FxAst, op : Float -> Float -> Float );
	Unop( a : FxAst, op : Float -> Float );
	If( cond : FxAst, eif : FxAst, eelse : FxAst );
}

enum ParamOption {
	Range( min : Float, max : Float );
}

enum FXParam {
	Float( name : String, value : Float, options : Array<ParamOption> );
	Int( name : String, value : Int, options : Array<ParamOption> );
}

enum FXVar {
	Float( value : Float );
	Int( value : Int );
}

class FXScript {

	public var fx : hide.prefab.fx.FX.FXAnimation;
	public var myVars : Map<String, FXVar> = [];
	public var ast : FxAst;
	public var params : Array<FXParam> = [];

	public function new(){
	}

	public function getSetter( p : String ) {
		var names = p.split('.');
		var i = 0;
		var root : h3d.scene.Object = fx;
		#if editor
		var fxRoot = fx.getObjectByName("FXRoot");
		if(fxRoot != null) root = fxRoot;
		#end
		var curObj : h3d.scene.Object = root.getObjectByName(names[i++]);
		while(curObj != null && i < p.length) {
			var next = curObj.getObjectByName(names[i++]);
			next != null ? curObj = next : break;
		}
		var field : String = "";
		for(index in i - 1 ... i)
			field += names[index];

		return switch(field){
			case "rotationX": function(v){
				var euler = curObj.getRotationQuat().toEuler();
				curObj.setRotation(v, euler.y, euler.z);};
			case "rotationY": function(v){
				var euler = curObj.getRotationQuat().toEuler();
				curObj.setRotation(euler.x, v, euler.z); };
			case "rotationZ": function(v){
				var euler = curObj.getRotationQuat().toEuler();
				curObj.setRotation(euler.x, euler.y, v);};
			default: function(v){ if(Reflect.hasField(curObj, field)) Reflect.setProperty(curObj, field, v); };
		}
	}

	public function getVar( n : String ) : Float {
		if(!myVars.exists(n))
			return 0.0;
		return switch myVars[n]{
			case Float(value): value;
			case Int(value): value;
		}
	}

	public function setVar( n : String, v : Float ) : Float {
		if(!myVars.exists(n))
			return 0.0;
		switch myVars[n]{
			case Float(value): myVars.set(n, FXVar.Float(v));
			case Int(value): myVars.set(n, FXVar.Int(Std.int(v)));
		}
		return switch myVars[n]{
			case Float(value): value;
			case Int(value): value;
		}
	}

	public function eval() {
		function eval(ast : FxAst) : Float {
			if(ast == null) return 0.0;
			switch (ast) {
				case Block(a):
					for(ast in a)
						eval(ast);
					return 0.0;
				case Var(get):
					return get();
				case Const(v):
					return v;
				case Set(set, a):
					var v = eval(a);
					set(v);
					return v;
				case Op(a, b, op):
					var va = eval(a);
					var vb = eval(b);
					return op(va,vb);
				case Unop(a, op):
					return op(eval(a));
				case If(cond, eif, eelse):
					return eval(cond) != 0 ? eval(eif) : eval(eelse);
			}
		}
		eval(ast);
	}
}

@:access(hide.view.FXEditor)
class FXScriptParser {

	public var firstParse = false;

	public function new(){
	}

	inline function getExpr(e : hscript.Expr) {
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
		var script = new FXScript();
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
			switch(getExpr(expr)){

				case EBlock(e):
					return Block( [for(expr in e) convert(expr)] );

				case EVar(n, t, e):
					if(e != null ) return Set(function(v){ script.setVar(n, v); }, convert(e));
					else return Var( function(){ return script.getVar(n); });

				case EField(e, f):
					return null;

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
						case "+": return Op( convert(e1), convert(e2), function(a,b) { return a + b; });
						case "-": return Op( convert(e1), convert(e2), function(a,b) { return a - b; });
						case "=":  switch(getExpr(e1)){
											case EIdent(v): return Set(function(val){ script.setVar(v, val); }, convert(e2));
											case EField(e,f):
												function getPath( expr : hscript.Expr ) : String {
													return switch(getExpr(expr)){
														case EField(e,f): getPath(e) + "." + f;
														case EIdent(v): v;
														default: null;
													}
												}
												var fullPath = getPath(e1);
												var setter = script.getSetter(fullPath);
												return Set( setter, convert(e2));
											default: return null;
										}
						default: return null;
					}

				case EUnop(op, prefix, e):
					return switch(op){
						case "++": Unop(convert(e), function(a){ return prefix ? ++a : a++; });
						case "--": Unop(convert(e), function(a){ return prefix ? --a : a--; });
						default: null;
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
									default:
								}
							default: null;
						}
					}
					if(e != null){
						switch(getExpr(e)){
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
									default:
								}
							default: null;
						}
					}
					if(e != null){
						switch(getExpr(e)){
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

	public function generateUI( s : FXScript, editor : FXEditor ){
		var elem = editor.element.find(".fx-scriptParams");
		elem.empty();
		var root = new Element('<div class="group" name="Params"></div>');
		for(p in s.params){
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
			}
		}
		elem.append(root);
	}

	function createSlider( s : FXScript, name : String, min : Float, max : Float, step : Float, defaultVal : Float ) : Element {
		var root = new Element('<div class="fx-slider"></div>');
		var label = new Element('<label> $name : </label>');
		var slider = new Element('<input type="range" min="$min" max="$max" step="$step" value="$defaultVal"/>');
		root.append(label);
		var range = new hide.comp.Range(root, slider);
		range.onChange = function(b){
			s.setVar(name, range.value);
		}
		return root;
	}

	#end
}
package hide.prefab.fx;

typedef Argument = { name : String, ?value : FxAst };

enum FxAst {
	Block( a : Array<FxAst> );
	Var( get : Void -> Float );
	Const( v : Float );
	Set( set : Float -> Void, a : FxAst );
	Op( a : FxAst, b : FxAst, op : Float -> Float -> Float );
	Unop( a : FxAst, op : Float -> Float );
	If( cond : FxAst, eif : FxAst, eelse : FxAst );
	Function( args : Array<hide.prefab.fx.Argument>, a : FxAst, name : String );
	Call( name : String, args : Array<FxAst> );
}

enum FXVar {
	Float( value : Float );
	Int( value : Int );
	Bool( value : Bool );
}

// UI
enum ParamOption {
	Range( min : Float, max : Float );
}
enum FXParam {
	Float( name : String, value : Float, options : Array<ParamOption> );
	Int( name : String, value : Int, options : Array<ParamOption> );
	Bool( name : String, value : Bool, options : Array<ParamOption> );
}

class FXScript {

	public var myVars : Map<String, FXVar> = [];
	public var params : Array<FXParam> = [];

	var fx : hide.prefab.fx.FX.FXAnimation;
	var ast : FxAst;
	var initAst : FxAst;
	var updateAst : FxAst;

	public function new( fx : hide.prefab.fx.FX.FXAnimation ){
		this.fx = fx;
	}

	public function getGetter( p : String ) : Void -> Float {
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
		if(curObj == null)
			return () -> 0.0;
		var field : String = "";
		for(index in i - 1 ... i)
			field += names[index];

		return switch(field){
			case "x": function(){ return curObj.x; };
			case "y": function(){ return curObj.y; };
			case "z": function(){ return curObj.z; };
			case "visible": function(){ return curObj.visible ? 1.0 : 0.0; };
			case "rotationX": function(){
				return curObj.getRotationQuat().toEuler().x;}
			case "rotationY": function(){
				return curObj.getRotationQuat().toEuler().y;}
			case "rotationZ": function(){
				return curObj.getRotationQuat().toEuler().z;}
			default: return function(){
				if(Reflect.hasField(curObj, field)){
					var p = Reflect.getProperty(curObj, field);
					return cast(p, Float);
				}
				else return 0.0;};
		}
	}

	public function getSetter( p : String ) : Float -> Void {
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
		if(curObj == null)
			return (v) -> {};
		var field : String = "";
		for(index in i - 1 ... i)
			field += names[index];

		return switch(field){
			case "x": function(v){ curObj.x = v; };
			case "y": function(v){ curObj.y = v; };
			case "z": function(v){ curObj.z = v; };
			case "visible": function(v){ curObj.visible = v > 0; };
			case "rotationX": function(v){
				var euler = curObj.getRotationQuat().toEuler();
				curObj.setRotation(v, euler.y, euler.z); };
			case "rotationY": function(v){
				var euler = curObj.getRotationQuat().toEuler();
				curObj.setRotation(euler.x, v, euler.z); };
			case "rotationZ": function(v){
				var euler = curObj.getRotationQuat().toEuler();
				curObj.setRotation(euler.x, euler.y, v); };
			default: {
				if(Reflect.hasField(curObj, field)) {
					var cur = Reflect.field(curObj, field);
					if(Std.is(cur, Value))
						(v) -> Reflect.setProperty(curObj, field, Value.VConst(v));
					else
						(v) -> Reflect.setProperty(curObj, field, v);
				}
				else (v) -> {};
			};
		}
	}

	public function getVar( n : String ) : Float {
		if(n == "time")  // TODO: support @global like hxsl
			return fx.localTime;
		if(!myVars.exists(n))
			return 0.0;
		if(myVars[n] == null)
			return 0.0;
		return switch myVars[n]{
			case Float(value): value;
			case Int(value): value;
			case Bool(value): value ? 1.0 : 0.0;
			default : 0.0;
		}
	}

	public function setVar( n : String, v : Float ) : Float {
		if(!myVars.exists(n))
			return 0.0;
		switch myVars[n]{
			case Float(value): myVars.set(n, FXVar.Float(v));
			case Int(value): myVars.set(n, FXVar.Int(Std.int(v)));
			case Bool(value):  myVars.set(n, FXVar.Bool( v > 0 ));
		}
		return switch myVars[n]{
			case Float(value): value;
			case Int(value): value;
			case Bool(value): value ? 1.0 : 0.0;
		}
	}

	function call( f : String, args : Array<FxAst>) : Float {
		switch(f){
			case "rand": return hxd.Math.random();
			case "mix": return hxd.Math.lerp(eval(args[0]), eval(args[1]), eval(args[2]));
			case "clamp": return hxd.Math.clamp(eval(args[0]), eval(args[1]), eval(args[2]));
			default: return 0.0;
		}
	}

	function eval(ast : FxAst) : Float {
		if(ast == null) return 0.0;
		switch (ast) {
			case Block(a):
				for(ast in a)
					eval(ast);
				return 0.0;
			case Call(a, args):
				return call(a, args);
			case Function(args, a, name):
				return 0.0; // TO DO
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

	public function init() {
		eval(initAst);
	}

	public function update() {
		eval(updateAst);
	}
}
package hide.prefab.fx;

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
	Bool( name : String, value : Bool, options : Array<ParamOption> );
}

enum FXVar {
	Float( value : Float );
	Int( value : Int );
	Bool( value : Bool );
}

class FXScript {

	public var fx : hide.prefab.fx.FX.FXAnimation;
	public var myVars : Map<String, FXVar> = [];
	public var ast : FxAst;
	public var params : Array<FXParam> = [];

	public function new(){
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
			default: function(v){
				if(Reflect.hasField(curObj, field))
					Reflect.setProperty(curObj, field, v); };
		}
	}

	public function getVar( n : String ) : Float {
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
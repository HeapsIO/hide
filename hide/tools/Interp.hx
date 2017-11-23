package hide.tools;

class Interp extends hscript.Interp {

	var ide : hide.ui.Ide;

	public function new() {
		ide = hide.ui.Ide.inst;
		super();
	}

	public function shareEnum( e : Enum<Dynamic> ) {
		for( c in e.getConstructors() )
			variables.set(c, Reflect.field(e, c));
	}

	public function shareObject( obj : Dynamic ) {
		for( f in Type.getInstanceFields(Type.getClass(obj)) ) {
			var v = Reflect.field(obj, f);
			if( Reflect.isFunction(v) )
				variables.set(f, Reflect.makeVarArgs(function(args) return Reflect.callMethod(obj,v,args)));
		}
	}

	override function set(o:Dynamic, f:String, v:Dynamic) : Dynamic {
		var fset = Reflect.field(o, "hscriptSet");
		if( fset != null )
			return Reflect.callMethod(o, fset, [f,v]);
		return super.set(o, f, v);
	}

	override function get(o:Dynamic, f:String) : Dynamic {
		var fget = Reflect.field(o, "hscriptGet");
		if( fget != null )
			return Reflect.callMethod(o, fget, [f]);
		return super.get(o, f);
	}

	override function cnew(cl:String, args:Array<Dynamic>):Dynamic {
		var c = Type.resolveClass(cl);
		if( c == null )
			try {
				c = resolve(cl);
			} catch( e : hscript.Expr.Error ) {
			}
		if( c == null ) {
			var s = ide.shaderLoader.load(cl);
			if( s == null )
				error(EUnknownVariable(cl));
			return s;
		}
		return Type.createInstance(c,args);
	}

}
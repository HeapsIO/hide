package hide.tools;

// make sure these classes are compiled
import h3d.anim.SmoothTarget;

class Interp extends hscript.Interp {

	var ide : hide.Ide;

	public function new() {
		ide = hide.Ide.inst;
		super();
		// share some classes
		variables.set("hxd", { Res : new ResourceLoader([]) });
		variables.set("h3d", { mat : { Texture : h3d.mat.Texture } });
		variables.set("haxe", { Json : haxe.Json });
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

	override function fcall(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic {
		var fun = get(o, f);
		if( !Reflect.isFunction(fun) ) {
			if( fun == null )
				throw o + " has no function " + f;
			throw o + "." + f + " is not a function";
		}
		return call(o, fun, args);
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

class ResourceLoader {

	var __path : Array<String>;

	public function new(p) {
		__path = p;
	}

	public function toTexture() {
		return hide.comp.Scene.getCurrent().loadTextureDotPath(__path.join("."));
	}

	function resolvePath() {
		var ide = hide.Ide.inst;
		var dir = __path.copy();
		var name = dir.pop();
		var dir = dir.join("/");
		for( f in sys.FileSystem.readDirectory(ide.getPath(dir)) )
			if( f.substr(0, f.lastIndexOf(".")) == name )
				return dir + "/" + f;
		return null;
	}

	public function hscriptGet( field : String ) : Dynamic {

		var f = Reflect.field(this,field);
		if( f != null )
			return Reflect.makeVarArgs(function(args) return Reflect.callMethod(this, f, args));

		if( field == "entry" ) {
			var path = resolvePath();
			return hxd.res.Loader.currentInstance.load(path).entry;
		}

		var p = __path.copy();
		p.push(field);
		return new ResourceLoader(p);
	}

}

package hide;
#if macro
import haxe.macro.Compiler in C;
import haxe.macro.Context;
#end

class Plugin {

	#if macro

	static var haxelibRoot(get,never) : String;
	static function get_haxelibRoot() {
		return switch(Sys.systemName()) {
			case "Windows": sys.io.File.getContent(Sys.getEnv("USERPROFILE")+"/.haxelib");
			case "Linux", "BSD", "Mac":	sys.io.File.getContent(Sys.getEnv("HOME")+"/.haxelib");
			default: throw "Unknown platform";
		}
	}

	static var EXCLUDES = [
		"hide",
		"hrt",

		"h2d",
		"h3d",
		"hxd",
		"hxsl",
		"hxbit",

		"haxe",
		"js",
		"sys",
		"hscript",
		"cdb",
		"format",
		"domkit",

		"HxOverrides",
		"Math",
		"EReg",
		"Lambda",
		"IntIterator",
		"Reflect",
		"Std",
		"StringBuf",
		"StringTools",
		"DateTools",
		"Sys",
		"_Sys",
		"Type",
		"ValueType",
		"Xml",
		"_Xml",		
	];

	static function getLibraryPath( libName ) {
		var libPath = haxelibRoot+"/"+libName;
		var dev = try StringTools.trim(sys.io.File.getContent(libPath+"/.dev")) catch( e : Dynamic ) null;
		if( dev != null )
			libPath = dev;
		else {
			var cur = try StringTools.trim(sys.io.File.getContent(libPath+"/.current")) catch( e : Dynamic ) null;
			if( cur == null )
				throw "Library not installed '"+libName+"'";
			libPath += "/"+cur.split(".").join(",");
		}
		var json = try haxe.Json.parse(sys.io.File.getContent(libPath+"/haxelib.json")) catch( e : Dynamic ) null;
		if( json != null && json.classPath != null )
			libPath += "/"+json.classPath;
		return libPath;
	}

	static function init() {
		var hidePath = getLibraryPath("hide");
		for( f in sys.io.File.getContent(hidePath+"/common.hxml").split("\n") ) {
			var f = StringTools.trim(f);
			if( f == "" ) continue;
			var pl = f.split(" ");
			var value = pl[1];
			switch( pl[0] ) {
			case "-lib":
				if( value == "heaps" ) continue;
				if( value == "hxnodejs" ) {
					// should be set with -cp or will conflict with macro code
					if( !Context.defined("hxnodejs") ) Context.error("Please add -lib hxnodejs", Context.currentPos());
					continue;
				}
				C.define(value,"1");
				C.addClassPath(getLibraryPath(value));
			case "-D":
				C.define(value,"1");
			case "-cp":
				C.addClassPath(hidePath+"/"+value);
			default:
			}
		}		
		for( e in EXCLUDES )
			C.exclude(e);
		hide.tools.Macros.initHide();
	}
	#end

}
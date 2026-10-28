package hide;
#if macro
import haxe.macro.Compiler in C;
import haxe.macro.Compiler.PackageRule;
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

		"haxe",
		"js",
		"sys",
		"hscript",
		"cdb",
		"format",
		"domkit",
		"electron",

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
		#if (domkit && hui)
		var parser : hrt.ui.CssParser = null; // force compilation of css parser
		#end

		var hidePath = getLibraryPath("hide");

		if( !Context.defined("js") && !Context.defined("hl") )
			Context.fatalError("Hide plugin only support js or hl targets", Context.currentPos());

		for( f in sys.io.File.getContent(hidePath+"/common.hxml").split("\n") ) {
			var f = StringTools.trim(f);
			if( f == "" ) continue;
			var pl = f.split(" ");
			var value = pl[1];
			switch( pl[0] ) {
			case "-lib":
				if( value == "heaps" ) continue;
				if ( value == "domkit" ) {
					// should be set with -lib or will conflict with macro code
					if (!Context.defined("domkit")) {
						Context.error("Please add -lib domkit", Context.currentPos());
					}
					continue;
				}


				if( !Context.defined(value) )
					C.define(value,"1");
				C.addClassPath(getLibraryPath(value));
			case "-D":
				C.define(value,"1");
			case "-cp":
				C.addClassPath(hidePath+"/"+value);
			default:
			}
		}

		if( Context.defined("js") ) {
			// should be set with -cp or will conflict with macro code
			if( !Context.defined("hxnodejs") ) Context.error("Please add -lib hxnodejs", Context.currentPos());
			for( d in ["js-classic", "js-unflatten", "editor", "multidriver"] )
				C.define(d, "1");
			C.addClassPath(hidePath+"/hide_js");
			C.addClassPath(hidePath+"/hide_js/libs");
			if( Context.defined("dx12") ) {
				// no macro API for --remap
				if( !C.getConfiguration().packageRules.get("hl").match(Remap("hlemu")) )
					Context.fatalError("-D dx12 flag also need a --remap hl:hlemu build argument", Context.currentPos());
				// hlemu.Macros.init(), which is not in the macro class path
				for( p in ["dx", "h3d.impl"] )
					C.addGlobalMetadata(p, "@:build(hlemu.Macros.build())", true, true, false);
				for( e in ["dx", "hlemu"] )
					C.exclude(e);
			}
			@:privateAccess hide.html.DomPatch.init();
			@:privateAccess hide.html.WebComponentMacro.init();
			// js-classic outputs root types as globals : prefix them so they can't overwrite browser globals (e.g. Data.Element)
			Context.onGenerate(function(types) {
				for( t in types ) {
					var b : haxe.macro.Type.BaseType = switch( t ) {
					case TInst(c, _): c.get();
					case TEnum(e, _): e.get();
					default: null;
					}
					if( b == null || b.isExtern || b.meta.has(":native") )
						continue;
					// abstract impls are generated with the abstract path
					var path : haxe.macro.Type.BaseType = switch( t ) {
					case TInst(_.get().kind => KAbstractImpl(a), _): a.get();
					default: b;
					}
					// excluded types are referenced from hide.js under their own name
					if( path.pack.length == 0 && !EXCLUDES.contains(path.name) )
						b.meta.add(":native", [macro $v{"$plugin_" + path.name}], b.pos);
				}
			});
		} else
			C.addClassPath(hidePath+"/hide_hl");

		for( e in EXCLUDES )
			C.exclude(e);
	}
	#end

}
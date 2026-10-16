package hide.tools.migrate;

import hrt.prefab.fx.FX;

typedef Change = { path : String, kind : String };

typedef FileReport = {
	var file : String;
	/** By path in the file **/
	var changes : Array<Change>;
	/** Old data approximated or left as it is **/
	var warnings : Array<String>;
	/** Old data that cannot be upgraded, left as it is **/
	var errors : Array<String>;
	/** `path`: the parent, at the original path of the object; `child`: the new name of the object **/
	var parents : Array<{ path : String, child : String, reason : String }>;
}

/** The files of a project, for the overrides of the references of a file **/
interface Context {
	/** The data of the file `path` as it is stored, a fresh copy, null if there is none **/
	function readRaw( path : String ) : Null<Dynamic>;
	/** The data of the file `path` migrated, a fresh copy, null if there is none **/
	function migrated( path : String ) : Null<Dynamic>;
	/** Migrates `data` as if it was the file `path` **/
	function upgradeAs( data : Dynamic, path : String ) : Dynamic;
}

typedef FileResult = {
	var path : String;
	/** Migrated in place **/
	var data : Dynamic;
	var changed : Bool;
	var report : FileReport;
}

typedef ProjectResult = {
	var files : Array<FileResult>;
	var errors : Array<String>;
}

/**
	Upgrades FX data saved in an older version (`hrt.prefab.fx.FX.VERSION`, on the root of the data:
	an FX, or an emitter out of any FX) to the current one, one step per version (`STEPS`).

	- On a whole project, once: `migrateProject`, or the tool (`Cli`, hide/migrate.hxml). The project is
	  migrated in memory, the files that change are written by `toText` (the prefab save of hide). The
	  overrides of the references to the migrated files are migrated with them. The upgrade reads the
	  prefab classes (the defaults of their fields, what their curves animate): the tool of a game with
	  its own prefabs is built with them, the prefab types the build does not have are reported as errors.
	- On load, as a fallback, when this module is compiled in (`--macro include("hide.tools.migrate")`):
	  it is `FX.upgrader`. FX data is then upgraded alone, in memory, once per loaded resource. The
	  overrides of its references are kept: they are applied on the files they override, still in the
	  old version, and the result is upgraded when it loads.
**/
@:keep
class Migrate {

	public static var STEPS : Map<Int, (data : Dynamic, root : Bool, report : FileReport) -> Void> = [
		0 => (data, root, report) -> new Upgrade0(null, report).run(data, root),
	];

	/** Loaded as prefabs (`hxd.res.Config`) **/
	public static var EXTENSIONS = ["prefab", "fx", "fx2d", "l3d"];

	static function __init__() {
		hrt.prefab.fx.FX.upgrader = fallback;
	}

	public static function newReport( file : String ) : FileReport {
		return { file: file, changes: [], warnings: [], errors: [], parents: [] };
	}

	public static function versionOf( data : Dynamic ) : Int {
		var v : Dynamic = Reflect.field(data, "version");
		return v == null ? 0 : Std.int(v);
	}

	/** Upgrades in place the root of FX data from `version`, `root` when it is the root of its file. **/
	public static function upgradeTree( data : Dynamic, version : Int, root : Bool, report : FileReport ) {
		for( v in version...FX.VERSION )
			STEPS.get(v)(data, root, report);
		// the FX inside are upgraded with it
		function mark( d : Dynamic ) {
			if( isFX(d) ) RawNode.setField(d, "version", FX.VERSION);
			var children : Array<Dynamic> = Reflect.field(d, "children");
			if( children != null ) for( c in children ) mark(c);
		}
		mark(data);
		RawNode.setField(data, "version", FX.VERSION);
	}

	static function isA( d : Dynamic, cl : Class<hrt.prefab.Prefab> ) {
		var c = RawNode.classOf(Reflect.field(d, "type"));
		return c != null && hrt.prefab.Prefab.isOfType(c, cl);
	}

	static function isFX( d : Dynamic ) return isA(d, hrt.prefab.fx.FX) || isA(d, hrt.prefab.fx.FX2D);
	static function isEmitter( d : Dynamic ) return isA(d, hrt.prefab.fx.Emitter) || isA(d, hrt.prefab.fx.Emitter2D);

	/** Migrates in place the data of the file `path`: its FX data, and the overrides of its references (`ctx` reads the files they override). **/
	public static function migrateData( data : Dynamic, path : String, ctx : Context ) : FileResult {
		var report = newReport(path);
		var changed = false;
		function walk( d : Dynamic ) {
			if( d == null || !Reflect.isObject(d) ) return;
			if( isFX(d) || isEmitter(d) ) {
				var v = versionOf(d);
				if( v != FX.VERSION ) {
					upgradeTree(d, v, d == data, report);
					changed = true;
				}
				return;
			}
			var children : Array<Dynamic> = Reflect.field(d, "children");
			if( children != null ) for( c in children ) walk(c);
		}
		walk(data);
		if( Upgrade0.upgradeReferences(data, ctx, report) )
			changed = true;
		return { path: path, data: data, changed: changed, report: report };
	}

	/** The file of migrated data, as hide saves it **/
	public static function toText( data : Dynamic ) : String {
		var p = @:privateAccess hrt.prefab.Prefab.createFromDynamic(hrt.prefab.Diff.deepCopy(data), null, new hrt.prefab.ContextShared(null, false));
		return haxe.Json.stringify(@:privateAccess p.serialize(), null, "\t");
	}

	/** Migrates every prefab file under `resDir` in memory: nothing is written. **/
	public static function migrateProject( resDir : String, ?extensions : Array<String> ) : ProjectResult {
		return run(new ProjectContext(resDir, extensions ?? EXTENSIONS));
	}

	/** Migrates a project given as its files (resource path => text), in memory **/
	static function migrateTexts( files : Map<String, String> ) : ProjectResult {
		return run(new ProjectContext(null, null, files));
	}

	static function run( ctx : ProjectContext ) : ProjectResult {
		var out : ProjectResult = { files: [], errors: [] };
		for( path in ctx.paths ) {
			var r = try ctx.result(path) catch( e : Dynamic ) {
				out.errors.push('$path: $e');
				null;
			}
			if( r != null )
				out.files.push(r);
		}
		for( e in ctx.errors )
			if( out.errors.indexOf(e) < 0 )
				out.errors.push(e);
		return out;
	}

	public static dynamic function log( msg : String ) {
		#if sys
		Sys.println(msg);
		#else
		trace(msg);
		#end
	}

	static var warned = false;

	/** `FX.upgrader` **/
	public static function fallback( data : Dynamic, version : Int, root : Bool ) {
		var report = newReport(Reflect.field(data, "name"));
		upgradeTree(data, version, root, report);
		if( !warned ) {
			warned = true;
			log('[hide] FX data of version $version is upgraded to version ${FX.VERSION} on load. Migrate the project once with the migration tool (hide/migrate.hxml).');
		}
		for( w in report.warnings )
			log('[hide] warning: $w');
		for( e in report.errors )
			log('[hide] error: $e');
	}
}

private class ProjectContext implements Context {
	var dir : String;
	public var paths : Array<String> = [];
	public var errors : Array<String> = [];
	var texts = new Map<String, String>();
	var results = new Map<String, FileResult>();
	var inProgress = new Map<String, Bool>();

	public function new( dir : Null<String>, extensions : Null<Array<String>>, ?files : Map<String, String> ) {
		if( files != null ) {
			for( path => text in files ) {
				texts.set(path, text);
				paths.push(path);
			}
			paths.sort(Reflect.compare);
			return;
		}
		this.dir = haxe.io.Path.removeTrailingSlashes(StringTools.replace(dir, "\\", "/"));
		function scan( rel : String ) {
			var full = rel == "" ? this.dir : this.dir + "/" + rel;
			var entries = sys.FileSystem.readDirectory(full);
			entries.sort(Reflect.compare);
			for( f in entries ) {
				var r = rel == "" ? f : rel + "/" + f;
				if( sys.FileSystem.isDirectory(full + "/" + f) ) {
					if( f.charAt(0) != "." ) scan(r);
				} else if( extensions.indexOf(haxe.io.Path.extension(f).toLowerCase()) >= 0 )
					paths.push(r);
			}
		}
		scan("");
	}

	function text( path : String ) : Null<String> {
		if( texts.exists(path) || dir == null ) return texts.get(path);
		var full = dir + "/" + path;
		var t = sys.FileSystem.exists(full) ? sys.io.File.getContent(full) : null;
		texts.set(path, t);
		return t;
	}

	public function readRaw( path : String ) : Null<Dynamic> {
		var t = text(path);
		return t == null ? null : try haxe.Json.parse(t) catch( e : Dynamic ) null;
	}

	public function result( path : String ) : Null<FileResult> {
		var r = results.get(path);
		if( r != null ) return r;
		var data = readRaw(path);
		if( data == null ) return null;
		if( inProgress.exists(path) ) {
			errors.push('$path: references itself through other files, its overrides are kept as they are');
			return null;
		}
		inProgress.set(path, true);
		r = try Migrate.migrateData(data, path, this) catch( e : Dynamic ) {
			inProgress.remove(path);
			throw e;
		}
		inProgress.remove(path);
		results.set(path, r);
		return r;
	}

	public function migrated( path : String ) : Null<Dynamic> {
		var r = try result(path) catch( e : Dynamic ) {
			errors.push('$path: $e');
			null;
		}
		return r == null ? null : hrt.prefab.Diff.deepCopy(r.data);
	}

	public function upgradeAs( data : Dynamic, path : String ) : Dynamic {
		return Migrate.migrateData(data, path, this).data;
	}
}

package hide.tools;

using Lambda;
import hide.tools.Report.*;
import hide.tools.Report.ReportBlock;
import hide.tools.Report.ReportSection;
import hide.tools.Report.ReportData;
import hide.tools.Report.ReportRow;

typedef ReportShader = { name : String, bits : Int };
typedef ReportEntry = { mode : String, shaders : Array<ReportShader>, tokens : Array<String> };
typedef ReportConst = { name : String, pos : Int, bits : Int };
typedef ReportAxis = { label : String, slot : Bool, shader : String, mask : Int, groups : Int, lists : Int, extra : Int, values : Map<String, Int>, examples : Array<{ pos : Int, entries : Array<ReportEntry> }> };

/**
	Game specific parts of the shader report, registered by a hide plugin:
	`static var _ = hide.tools.ShaderReport.register(new MyShaderReportExtension());`
	A section with the id of a section of the report replaces it.
**/
class ShaderReportExtension {
	public function new() {
	}
	public function init( r : ShaderReport ) {
	}
	public function visitPrefab( r : ShaderReport, o : Dynamic, file : String, path : String ) {
	}
	public function codeRoots( r : ShaderReport, roots : Array<String> ) {
	}
	public function optionPatterns( r : ShaderReport ) : Array<String> {
		return [];
	}
	public function summary( r : ShaderReport ) : Array<ReportBlock> {
		return [];
	}
	public function sections( r : ShaderReport ) : Array<ReportSection> {
		return [];
	}
}

class ShaderReport {

	public static inline var ENTRY_KB = 300;
	public static inline var ENTRY_MS = 4.5;
	public static inline var EXAMPLES = 3;

	public static var extensions : Array<ShaderReportExtension> = [];

	static var _ = Report.register("shaders", { title : "Shader report", editParams : editParams, generate : generate });

	public static function register( e : ShaderReportExtension ) {
		extensions.push(e);
		return true;
	}

	public static function defaultCache() {
		var ide = hide.Ide.inst;
		var path : String = ide.currentConfig.get("shaderReport.cache") ?? "bin/refshaders.cache2";
		return haxe.io.Path.isAbsolute(path) ? path : ide.projectDir + "/" + path;
	}

	public var path(default, null) : String;
	public var entries(default, null) : Array<ReportEntry> = [];
	public var layouts(default, null) : Map<String, Array<ReportConst>> = [];
	public var prefabHits(default, null) : Map<String, Array<String>> = [];
	public var lightHits(default, null) : Map<String, Array<String>> = [];
	public var suns(default, null) : Map<String, { path : String, desc : String, count : Int }> = [];
	public var rpUsers(default, null) : Map<String, Array<String>> = [];
	public var optionConsts(default, null) : Map<String, Array<String>> = [];
	public var codeOptions(default, null) : Array<{ key : String, file : String, line : Int, text : String }> = [];
	public var linkErrors(default, null) = 0;
	var postings : Map<String, Array<Int>>;
	var codeHits : Map<String, Array<{ file : String, line : Int, text : String }>> = [];
	var codeFiles : Map<String, String> = [];
	var targets : Array<{ file : String, tag : String, shaders : Array<String> }> = [];
	var byNames : Map<String, Array<ReportEntry>>;
	var bySlot : Map<String, ReportEntry>;
	var programs : Map<String, String>;
	var runtimes : Map<String, hxsl.RuntimeShader> = [];
	var linkCache : hxsl.CacheFile2;
	var linkLoader : hxsl.CacheFile2.CacheFile2Loader;
	var linkJobs : Array<{ info : Dynamic, mode : hxsl.RuntimeShader.LinkMode }>;
	var linkPos = 0;
	var graphs : Map<String, hxsl.Shader> = [];

	public function new( path : String ) {
		this.path = path;
	}

	static function editParams( bar : js.html.Element, params : { ?cache : String }, onChange : Void -> Void ) {
		var ide = hide.Ide.inst;
		el("label", null, bar).textContent = "Cache";
		var cache : js.html.InputElement = cast el("input", "cache", bar);
		cache.value = params.cache ?? defaultCache();
		cache.onchange = () -> {
			params.cache = cache.value;
			onChange();
		};
		var browse = el("button", null, bar);
		browse.textContent = "...";
		browse.onclick = () -> ide.chooseFile(["cache2"], (f) -> {
			if( f == null )
				return;
			cache.value = params.cache = ide.getPath(f);
			onChange();
		});
	}

	public static function generate( params : { ?cache : String }, onProgress : String -> Void, onDone : ReportData -> Void, onError : haxe.Exception -> Void ) {
		var r = new ShaderReport(params.cache ?? defaultCache());
		function finish() {
			try {
				for( e in extensions )
					e.init(r);
				for( e in r.entries )
					for( s in e.shaders )
						r.layout(s.name);
				onProgress("Scanning prefabs and code...");
				r.scanPrefabs();
				r.scanCode();
				r.scanOptions();
				onDone(r.makeReport());
			} catch( e : haxe.Exception )
				onError(e);
		}
		function link() {
			var done = try r.linkSome(0.05) catch( e : haxe.Exception ) {
				onError(e);
				return;
			}
			if( done ) {
				onProgress("Scanning prefabs and code...");
				haxe.Timer.delay(finish, 0);
				return;
			}
			onProgress('Linking ${r.linkPos} / ${r.linkJobs.length} lists...');
			haxe.Timer.delay(link, 0);
		}
		try {
			r.load();
			r.startLink();
		} catch( e : haxe.Exception ) {
			onError(e);
			return;
		}
		link();
	}

	function load() {
		if( !sys.FileSystem.exists(path) )
			throw 'File not found: $path';
		var modes = ["Default", "Batch", "Compute"];
		var section = 0;
		var lines = sys.io.File.getContent(path).split("\n");
		for( i in 1...lines.length ) {
			var l = StringTools.trim(lines[i]);
			if( l == "" ) {
				section++;
				continue;
			}
			if( section >= 2 && section <= 4 ) {
				var e = parseEntry(modes[section - 2], l);
				if( e != null )
					entries.push(e);
			}
		}
	}

	public static function parseEntry( mode : String, line : String ) : ReportEntry {
		var parts = line.split(";");
		if( parts.length < 2 )
			return null;
		var shaders = [];
		for( s in parts[1].split(":") ) {
			var f = s.split(",");
			if( f.length >= 3 )
				shaders.push({ name : f[0], bits : Std.parseInt(f[2]) });
		}
		return shaders.length == 0 ? null : { mode : mode, shaders : shaders, tokens : [for( s in shaders ) s.name + "@" + s.bits] };
	}

	// links every list like hxsl.CacheFile2 does, without compiling them on the driver
	function startLink() @:privateAccess {
		linkCache = new hxsl.CacheFile2("", false);
		linkLoader = new hxsl.CacheFile2.CacheFile2Loader(linkCache);
		var version = hxsl.CacheFile2.VERSION;
		var magic = sys.io.File.getContent(path).split("\n")[0];
		hxsl.CacheFile2.VERSION = Std.parseInt(magic.substr(4)) ?? version;
		var loaded = try hxsl.CacheFile2.loadFile(linkLoader, path) catch( e : Dynamic ) false;
		hxsl.CacheFile2.VERSION = version;
		if( !loaded )
			return;
		for( lk in linkLoader.lkInfos )
			linkLoader.ssMap.set(lk.name, linkCache.getLinkShader(lk.vars).shader);
		for( e in entries )
			for( s in e.shaders )
				if( StringTools.endsWith(s.name, ".shgraph") && !linkLoader.ssMap.exists(s.name) ) {
					var sh = shaderGraph(s.name);
					if( sh != null )
						linkLoader.ssMap.set(s.name, sh.shader);
				}
		programs = new Map();
		linkJobs = [];
		for( m in [
			{ infos : linkLoader.rtInfosDefault, mode : hxsl.RuntimeShader.LinkMode.Default },
			{ infos : linkLoader.rtInfosCompute, mode : hxsl.RuntimeShader.LinkMode.Compute },
			{ infos : linkLoader.rtInfosBatch, mode : hxsl.RuntimeShader.LinkMode.Batch },
		] )
			for( info in m.infos )
				linkJobs.push({ info : info, mode : m.mode });
	}

	function linkSome( maxTime : Float ) @:privateAccess {
		var end = haxe.Timer.stamp() + maxTime;
		while( linkJobs != null && linkPos < linkJobs.length && haxe.Timer.stamp() < end ) {
			var job = linkJobs[linkPos++];
			var info = job.info;
			var sl = try linkLoader.makeShaderList(info.sl, job.mode) catch( e : Dynamic ) null;
			var rt = sl == null ? null : try linkCache.link(sl, job.mode) catch( e : Dynamic ) null;
			if( rt == null ) {
				linkErrors++;
				continue;
			}
			if( job.mode == Default )
				linkLoader.rtMap.set(info.sign, { rt : rt, sl : sl });
			var key = job.mode.getName() + " " + [for( s in info.sl ) s.name + "@" + s.constBits].join(" ");
			programs.set(key, rt.signature);
			runtimes.set(key, rt);
		}
		return linkJobs == null || linkPos >= linkJobs.length;
	}

	function programCode( e : ReportEntry ) {
		var rt = runtimes.get(e.mode + " " + e.tokens.join(" "));
		return rt == null ? "" : [for( s in rt.getShaders() ) hxsl.Printer.shaderToString(s.data)].join("\n");
	}

	public function program( e : ReportEntry ) {
		return programs?.get(e.mode + " " + e.tokens.join(" "));
	}

	function codeDiff( a : ReportEntry, b : ReportEntry ) {
		var la = programCode(a).split("\n");
		var lb = programCode(b).split("\n");
		var start = 0;
		while( start < la.length && start < lb.length && la[start] == lb[start] )
			start++;
		var end = 0;
		while( end < la.length - start && end < lb.length - start && la[la.length - 1 - end] == lb[lb.length - 1 - end] )
			end++;
		function part( l : Array<String> ) {
			var lines = l.slice(start, l.length - end);
			return esc((lines.length > 30 ? lines.slice(0, 30).concat(["..."]) : lines).join("\n"));
		}
		return details("code that differs", '${listHtml(a, -1)}<pre>${part(la)}</pre>${listHtml(b, -1)}<pre>${part(lb)}</pre>');
	}

	function scanOptions() {
		var patterns = [];
		for( p in (hide.Ide.inst.currentConfig.get("shaderReport.optionPatterns") : Array<String>) ?? [] )
			patterns.push(p);
		for( e in extensions )
			for( p in e.optionPatterns(this) )
				if( !patterns.contains(p) )
					patterns.push(p);
		if( patterns.length == 0 )
			return;
		var done = new Map<String, Bool>();
		for( e in entries ) {
			if( e.tokens.exists(t -> StringTools.startsWith(t, "h3d.shader.Base2d@")) )
				continue;
			for( s in e.shaders ) {
				if( done.exists(s.name) )
					continue;
				done.set(s.name, true);
				var l = layout(s.name);
				if( l != null )
					for( c in l )
						for( h in codeFor(s.name, c.name) )
							if( patterns.exists(p -> h.text.indexOf(p) >= 0) ) {
								markOption(s.name + "." + c.name, h.file.substr(h.file.lastIndexOf("/") + 1) + ":" + h.line);
								codeOptions.push({ key : s.name + "." + c.name, file : h.file, line : h.line, text : h.text });
							}
			}
		}
	}

	public function markOption( key : String, label : String ) {
		var l = optionConsts.get(key);
		if( l == null ) {
			l = [];
			optionConsts.set(key, l);
		}
		if( !l.contains(label) )
			l.push(label);
	}

	public function optionLabels( shader : String, const : String ) {
		var cl = Type.resolveClass(shader);
		var name = shader;
		while( name != null ) {
			var l = optionConsts.get(name + "." + const);
			if( l != null )
				return l;
			cl = cl == null ? null : Type.getSuperClass(cl);
			name = cl == null ? null : Type.getClassName(cl);
		}
		return null;
	}

	public function inherits( name : String, base : String ) {
		var cl = Type.resolveClass(name);
		while( cl != null ) {
			if( Type.getClassName(cl) == base )
				return true;
			cl = Type.getSuperClass(cl);
		}
		return name == base;
	}

	public function countWith( key : String, from : String ) {
		var i = key.lastIndexOf(".");
		var shader = key.substr(0, i), const = key.substr(i + 1);
		var values = [for( v in from.split("/") ) Std.parseInt(v)];
		var match = new Map<String, Bool>();
		var n = 0;
		for( e in entries )
			for( s in e.shaders ) {
				var m = match.get(s.name);
				if( m == null ) {
					m = inherits(s.name, shader);
					match.set(s.name, m);
				}
				var c = m ? Lambda.find(layout(s.name) ?? [], c -> c.name == const) : null;
				if( c != null && values.contains(constValue(c, s.bits)) ) {
					n++;
					break;
				}
			}
		return n;
	}

	function namesKey( e : ReportEntry ) {
		return e.mode + " " + [for( s in e.shaders ) s.name].join(" ");
	}

	public function closestList( e : ReportEntry, label : String ) : { base : ReportEntry, text : String } {
		if( byNames == null ) {
			byNames = new Map();
			bySlot = new Map();
			for( x in entries ) {
				var k = namesKey(x);
				var l = byNames.get(k);
				if( l == null ) {
					l = [];
					byNames.set(k, l);
				}
				l.push(x);
				for( i in 1...x.shaders.length )
					bySlot.set(slotKey(x, i, true), x);
			}
		}
		var best : ReportEntry = null, diff : Array<Int> = null;
		for( c in byNames.get(namesKey(e)) ?? [] ) {
			var d = [for( k => s in e.shaders ) if( s.bits != c.shaders[k].bits ) k];
			if( diff == null || d.length < diff.length ) {
				best = c;
				diff = d;
			}
		}
		if( best != null && diff.length == 0 )
			return { base : best, text : "already in the cache" };
		if( best != null )
			return { base : best, text : "same as a list of the cache except " + [for( k in diff ) {
				var s = e.shaders[k], was = best.shaders[k].bits, mask = s.bits ^ was;
				var l = layout(s.name);
				if( l != null )
					for( c in l )
						if( constValue(c, mask) != 0 )
							markOption(s.name + "." + c.name, label);
				s.name + " " + decode(s.name, was, mask) + " -> " + decode(s.name, s.bits, mask);
			}].join(", ") };
		for( i in 1...e.shaders.length ) {
			var c = bySlot.get(slotKey(e, i, true));
			if( c != null ) {
				markOption(e.shaders[i].name, label);
				return { base : c, text : "same as a list of the cache except " + c.tokens[i] + " -> " + e.tokens[i] };
			}
		}
		return { base : null, text : "no similar list in the cache" };
	}

	public static function add( map : Map<String, Array<String>>, key : String, file : String ) {
		var l = map.get(key);
		if( l == null ) {
			l = [];
			map.set(key, l);
		}
		if( !l.contains(file) )
			l.push(file);
	}

	function scanPrefabs() {
		var res = hide.Ide.inst.resourceDir;
		function walk( dir : String ) {
			for( f in sys.FileSystem.readDirectory(res + "/" + dir) ) {
				var rel = dir == "" ? f : dir + "/" + f;
				var p = res + "/" + rel;
				if( sys.FileSystem.isDirectory(p) ) {
					if( f.charAt(0) != "." )
						walk(rel);
				} else if( StringTools.endsWith(f, ".prefab") || StringTools.endsWith(f, ".fx") || StringTools.endsWith(f, ".rp") ) {
					var text = sys.io.File.getContent(p);
					if( text.indexOf('"source"') < 0 && text.indexOf('"Directional"') < 0 )
						continue;
					var json : Dynamic = try haxe.Json.parse(text) catch( e : Dynamic ) null;
					if( json == null )
						continue;
					var lights : Array<Dynamic> = [];
					visit(json, rel, lights);
					var main = lights.filter(l -> l.o.isMainLight == true);
					if( main.length == 0 )
						main = lights.slice(0, 1);
					for( l in main ) {
						addLight(l.o, rel);
						var path : String = l.path;
						if( StringTools.endsWith(f, ".rp") )
							suns.set(rel, { path : path.substr(1), desc : sunDesc(l.o), count : lights.length });
					}
				}
			}
		}
		walk("");
	}

	static function shaderName( o : Dynamic ) : String {
		var source : String = o.source;
		if( source == null || o.props == null )
			return null;
		if( StringTools.endsWith(source, ".hx") )
			return source.substr(0, source.length - 3).split("/").join(".");
		return StringTools.endsWith(source, ".shgraph") ? source : null;
	}

	function visit( o : Dynamic, file : String, lights : Array<Dynamic>, path = "" ) {
		for( e in extensions )
			e.visitPrefab(this, o, file, path);
		var source : String = o.source;
		var props : Dynamic = o.props;
		if( source != null && props != null && (StringTools.endsWith(source, ".hx") || StringTools.endsWith(source, ".shgraph")) ) {
			var name = StringTools.endsWith(source, ".hx") ? source.substr(0, source.length - 3).split("/").join(".") : source;
			var l = layout(name);
			if( l != null )
				for( c in l ) {
					var v : Dynamic = Reflect.field(props, c.name);
					if( Std.isOfType(v, Bool) )
						add(prefabHits, name + "." + c.name + "=" + (v ? 1 : 0), file);
					else if( Std.isOfType(v, Float) )
						add(prefabHits, name + "." + c.name + "=" + Std.int(v), file);
				}
		}
		if( o.type == "light" && o.kind == "Directional" )
			lights.push({ o : o, path : path });
		if( o.type == "reference" && o.enabled != false && StringTools.endsWith(source ?? "", ".rp") )
			add(rpUsers, source, file.indexOf(".dat/") >= 0 ? file.substr(0, file.indexOf(".dat/")) + ".prefab" : file);
		if( o.type == "ShaderTarget" && o.enabled != false ) {
			var shaders = [];
			function collect( o : Dynamic ) {
				var children : Array<Dynamic> = o.children;
				if( children != null )
					for( c in children ) {
						var name = shaderName(c);
						var mat = name != null || c.type == "material" || c.type == "materialSelector";
						if( mat && (c.enabled == false || c.editorOnly == true) )
							continue;
						if( name != null )
							shaders.push(name);
						collect(c);
					}
			}
			collect(o);
			var tag : String = o.tag;
			if( shaders.length > 1 )
				targets.push({ file : file, tag : tag ?? "default", shaders : shaders });
		}
		var children : Array<Dynamic> = o.children;
		if( children != null )
			for( c in children )
				visit(c, file, lights, path + "/" + c.name);
	}

	public static function sunDesc( o : Dynamic ) {
		var shadows : Dynamic = o.shadows;
		var mode : String = shadows?.mode ?? "None";
		var parts = ['shadows $mode'];
		if( mode != "None" )
			parts.push(shadows?.samplingMode?.kind ?? "no sampling");
		parts.push(o.cascade == true ? "cascades" : "no cascades");
		if( o.cascade == true && mode != "None" && (o.transitionFraction ?? 0.15) <= 0 )
			parts.push("no blend between cascades");
		return parts.join(", ");
	}

	function addLight( o : Dynamic, file : String ) {
		var shadows : Dynamic = o.shadows;
		var mode : String = shadows?.mode;
		var on = mode != null && mode != "None";
		var kind : String = shadows?.samplingMode?.kind;
		var cascade = o.cascade == true;
		var transition : Null<Float> = o.transitionFraction;
		var values = [
			"enable" => (on ? 1 : 0),
			"SAMPLING_MODE" => (!on ? 0 : kind == "PCF" ? 2 : kind == "ESM" ? 1 : 0),
			"BLEND" => (on && cascade && (transition ?? 0.15) > 0 ? 1 : 0),
		];
		var name = cascade ? "h3d.shader.CascadeShadow" : "h3d.shader.DirShadow";
		var l = layout(name);
		if( l != null ) {
			var bits = 0;
			for( c in l )
				bits |= (values.get(c.name) ?? 0) << c.pos;
			add(lightHits, name + "@" + bits, file);
		}
	}

	function scanCode() {
		var names = new Map<String, Bool>();
		for( l in layouts )
			if( l != null )
				for( c in l )
					names.set(c.name, true);
		var ide = hide.Ide.inst;
		var roots = [ide.projectDir + "/src"];
		for( r in (ide.currentConfig.get("shaderReport.codeRoots") : Array<String>) ?? [] )
			roots.push(haxe.io.Path.isAbsolute(r) ? r : ide.projectDir + "/" + r);
		for( lib in ["heaps", "hide", "shiro"] )
			try {
				var dir = StringTools.trim(Std.string(js.node.ChildProcess.execSync('haxelib libpath $lib', { cwd : ide.projectDir, encoding : "utf8", stdio : ["ignore", "pipe", "ignore"] })));
				if( dir != "" && sys.FileSystem.exists(dir) )
					roots.push(dir);
			} catch( e : Dynamic ) {
			}
		for( e in extensions )
			e.codeRoots(this, roots);
		var re = ~/\.([A-Za-z_][A-Za-z0-9_]*)\s*=[^=]/;
		var visited = new Map<String, Bool>();
		function walk( dir : String ) {
			if( visited.exists(dir) || !sys.FileSystem.exists(dir) )
				return;
			visited.set(dir, true);
			for( f in sys.FileSystem.readDirectory(dir) ) {
				var p = dir + "/" + f;
				if( sys.FileSystem.isDirectory(p) ) {
					if( f.charAt(0) != "." && f != "bin" && f != "node_modules" )
						walk(p);
					continue;
				}
				if( !StringTools.endsWith(f, ".hx") )
					continue;
				var content = sys.io.File.getContent(p);
				var found = false;
				for( i => line in content.split("\n") ) {
					var t = StringTools.trim(line);
					if( StringTools.startsWith(t, "//") )
						continue;
					var pos = 0;
					while( re.matchSub(line, pos) ) {
						var name = re.matched(1);
						if( names.exists(name) ) {
							var l = codeHits.get(name);
							if( l == null ) {
								l = [];
								codeHits.set(name, l);
							}
							l.push({ file : p, line : i + 1, text : t });
							found = true;
						}
						var mp = re.matchedPos();
						pos = mp.pos + mp.len - 1;
					}
				}
				if( found )
					codeFiles.set(p, content);
			}
		}
		for( r in roots )
			walk(haxe.io.Path.removeTrailingSlashes(r.split("\\").join("/").split("//").join("/")));
	}

	public function codeFor( shader : String, const : String ) {
		var i = shader.lastIndexOf(".");
		var short = StringTools.endsWith(shader, ".shgraph") ? null : shader.substr(i + 1);
		if( short == null )
			return [];
		var hits = codeHits.get(const) ?? [];
		var files = [];
		for( h in hits )
			if( !files.contains(h.file) )
				files.push(h.file);
		var generic = files.length > 20;
		var lower = short.toLowerCase();
		return [for( h in hits ) if( codeFiles.get(h.file).indexOf(short) >= 0 && (!generic || h.text.toLowerCase().indexOf("shader") >= 0 || h.text.toLowerCase().indexOf(lower) >= 0) ) h];
	}

	function sources( shader : String, c : ReportConst, values : Array<Int> ) {
		var parts = [];
		for( h in codeFor(shader, c.name).slice(0, 6) )
			parts.push(code(h.file, h.line, h.text));
		for( v in values ) {
			var files = prefabHits.get(shader + "." + c.name + "=" + v);
			if( files != null )
				parts.push('${files.length} prefabs set ${esc(c.name)}=$v <small>(${Report.files(files, 4)})</small>');
		}
		return parts;
	}

	static function where( parts : Array<String> ) {
		return parts.length == 0 ? "" : details("where", parts.join("<br>"));
	}

	public static function generated( name : String ) {
		return StringTools.startsWith(name, "shaderLinker_") || StringTools.startsWith(name, "batchShader_");
	}

	// hide's loader caches resources on the current h3d.Engine, which is null while no scene view is open
	function shaderGraph( name : String ) : hxsl.Shader {
		if( graphs.exists(name) )
			return graphs.get(name);
		var s = try {
			var res = new hrt.prefab.Resource(hxd.res.Loader.currentInstance.fs.get(name));
			Std.downcast(res.loadBypassCache(), hrt.shgraph.ShaderGraph)?.makeShaderInstance();
		} catch( e : Dynamic ) null;
		graphs.set(name, s);
		return s;
	}

	public function layout( name : String ) {
		if( layouts.exists(name) )
			return layouts.get(name);
		var res : Array<ReportConst> = null;
		try {
			var s : hxsl.Shader = null;
			if( StringTools.endsWith(name, ".shgraph") ) {
				s = shaderGraph(name);
			} else {
				var cl = Type.resolveClass(name);
				if( cl != null ) {
					s = Type.createEmptyInstance(cl);
					@:privateAccess s.initialize();
				}
			}
			if( s != null ) {
				res = [];
				var c = @:privateAccess s.shader.consts;
				while( c != null ) {
					res.push({ name : c.v.name, pos : c.pos, bits : c.bits });
					c = c.next;
				}
			}
		} catch( e : Dynamic ) {
		}
		layouts.set(name, res);
		return res;
	}

	public function constValue( c : ReportConst, bits : Int ) {
		return (bits >> c.pos) & ((1 << c.bits) - 1);
	}

	public function constNames( shader : String, mask : Int ) {
		var l = layout(shader);
		var names = l == null ? [] : [for( c in l ) if( constValue(c, mask) != 0 ) c.name];
		return names.length == 0 ? "bits 0x" + StringTools.hex(mask) : names.join(" + ");
	}

	public function decode( shader : String, bits : Int, mask : Int ) {
		var l = layout(shader);
		if( l == null || l.length == 0 )
			return "@" + bits;
		var parts = [for( c in l ) if( mask == -1 || constValue(c, mask) != 0 ) c.name + "=" + constValue(c, bits)];
		return parts.length == 0 ? "@" + bits : parts.join(" ");
	}

	public function decodeToken( t : String ) {
		var i = t.lastIndexOf("@");
		var name = t.substr(0, i), bits = Std.parseInt(t.substr(i + 1));
		var l = layout(name);
		return l == null || l.length == 0 ? t : t + " (" + decode(name, bits, -1) + ")";
	}

	function slotKey( e : ReportEntry, skip : Int, keep : Bool ) {
		var b = new StringBuf();
		b.add(e.mode);
		b.add("#");
		b.add(e.tokens.length);
		for( k => t in e.tokens ) {
			b.add(" ");
			if( k != skip )
				b.add(t);
			else if( keep )
				b.add("*");
		}
		return b.toString();
	}

	function axes() {
		var groups = new Map<String, Array<Int>>();
		var slots = new Map<String, Int>();
		for( ei => e in entries )
			for( i in 1...e.shaders.length ) {
				if( generated(e.shaders[i].name) )
					continue;
				var key = slotKey(e, i, true);
				var g = groups.get(key);
				if( g == null ) {
					g = [];
					groups.set(key, g);
					slots.set(key, i);
				}
				g.push(ei);
			}
		var result = new Map<String, ReportAxis>();
		for( key => g in groups ) {
			if( g.length < 2 )
				continue;
			var i = slots.get(key);
			var names = [];
			for( ei in g )
				if( !names.contains(entries[ei].shaders[i].name) )
					names.push(entries[ei].shaders[i].name);
			var mask = 0;
			var label;
			if( names.length == 1 ) {
				var b0 = entries[g[0]].shaders[i].bits;
				for( ei in g )
					mask |= entries[ei].shaders[i].bits ^ b0;
				label = names[0] + " : " + constNames(names[0], mask);
			} else {
				if( [for( s in entries[g[0]].shaders ) if( !generated(s.name) ) s].length < 3 )
					continue;
				names.sort(Reflect.compare);
				label = names.join(" / ");
			}
			var a = result.get(label);
			if( a == null ) {
				a = { label : label, slot : names.length > 1, shader : names.length == 1 ? names[0] : null, mask : 0, groups : 0, lists : 0, extra : 0, values : new Map(), examples : [] };
				result.set(label, a);
			}
			a.mask |= mask;
			a.groups++;
			a.lists += g.length;
			a.extra += g.length - 1;
			for( ei in g ) {
				var t = entries[ei].tokens[i];
				a.values.set(t, (a.values.get(t) ?? 0) + 1);
			}
			if( a.examples.length < EXAMPLES )
				a.examples.push({ pos : i, entries : [for( ei in g ) entries[ei]] });
		}
		var list = [for( a in result ) a];
		list.sort((x, y) -> y.extra - x.extra);
		return list;
	}

	function coexist( names : Array<String> ) {
		if( postings == null ) {
			postings = new Map();
			for( ei => e in entries )
				for( s in e.shaders ) {
					var p = postings.get(s.name);
					if( p == null ) {
						p = [];
						postings.set(s.name, p);
					}
					if( p.length == 0 || p[p.length - 1] != ei )
						p.push(ei);
				}
		}
		for( i in 0...names.length )
			for( j in i + 1...names.length ) {
				var a = postings.get(names[i]), b = postings.get(names[j]);
				var ia = 0, ib = 0;
				while( ia < a.length && ib < b.length ) {
					if( a[ia] == b[ib] )
						return true;
					if( a[ia] < b[ib] ) ia++ else ib++;
				}
			}
		return false;
	}

	function optionals() {
		var all = new Map<String, ReportEntry>();
		for( e in entries )
			all.set(slotKey(e, -1, false), e);
		var result = new Map<String, { name : String, count : Int, examples : Array<{ pos : Int, entry : ReportEntry, without : ReportEntry }> }>();
		for( e in entries ) {
			var done = [];
			for( i in 1...e.shaders.length ) {
				var name = e.shaders[i].name;
				if( generated(name) || done.contains(name) )
					continue;
				var without = new StringBuf();
				without.add(e.mode);
				without.add("#");
				without.add(e.tokens.length - 1);
				for( k => t in e.tokens )
					if( k != i ) {
						without.add(" ");
						without.add(t);
					}
				var w = all.get(without.toString());
				if( w == null )
					continue;
				done.push(name);
				var o = result.get(name);
				if( o == null ) {
					o = { name : name, count : 0, examples : [] };
					result.set(name, o);
				}
				o.count++;
				if( o.examples.length < EXAMPLES )
					o.examples.push({ pos : i, entry : e, without : w });
			}
		}
		var list = [for( o in result ) o];
		list.sort((x, y) -> y.count - x.count);
		return list;
	}

	function orders() {
		var groups = new Map<String, Array<ReportEntry>>();
		for( e in entries ) {
			var t = e.tokens.copy();
			t.sort(Reflect.compare);
			var key = e.mode + " " + t.join(" ");
			var g = groups.get(key);
			if( g == null ) {
				g = [];
				groups.set(key, g);
			}
			g.push(e);
		}
		var result = new Map<String, { label : String, groups : Int, extra : Int, same : Int, examples : Array<Array<ReportEntry>> }>();
		for( g in groups ) {
			if( g.length < 2 )
				continue;
			var p = program(g[0]);
			var same = p != null && !g.exists(e -> program(e) != p);
			var moving = [];
			for( e in g )
				for( k => t in e.tokens )
					if( t != g[0].tokens[k] ) {
						var n = e.shaders[k].name;
						if( !moving.contains(n) )
							moving.push(n);
					}
			moving.sort(Reflect.compare);
			var label = moving.length == 0 ? "(identical lists)" : moving.join(", ");
			var o = result.get(label);
			if( o == null ) {
				o = { label : label, groups : 0, extra : 0, same : 0, examples : [] };
				result.set(label, o);
			}
			o.groups++;
			o.extra += g.length - 1;
			if( same )
				o.same++;
			if( o.examples.length < EXAMPLES )
				o.examples.push(g);
		}
		var list = [for( o in result ) o];
		list.sort((x, y) -> y.extra - x.extra);
		return list;
	}

	function samePrograms() {
		var groups = new Map<String, Array<ReportEntry>>();
		for( e in entries ) {
			var p = program(e);
			if( p == null )
				continue;
			var g = groups.get(e.mode + p);
			if( g == null ) {
				g = [];
				groups.set(e.mode + p, g);
			}
			g.push(e);
		}
		var result = new Map<String, { label : String, groups : Int, extra : Int, examples : Array<Array<ReportEntry>> }>();
		for( g in groups ) {
			if( g.length < 2 )
				continue;
			var differ = [];
			for( e in g )
				for( k => s in e.shaders )
					if( !generated(s.name) && !differ.contains(s.name) && g.exists(o -> !o.tokens.contains(e.tokens[k])) )
						differ.push(s.name);
			differ.sort(Reflect.compare);
			var label = differ.length == 0 ? "(same shaders in another order)" : differ.join(", ");
			var o = result.get(label);
			if( o == null ) {
				o = { label : label, groups : 0, extra : 0, examples : [] };
				result.set(label, o);
			}
			o.groups++;
			o.extra += g.length - 1;
			if( o.examples.length < EXAMPLES )
				o.examples.push(g);
		}
		var list = [for( o in result ) o];
		list.sort((x, y) -> y.extra - x.extra);
		return list;
	}

	function shadowPrograms() {
		var lists = 0;
		var progs = new Map<String, Bool>();
		for( e in entries )
			if( e.tokens.exists(t -> StringTools.startsWith(t, "h3d.shader.LinearShadowDepth@")) ) {
				lists++;
				var p = program(e);
				if( p != null )
					progs.set(p, true);
			}
		return { lists : lists, programs : Lambda.count(progs) };
	}

	function orderTargets( names : Array<String> ) {
		var tags = new Map<String, Array<{ order : String, pairs : Array<String>, files : Array<String> }>>();
		for( t in targets ) {
			var seq = [for( s in t.shaders ) if( names.contains(s) ) s];
			if( [for( n in names ) if( seq.contains(n) ) n].length < 2 )
				continue;
			var order = seq.join(", ");
			var l = tags.get(t.tag);
			if( l == null ) {
				l = [];
				tags.set(t.tag, l);
			}
			var g = Lambda.find(l, g -> g.order == order);
			if( g == null ) {
				var pairs = [];
				for( i in 0...seq.length )
					for( j in i + 1...seq.length )
						if( seq[i] != seq[j] && !pairs.contains(seq[i] + "|" + seq[j]) )
							pairs.push(seq[i] + "|" + seq[j]);
				g = { order : order, pairs : pairs, files : [] };
				l.push(g);
			}
			if( !g.files.contains(t.file) )
				g.files.push(t.file);
		}
		var parts = [];
		for( tag => l in tags ) {
			l.sort((x, y) -> y.files.length - x.files.length);
			for( i => g in l ) {
				var swap = i > 0 && g.pairs.exists(p -> l[0].pairs.contains(p.split("|")[1] + "|" + p.split("|")[0]));
				var text = '${esc(tag)}: ${esc(g.order)} <small>(${g.files.length} FX)</small>';
				parts.push((swap ? '<span class="warn">$text</span>' : text) + details("FX", [for( f in g.files ) file(f)].join("<br>")));
			}
		}
		return parts.length == 0 ? '<small>no FX shader target has several of these shaders</small>' : parts.join("");
	}

	function shaders() {
		var result = new Map<String, { name : String, lists : Int, variants : Map<Int, Int> }>();
		for( e in entries ) {
			var seen = new Map<String, Bool>();
			for( k => s in e.shaders ) {
				if( generated(s.name) )
					continue;
				var o = result.get(s.name);
				if( o == null ) {
					o = { name : s.name, lists : 0, variants : new Map() };
					result.set(s.name, o);
				}
				if( !seen.exists(s.name) )
					o.lists++;
				if( !seen.exists(e.tokens[k]) )
					o.variants.set(s.bits, (o.variants.get(s.bits) ?? 0) + 1);
				seen.set(s.name, true);
				seen.set(e.tokens[k], true);
			}
		}
		var list = [for( o in result ) o];
		list.sort((x, y) -> y.lists - x.lists);
		return list;
	}

	public static function cost( lists : Int, long = false ) {
		var kb = lists * ENTRY_KB, s = lists * ENTRY_MS / 1000;
		var ram = kb < 1024 ? kb + " KB" : kb < 1024 * 1024 ? Std.int(kb / 1024) + " MB" : Math.round(kb / 1024 / 1024 * 10) / 10 + " GB";
		var time = s < 1 ? Math.round(s * 1000) + " ms" : Math.round(s * 10) / 10 + " s";
		return long ? ram + " of RAM and " + time + " of loading" : ram + ", " + time;
	}

	public function listHtml( e : ReportEntry, mark : Int ) {
		return e.mode + ": " + [for( k => t in e.tokens ) if( !StringTools.startsWith(t, "shaderLinker_") ) shader(e.shaders[k].name, t, k == mark ? "diff" : null, decodeToken(t))].join(" ");
	}

	function axisVersions( a : ReportAxis ) {
		var list : Array<{ label : String, n : Int, suns : Array<String> }> = [];
		for( t => n in a.values ) {
			var label = a.shader == null ? decodeToken(t) : decode(a.shader, Std.parseInt(t.substr(t.lastIndexOf("@") + 1)), a.mask);
			var v = Lambda.find(list, v -> v.label == label);
			if( v == null ) {
				v = { label : label, n : 0, suns : [] };
				list.push(v);
			}
			v.n += n;
			for( f in lightHits.get(t) ?? [] )
				if( !v.suns.contains(f) )
					v.suns.push(f);
		}
		list.sort((x, y) -> y.n - x.n);
		return list;
	}

	function axisText( a : ReportAxis ) {
		var n = axisVersions(a).length;
		return a.slot
			? '<b>${esc(a.label)}</b> take each other\'s place ($n versions): ${a.groups} lists exist in several versions'
			: '<b>${esc(a.shader)}</b> comes in $n versions (${esc(constNames(a.shader, a.mask))}): ${a.groups} lists exist in several versions';
	}

	function axisWhere( a : ReportAxis ) {
		if( a.shader == null )
			return "";
		var parts = [];
		for( c in layout(a.shader) ?? [] )
			if( constValue(c, a.mask) != 0 ) {
				var values = [];
				for( t in a.values.keys() ) {
					var v = constValue(c, Std.parseInt(t.substr(t.lastIndexOf("@") + 1)));
					if( !values.contains(v) )
						values.push(v);
				}
				parts = parts.concat(sources(a.shader, c, values));
			}
		return where(parts);
	}

	function axisWarn( a : ReportAxis ) {
		var labels = [];
		function add( l : Array<String> )
			for( x in l ?? [] )
				if( !labels.contains(x) )
					labels.push(x);
		if( a.shader != null ) {
			for( c in layout(a.shader) ?? [] )
				if( constValue(c, a.mask) != 0 )
					add(optionLabels(a.shader, c.name));
		} else
			for( n in a.label.split(" / ") )
				add(optionConsts.get(n));
		return labels.length == 0 ? "" : '<div class="warn">changed by an option: ${esc(labels.join(", "))}</div>';
	}

	function shaderLabel( name : String ) {
		return shader(name) + (StringTools.endsWith(name, ".shgraph") ? " " + file(name, "open") : "");
	}

	function makeReport() : ReportData {
		var extSections = [for( e in extensions ) for( s in e.sections(this) ) s];
		var summary = [];
		for( e in extensions )
			summary = summary.concat(e.summary(this));

		var counts = new Map<String, Int>();
		for( e in entries )
			counts.set(e.mode, (counts.get(e.mode) ?? 0) + 1);
		var all = axes();
		var materials = [for( a in all ) if( a.slot && coexist(a.label.split(" / ")) ) a];
		var mainAxes = [for( a in all ) if( !materials.contains(a) ) a];
		var opts = optionals();
		var ords = orders();
		var sames = samePrograms();

		var box = new StringBuf();
		box.add('<p><b>${entries.length} shader lists</b> (${[for( m => n in counts ) m + " " + n].join(", ")}): players pay about ${cost(entries.length, true)} for this cache, in the background when the game starts.</p>');
		if( codeOptions.length > 0 && !extSections.exists(s -> s.id == "options") )
			box.add('<p class="warn">Options: ${codeOptions.length} 3D shader consts are set from options in code. The cache only holds the values of the options the warm-up ran with:
players with other values compile these shaders while playing (stutters). ${goto("options", "See the details")}.</p>');
		if( programs == null )
			box.add('<p class="note">The lists could not be linked, the sections comparing programs are empty.</p>');
		else {
			var distinct = new Map<String, Bool>();
			for( e in entries ) {
				var p = program(e);
				if( p != null )
					distinct.set(e.mode + p, true);
			}
			var extra = 0;
			for( s in sames )
				extra += s.extra;
			var shadow = shadowPrograms();
			box.add('<p>Linked, the ${entries.length} lists make <b>${Lambda.count(distinct)} different programs</b>: $extra lists compile to the same program as another list
(${goto("same", "see which")})${linkErrors == 0 ? "" : ', $linkErrors lists failed to link'}.
The ${shadow.lists} shadow lists (with <code>LinearShadowDepth</code>) make ${shadow.programs} programs.</p>');
		}
		summary.unshift(Html(box.toString()));

		var top = [];
		for( i => a in mainAxes )
			top.push({ text : axisText(a), extra : a.extra, id : "a" + i });
		for( i => o in opts )
			top.push({ text : '<b>${esc(o.name)}</b> is added to only some objects: ${o.count} lists are another list of the cache plus this shader', extra : o.count, id : "o" + i });
		for( i => o in ords )
			top.push({ text : '<b>${esc(o.label)}</b> are added in different orders: ${o.groups} lists exist in several orders', extra : o.extra, id : "r" + i });
		top.sort((x, y) -> y.extra - x.extra);
		summary.push(Html('<p>What multiplies the lists the most (a list can be counted in several rows: don\'t add them up):</p>'));
		summary.push(Table({
			columns : [{ name : "Cause", width : 70 }, { name : "Extra lists", num : true, width : 12 }, { name : "Cost", width : 18 }],
			rows : [for( t in top.slice(0, 8) ) { cells : [goto(t.id, t.text), "" + t.extra, cost(t.extra)], values : [null, t.extra, t.extra] }],
		}));

		var sections : Array<ReportSection> = [];
		sections.push({ id : "help", title : "How to read this report", order : 0, open : false, blocks : [Html('
<p>A list missing from the ref cache is compiled while playing (a stutter), and each list in it costs players about $ENTRY_KB KB of RAM and $ENTRY_MS ms of loading (measured on a dev PC: the order of magnitude): the fewer different lists, the better.</p>
<p><b>Const</b>: a shader setting fixed when the program is compiled, like <code>fourBonesByVertex</code> in <code>h3d.shader.Skin</code>, on for models skinned with 4 bones per vertex.
Each value makes another program: a const with 2 values doubles the lists of its shader. A shader with a given set of const values is one <b>version</b> of it.
In the lists, <code>h3d.shader.Skin@2432</code> is the version of Skin whose const values are packed in the number 2432 (${esc(decode("h3d.shader.Skin", 2432, -1))}): hover a shader of a list to decode it, click it to see its row in ${goto("shaders", "All shaders")}.</p>
<p><b>Default, Batch, Compute</b>: lists of regular meshes, of meshes drawn many at once (particles, props), and of GPU computations.</p>
<p><b>Cost</b>: the RAM and loading time players pay for the lists of a row, at $ENTRY_KB KB and $ENTRY_MS ms per list.</p>
<p>Each section below looks for one thing that multiplies the lists, and says how to reduce it. A list can be counted in several rows: don\'t add rows up.
Click <i>examples</i> to see real lists of the cache, with the shader that differs in red, and <i>where</i> to see the code and prefabs that set a const.
Click a column to sort it, and use the filter to keep only the rows that contain a text.</p>')] });

		if( codeOptions.length > 0 )
			sections.push({ id : "options", title : "Shader consts set from options", order : 10, count : codeOptions.length, open : true, blocks : [
				Html('<p>3D shader consts that the code sets from options. The cache is made with the options of the PC that ran the shader warm-up:
players with another value compile the missing lists while playing. Fine where the options are fixed (consoles), a stutter elsewhere.</p>
<p>The consts involved are marked <span class="warn">changed by an option</span> in the other sections.</p>'),
				Table({
					columns : [{ name : "Const", width : 35 }, { name : "Code", width : 65 }],
					rows : [for( c in codeOptions ) { cells : ['<span class="warn">${esc(c.key)}</span>', code(c.file, c.line, c.text)] }],
				}),
			] });

		function axesTable( list : Array<ReportAxis>, id : String, slotKind : String ) : ReportBlock {
			var rows : Array<ReportRow> = [];
			for( i => a in list ) {
				var versions = axisVersions(a);
				var shown = [for( v in versions.slice(0, 12) ) esc(v.label) + " <small>(" + v.n + ")" + (v.suns.length == 0 ? "" : " made by the sun of: " + files(v.suns, 4)) + "</small>"].join("<br>") + (versions.length > 12 ? "<br>..." : "");
				var label = a.shader != null ? shader(a.shader) + " : " + esc(constNames(a.shader, a.mask)) : [for( n in a.label.split(" / ") ) shader(n)].join(" / ");
				var examples = details("examples", [for( ex in a.examples ) "<div>" + [for( e in ex.entries ) listHtml(e, ex.pos)].join("<br>") + "</div>"].join(""));
				rows.push({ id : id + i, cells : [label + axisWarn(a) + axisWhere(a) + examples, a.slot ? slotKind : "settings", shown, "" + a.groups, "" + a.extra, cost(a.extra)], values : [a.label, null, versions.length, a.groups, a.extra, a.extra] });
			}
			return Table({
				columns : [{ name : "Shader that differs", width : 30 }, { name : "Kind", width : 6 }, { name : "Versions found (lists)", width : 36 }, { name : "Lists in several versions", num : true, width : 9 }, { name : "Extra lists", num : true, width : 7 }, { name : "Cost", width : 12 }],
				rows : rows,
			});
		}
		var ex = mainAxes[0];
		sections.push({ id : "axes", title : "One shader in several versions", order : 20, count : mainAxes.length, open : true, blocks : [Html('<p>Lists that are identical except for one shader, which comes in several versions:</p>
<ul><li><i>settings</i>: the same shader with other const values, for example <code>h3d.shader.Skin</code> with <code>calcPrevPos</code> on and off;</li>
<li><i>swap</i>: other shaders at the same place, never found in the same list: they do the same job in different ways, for example the sun shadow shader of each lighting.</li></ul>
<ul><li><i>Versions found</i>: each version, with how many lists of the cache use it (and for sun shadow shaders, the prefabs whose sun gives it).</li>
<li><i>Lists in several versions</i>: how many lists exist in several versions because of this shader (a list and its versions count as one).</li>
<li><i>Extra lists</i>: the versions beyond the first one, that is the lists the cache would lose if this shader had only one version.'
			+ (ex == null ? "" : ' In the first row, ${ex.groups} lists exist in several versions of ${esc(ex.shader ?? ex.label)}: ${ex.lists} lists in the cache, ${ex.extra} more than one per list.') + '</li></ul>
<p>To reduce: keep one value when the versions look the same, or make the const a regular shader parameter (<code>@param</code> instead of <code>@const</code>); for a swap, make the content use the same shader (for sun shadows, the same shadow settings on their directional lights).</p>'),
			axesTable(mainAxes, "a", "swap")] });

		sections.push({ id : "optional", title : "Shaders added to only some objects", order : 30, count : opts.length, open : false, blocks : [Html('<p>Lists that also exist without one of their shaders, everything else being identical: some objects, or some moments, get this shader and others don\'t.
Typically an FX adds it to a unit while it plays (hit flash, dissolve, color change), or the code adds it in some state: every material the FX can play on then exists once without it and once with it, and once more for each other combination of FX shaders.</p>
<ul><li><i>Lists also found without it</i>: lists of the cache that are another list of the cache plus this shader.</li>
<li><i>Cost</i>: what these lists cost.</li></ul>
<p>To reduce: FX that play on units should reuse the same few shaders with the same settings, since each new shader or setting multiplies the lists of every material it can play on.</p>'),
			Table({
				columns : [{ name : "Shader", width : 62 }, { name : "Lists also found without it", num : true, width : 18 }, { name : "Cost", width : 20 }],
				rows : [for( i => o in opts ) {
					id : "o" + i,
					cells : [shaderLabel(o.name) + details("examples", [for( ex in o.examples ) "<div>with: " + listHtml(ex.entry, ex.pos) + "<br>without: " + listHtml(ex.without, -1) + "</div>"].join("")), "" + o.count, cost(o.count)],
					values : [o.name, o.count, o.count],
				}],
			})] });

		var orderRows : Array<ReportRow> = [];
		for( i => o in ords ) {
			var examples = details("examples", [for( g in o.examples ) "<div>" + [for( e in g ) listHtml(e, -1)].join("<br>") + "</div>"].join(""));
			var same = programs == null ? "" : '<span class="${o.same == o.groups ? "ok" : o.same == 0 ? "warn" : ""}">${o.same}/${o.groups}</span>';
			var diff = "";
			if( programs != null )
				for( g in o.examples ) {
					var other = Lambda.find(g, e -> program(e) != program(g[0]));
					if( other != null ) {
						diff = codeDiff(g[0], other);
						break;
					}
				}
			var label = [for( n in o.label.split(", ") ) n.charAt(0) == "(" ? esc(n) : shader(n)].join(", ");
			orderRows.push({ id : "r" + i, cells : [label + examples + diff, orderTargets(o.label.split(", ")), "" + o.groups, same, "" + o.extra, cost(o.extra)], values : [o.label, null, o.groups, o.groups == 0 ? 0 : o.same / o.groups, o.extra, o.extra] });
		}
		sections.push({ id : "order", title : "Same shaders in a different order", order : 40, count : ords.length, open : false, blocks : [Html('<p>Lists that contain exactly the same shaders, in another order: each order is compiled separately.
Shaders are sorted by priority, and shaders with the same priority by the time they were added: two FX that start in a different order, for example, make two lists.</p>
<ul><li><i>Shaders that move</i>: the shaders found at different places.</li>
<li><i>Lists in several orders</i>: how many lists exist in several orders (a list and its other orders count as one).</li>
<li><i>Extra lists</i>: the orders beyond the first one, that is the lists the cache would lose with a fixed order.</li>
<li><i>FX shader targets</i>: the FX ShaderTargets that hold several of these shaders, by tag, with the order of these shaders in the FX (top to bottom).
All the shaders of a ShaderTarget get the priority of its tag, so they keep the order of the FX: when the ShaderTargets of a tag put them in several orders, each order makes its own lists on the units. In red, the ShaderTargets that put two of these shaders the other way round from the most common order of their tag.</li></ul>
<p>To reduce: put these shaders in the same order in all the ShaderTargets of a tag (the ones in red), or give them different priorities in code. When no ShaderTarget is in red, the order comes from FX that start at different times (several ShaderTargets applied at once on different objects of a unit, or shaders added outside ShaderTargets).</p>
<p><i>Same program</i>: the groups whose orders all link to the same program. There the order changes nothing and a fixed priority is safe.
Elsewhere the program differs: either the order changes the result (two shaders blending over the same color), or only the order of independent instructions changes. Check the shaders before fixing their order.</p>'),
			Table({
				columns : [{ name : "Shaders that move", width : 28 }, { name : "FX shader targets", width : 28 }, { name : "Lists in several orders", num : true, width : 9 }, { name : "Same program", num : true, width : 9 }, { name : "Extra lists", num : true, width : 9 }, { name : "Cost", width : 17 }],
				rows : orderRows,
			})] });

		sections.push({ id : "same", title : "Lists that compile to the same program", order : 50, count : sames.length, open : false, blocks : [Html('<p>Lists that differ, but link to exactly the same program: the shaders that differ are removed by the linker
because nothing uses what they write in this pass (typically material shaders in the shadow or outline passes), or only their order differs.
Each list is still linked when the game starts, but the driver gets the same code.</p>
<ul><li><i>Shaders that make no difference</i>: the shaders found in some lists of a group and not in others, or in other versions.</li>
<li><i>Groups</i>: the programs made by several lists.</li>
<li><i>Extra lists</i>: the lists beyond the first one of each group, that is the lists the cache would lose if these shaders were left out of the pass.</li></ul>
<p>To reduce: leave these shaders out of the pass where they are removed anyway, or give them a fixed order.</p>'),
			Table({
				columns : [{ name : "Shaders that make no difference", width : 62 }, { name : "Groups", num : true, width : 9 }, { name : "Extra lists", num : true, width : 9 }, { name : "Cost", width : 20 }],
				rows : [for( i => o in sames ) {
					id : "s" + i,
					cells : [[for( n in o.label.split(", ") ) n.charAt(0) == "(" ? esc(n) : shader(n)].join(", ") + details("examples", [for( g in o.examples ) "<div>" + [for( e in g.slice(0, 6) ) listHtml(e, -1)].join("<br>") + (g.length > 6 ? "<br>..." : "") + "</div>"].join("")), "" + o.groups, "" + o.extra, cost(o.extra)],
					values : [o.label, o.groups, o.extra, o.extra],
				}],
			})] });

		sections.push({ id : "materials", title : "Different shaders at the same place", order : 60, count : Std.int(Math.min(materials.length, 30)), open : false, blocks : [Html('<p>Lists that are identical except for one shader, replaced by another one.
Unlike a swap, these shaders are also found together in other lists, so they are not two versions of the same thing: usually two different effects on the same object (an FX adds a color, another one a rim light).
This comes from the content, there is usually nothing to fix. The 30 biggest are listed, with the columns of <i>One shader in several versions</i>.</p>'),
			axesTable(materials.slice(0, 30), "m", "other shader")] });

		var shaderRows : Array<ReportRow> = [];
		for( s in shaders() ) {
			var l = layout(s.name);
			var consts = [];
			if( l != null )
				for( c in l ) {
					var values = new Map<Int, Int>();
					for( bits => n in s.variants ) {
						var v = constValue(c, bits);
						values.set(v, (values.get(v) ?? 0) + n);
					}
					var parts = [for( v => n in values ) v + ": " + n];
					parts.sort(Reflect.compare);
					var opts = optionLabels(s.name, c.name);
					consts.push(esc(c.name) + " <small>{" + parts.join(", ") + "}</small>" + (opts == null ? "" : ' <span class="warn">changed by an option: ${esc(opts.join(", "))}</span>') + where(sources(s.name, c, [for( v in values.keys() ) v])));
				}
			var variants = [for( bits => n in s.variants ) { bits : bits, n : n }];
			variants.sort((x, y) -> y.n - x.n);
			function suns( bits : Int ) {
				var list = lightHits.get(s.name + "@" + bits);
				return list == null ? "" : ' <small>made by the sun of (${list.length}): ${files(list, 6)}</small>';
			}
			var shown = variants.length == 1 ? "1" + suns(variants[0].bits) : variants.length + details("all", [for( v in variants ) esc("@" + v.bits + (l == null || l.length == 0 ? "" : " " + decode(s.name, v.bits, -1))) + " <small>(" + v.n + ")</small>" + suns(v.bits)].join("<br>"));
			shaderRows.push({ id : "sh-" + s.name, cells : [esc(s.name) + (StringTools.endsWith(s.name, ".shgraph") ? " " + file(s.name, "open") : ""), "" + s.lists, shown, consts.join("<br>")], values : [s.name, s.lists, variants.length, consts.length] });
		}
		sections.push({ id : "shaders", title : "All shaders", order : 70, count : shaderRows.length, open : false, blocks : [Html('<p>Every shader of the cache.</p>
<ul><li><i>Lists</i>: the lists that use it.</li>
<li><i>Versions</i>: how many versions of it the cache has (one per set of const values). Click <i>all</i> to see them, with the lists using each (and for sun shadow shaders, the prefabs whose sun gives it).</li>
<li><i>Consts</i>: each const, with the values found and how many lists use each value (<code>{value: lists}</code>). Click <i>where</i> to see the code and prefabs that set it.</li></ul>'),
			Table({
				columns : [{ name : "Shader", width : 18 }, { name : "Lists", num : true, width : 6 }, { name : "Versions", width : 38 }, { name : "Consts {value: lists}", width : 38 }],
				rows : shaderRows,
			})] });

		for( s in extSections ) {
			sections = sections.filter(x -> x.id != s.id);
			sections.push(s);
		}
		sections.sort((a, b) -> Reflect.compare(a.order ?? 100, b.order ?? 100));
		return {
			title : "Shader cache report",
			subtitle : '${esc(path)} <small>(${DateTools.format(sys.FileSystem.stat(path).mtime, "%Y-%m-%d %H:%M")})</small>',
			summary : summary,
			sections : sections,
		};
	}
}

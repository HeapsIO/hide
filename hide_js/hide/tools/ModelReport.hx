package hide.tools;

import hide.tools.Report.*;
import hide.tools.Report.ReportSection;
import hide.tools.Report.ReportData;
import hide.tools.Report.ReportRow;
import hide.tools.Report.ReportColumn;

typedef ReportModel = { path : String, ?cells : Array<String>, ?values : Array<Dynamic> };
typedef ColliderStats = { tris : Int, meshes : Int, convex : Int, other : Int, ms : Float };

/**
	Game specific parts of the model report, registered by a hide plugin:
	`static var _ = hide.tools.ModelReport.register(new MyModelReportExtension());`
**/
class ModelReportExtension {
	public function new() {
	}
	public function models() : Array<ReportModel> {
		return null;
	}
	public function columns() : Array<ReportColumn> {
		return [];
	}
	public function hasColliders() {
		return false;
	}
	public function collider( path : String ) : ColliderStats {
		return null;
	}
	public function sections( p : ModelReport ) : Array<ReportSection> {
		return [];
	}
}

class ModelReport {

	public static inline var DEFAULT_MIN_TRIS = 1000;

	public static var extensions : Array<ModelReportExtension> = [];

	static var _ = Report.register("models", { title : "Model report", editParams : editParams, generate : generate });

	public static function register( e : ModelReportExtension ) {
		extensions.push(e);
		return true;
	}

	public var minTris(default, null) : Int;
	public var models(default, null) : Array<ReportModel>;
	public var columns(default, null) : Array<ReportColumn> = [];
	public var errors(default, null) : Array<{ path : String, msg : String }> = [];
	var colliders : ModelReportExtension;
	var shapeRows : Array<ReportRow> = [];
	var lodRows : Array<{ model : ReportModel, meshes : Int, tris : Array<Int>, has : Array<Int> }> = [];
	var colModels = 0;
	var totalTris = 0;
	var lodCount = 1;
	var noLods = 0;
	var lodTris = 0;

	public function new( minTris : Int ) {
		this.minTris = minTris > 0 ? minTris : DEFAULT_MIN_TRIS;
	}

	static function editParams( bar : js.html.Element, params : { ?minTris : Int }, onChange : Void -> Void ) {
		var title = "The Physics section lists the models whose collision shapes have at least this many triangles";
		var label = el("label", null, bar);
		label.textContent = "List colliders with at least";
		label.title = title;
		var min : js.html.InputElement = cast el("input", null, bar);
		min.type = "number";
		min.title = title;
		var unit = el("label", null, bar);
		unit.textContent = "triangles";
		unit.title = title;
		min.value = "" + (params.minTris ?? DEFAULT_MIN_TRIS);
		min.onchange = () -> {
			params.minTris = Std.parseInt(min.value);
			onChange();
		};
	}

	public static function generate( params : { ?minTris : Int }, onProgress : String -> Void, onDone : ReportData -> Void, onError : haxe.Exception -> Void ) {
		var p = new ModelReport(params.minTris ?? DEFAULT_MIN_TRIS);
		var pos = 0;
		function step() {
			try {
				var end = haxe.Timer.stamp() + 0.05;
				while( pos < p.models.length && haxe.Timer.stamp() < end )
					p.processModel(p.models[pos++]);
				if( pos < p.models.length ) {
					onProgress('Loading ${pos} / ${p.models.length} models...');
					haxe.Timer.delay(step, 0);
					return;
				}
				onDone(p.makeReport());
			} catch( e : haxe.Exception )
				onError(e);
		}
		try {
			p.collectModels();
			p.colliders = Lambda.find(extensions, e -> e.hasColliders());
		} catch( e : haxe.Exception ) {
			onError(e);
			return;
		}
		step();
	}

	function collectModels() {
		for( e in extensions ) {
			var l = e.models();
			if( l != null ) {
				models = l;
				columns = e.columns();
				return;
			}
		}
		models = [];
		var res = hide.Ide.inst.resourceDir;
		function rec( dir : String ) {
			for( f in sys.FileSystem.readDirectory(res + "/" + dir) ) {
				var path = dir == "" ? f : dir + "/" + f;
				if( sys.FileSystem.isDirectory(res + "/" + path) ) {
					if( f.charCodeAt(0) != ".".code )
						rec(path);
				} else {
					var ext = f.substr(f.lastIndexOf(".") + 1).toLowerCase();
					if( ext == "fbx" || ext == "hmd" )
						models.push({ path : path });
				}
			}
		}
		rec("");
		models.sort((a, b) -> Reflect.compare(a.path, b.path));
	}

	function collectLods( path : String, meshes : Array<Array<Int>> ) {
		var entry = try hxd.res.Loader.currentInstance.fs.get(path) catch( e : Dynamic ) {
			errors.push({ path : path, msg : Std.string(e) });
			null;
		}
		if( entry == null )
			return;
		switch( entry.extension.toLowerCase() ) {
		case "fbx", "hmd":
			var lib = try new hxd.res.Model(entry).toHmd() catch( e : Dynamic ) {
				errors.push({ path : path, msg : Std.string(e) });
				null;
			}
			if( lib == null )
				return;
			for( m in lib.header.models ) {
				if( m.geometry < 0 )
					continue;
				var prim = try @:privateAccess lib.makePrimitive(m) catch( e : Dynamic ) null;
				if( prim != null )
					meshes.push([for( g in @:privateAccess prim.lods ) Std.int(g.indexCount / 3)]);
			}
		case "prefab":
			function rec( p : hrt.prefab.Prefab ) {
				if( p == null || @:privateAccess !p.shouldBeInstanciated() )
					return;
				var model = Std.downcast(p, hrt.prefab.Model);
				if( model != null && model.source != null )
					collectLods(model.source, meshes);
				var ref = Std.downcast(p, hrt.prefab.Reference);
				if( ref != null && ref.source != null )
					collectLods(ref.source, meshes);
				for( c in p.children )
					rec(c);
			}
			rec(try new hrt.prefab.Resource(entry).loadBypassCache() catch( e : Dynamic ) null);
		default:
		}
	}

	function processModel( m : ReportModel ) {
		if( colliders != null ) {
			var stats = try colliders.collider(m.path) catch( e : Dynamic ) {
				errors.push({ path : m.path, msg : Std.string(e) });
				null;
			}
			if( stats != null && stats.tris > 0 ) {
				colModels++;
				totalTris += stats.tris;
				if( stats.tris >= minTris ) {
					var ms = Std.int(stats.ms * 100) / 100;
					shapeRows.push({
						cells : ["" + stats.tris, "" + stats.meshes, "" + stats.convex, "" + stats.other, "" + ms].concat(m.cells ?? []).concat([file(m.path)]),
						values : ([stats.tris, stats.meshes, stats.convex, stats.other, ms] : Array<Dynamic>).concat(m.values ?? []).concat([m.path]),
					});
				}
			}
		}

		var meshes = [];
		collectLods(m.path, meshes);
		var count = 0;
		for( l in meshes )
			if( l.length > count )
				count = l.length;
		var tris = [], has = [];
		for( i in 0...count ) {
			tris.push(0);
			has.push(0);
			for( l in meshes ) {
				tris[i] += l[i < l.length ? i : l.length - 1];
				if( i < l.length )
					has[i]++;
			}
		}
		if( count == 0 || tris[0] == 0 )
			return;
		if( count > lodCount )
			lodCount = count;
		if( count == 1 )
			noLods++;
		lodTris += tris[0];
		lodRows.push({ model : m, meshes : meshes.length, tris : tris, has : has });
	}

	function makeReport() : ReportData {
		shapeRows.sort((a, b) -> (b.values[0] : Int) - (a.values[0] : Int));
		lodRows.sort((a, b) -> b.tris[0] - a.tris[0]);

		var extraCols = columns;
		var sections : Array<ReportSection> = [];
		var summary = '<b>${models.length} models</b>';
		if( colliders != null ) {
			summary += ', $colModels with a collider ($totalTris triangles), <b>${shapeRows.length} with at least $minTris collider triangles</b>';
			sections.push({ id : "physics", title : "Physics", order : 10, count : shapeRows.length, open : true, blocks : [
				Html('<p>Models whose collision shapes hold at least $minTris triangles. Mesh colliders and detailed convex hulls are slow to build and to test against: a few simple hulls or primitives are usually enough.</p>
<ul><li><i>Triangles</i>: triangles of all the mesh shapes and convex hulls of the model.</li>
<li><i>Mesh / Convex / Other</i>: how many mesh shapes, convex hulls and other shapes (boxes, spheres, capsules...) the collider has.</li>
<li><i>Load ms</i>: time to build the shapes from the already loaded model.</li></ul>'),
				Table({
					columns : ([{ name : "Triangles", num : true }, { name : "Mesh", num : true }, { name : "Convex", num : true }, { name : "Other", num : true }, { name : "Load ms", num : true }] : Array<ReportColumn>).concat(extraCols).concat([{ name : "Model" }]),
					rows : shapeRows,
				}),
			] });
		}
		summary += ', ${lodRows.length} with meshes ($lodTris triangles), <b>$noLods without any LOD</b>.';

		var rows : Array<ReportRow> = [];
		for( r in lodRows ) {
			var cells = ["" + r.tris[0]], values : Array<Dynamic> = [r.tris[0]];
			for( i in 1...lodCount ) {
				values.push(i < r.tris.length ? r.tris[i] : -1);
				if( i >= r.tris.length ) {
					cells.push('<span class="x">&#10007;</span>');
					continue;
				}
				var text = '${r.tris[i]} <small>${Math.round(r.tris[i] * 100 / r.tris[0])}%</small>';
				cells.push(r.has[i] < r.meshes ? '<span class="part" title="LOD$i on ${r.has[i]}/${r.meshes} meshes">$text</span>' : text);
			}
			rows.push({ cells : cells.concat(r.model.cells ?? []).concat([file(r.model.path)]), values : values.concat(r.model.values ?? []).concat([r.model.path]) });
		}
		sections.push({ id : "lod", title : "LOD", order : 20, count : rows.length, open : true, blocks : [
			Html('<ul><li><i>Triangles</i>: triangles of all the meshes of the model, at LOD0.</li>
<li><i>LOD n</i>: triangles drawn at this LOD, and their share of LOD0. <span class="x">&#10007;</span>: no mesh of the model has this LOD. <span class="part">Orange</span>: only some meshes have it, the others keep their last LOD.</li></ul>'),
			Table({
				columns : ([{ name : "Triangles", num : true }] : Array<ReportColumn>).concat([for( i in 1...lodCount ) { name : "LOD" + i, num : true }]).concat(extraCols).concat([{ name : "Model" }]),
				rows : rows,
			}),
		] });

		if( errors.length > 0 )
			sections.push({ id : "errors", title : "Models that failed to load", order : 90, count : errors.length, open : false, blocks : [Table({
				columns : [{ name : "Model", width : 40 }, { name : "Error", width : 60 }],
				rows : [for( e in errors ) { cells : [file(e.path), esc(e.msg)] }],
			})] });

		for( e in extensions )
			for( s in e.sections(this) ) {
				sections = sections.filter(x -> x.id != s.id);
				sections.push(s);
			}
		sections.sort((a, b) -> Reflect.compare(a.order ?? 100, b.order ?? 100));
		return {
			title : "Model report",
			subtitle : '${esc(hide.Ide.inst.resourceDir)} <small>(${DateTools.format(Date.now(), "%Y-%m-%d %H:%M")})</small>',
			summary : [Html('<p>$summary</p>')],
			sections : sections,
		};
	}
}

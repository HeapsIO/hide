package hide.tools.migrate;

import hide.tools.migrate.Migrate;

/** The migration tool, see `usage` **/
class Cli {

	static function usage() {
		Sys.println("usage: hl migrate.hl <res dir> [--out <dir> | --in-place] [--report <file>] [--verbose]
Upgrades the FX data of the prefab files of a project (" + Migrate.EXTENSIONS.join(", ") + ") to version " + hrt.prefab.fx.FX.VERSION + ".
With no option, a dry run: lists the files that would change, the changes and the warnings.
  --out <dir>      write the migrated files to <dir>, under their path in the res dir
  --in-place       rewrite the files of the project
  --report <file>  write the full report (markdown) to <file>
  --verbose        list every change of every file");
	}

	static function main() {
		var args = Sys.args();
		var res : String = null, out : String = null, inPlace = false, reportFile : String = null, verbose = false;
		var i = 0;
		while( i < args.length ) {
			var a = args[i++];
			switch( a ) {
			case "--out": out = args[i++];
			case "--in-place": inPlace = true;
			case "--report": reportFile = args[i++];
			case "--verbose": verbose = true;
			case "--help", "-h": usage(); return;
			default:
				if( StringTools.startsWith(a, "-") || res != null ) {
					usage();
					Sys.exit(1);
				}
				res = a;
			}
		}
		if( res == null || (out != null && inPlace) ) {
			usage();
			Sys.exit(1);
		}
		var t0 = haxe.Timer.stamp();
		var result = Migrate.migrateProject(res);
		var changed = [for( f in result.files ) if( f.changed ) f];
		var md = report(res, result, verbose);
		if( reportFile != null )
			sys.io.File.saveContent(reportFile, md);
		Sys.println(md.split("\n## ")[0]);
		if( out != null || inPlace ) {
			var dir = inPlace ? res : out;
			for( f in changed ) {
				var path = dir + "/" + f.path;
				sys.FileSystem.createDirectory(haxe.io.Path.directory(path));
				sys.io.File.saveContent(path, Migrate.toText(f.data));
			}
			Sys.println('${changed.length} files written to $dir');
		} else
			Sys.println("dry run, nothing written (--out <dir> or --in-place to write)");
		var parents = 0, warnings = 0;
		for( f in result.files ) {
			parents += f.report.parents.length;
			warnings += f.report.warnings.length;
		}
		Sys.println('${result.files.length} files read, ${changed.length} changed, $parents objects moved under a parent, $warnings warnings, ${result.errors.length} errors, ${Math.round((haxe.Timer.stamp() - t0) * 10) / 10}s');
		Sys.exit(result.errors.length > 0 ? 1 : 0);
	}

	public static function report( res : String, result : ProjectResult, verbose : Bool ) : String {
		var b = new StringBuf();
		inline function line( s : String ) b.add(s + "\n");
		var changed = [for( f in result.files ) if( f.changed ) f];
		var kinds = new Map<String, Int>();
		for( f in result.files )
			for( c in f.report.changes ) {
				var k = ~/ [^ ]+ ->| of [^ ]+/g.replace(c.kind, "");
				kinds.set(k, (kinds.get(k) ?? 0) + 1);
			}
		line('# FX data version ${hrt.prefab.fx.FX.VERSION} migration of $res\n');
		line('${result.files.length} files, ${changed.length} to change.\n');
		var keys = [for( k in kinds.keys() ) k];
		keys.sort(Reflect.compare);
		if( keys.length > 0 ) {
			line("| Change | Count |");
			line("|---|--:|");
			for( k in keys ) line('| $k | ${kinds.get(k)} |');
		}
		var parents = [for( f in result.files ) for( p in f.report.parents ) '${f.path} ${p.path} (content now ${p.path}.${p.child}): ${p.reason}'];
		if( parents.length > 0 ) {
			line("\n## Objects moved under a parent\n");
			line("The parent takes the name, place, position and animation of the object; the object keeps its base rotation and scale and its content under the new name.\n");
			for( p in parents ) line('- $p');
		}
		var warnings = [for( f in result.files ) for( w in f.report.warnings ) w];
		if( warnings.length > 0 ) {
			line("\n## Warnings\n");
			for( w in warnings ) line('- $w');
		}
		if( result.errors.length > 0 ) {
			line("\n## Errors\n");
			for( e in result.errors ) line('- $e');
		}
		line("\n## Files\n");
		for( f in changed ) {
			line('- ${f.path} (${f.report.changes.length} changes)');
			if( verbose )
				for( c in f.report.changes ) line('  - ${c.path}: ${c.kind}');
		}
		return b.toString();
	}
}

package hrt.ui.tests;

import haxe.macro.*;

#if hui

class Macros {
	public static macro function assertSnapshot(a: ExprOf<Dynamic>, b: ExprOf<String>) {
		return macro @:privateAccess hrt.ui.tests.Macros.assertSnapshotImpl($a, $b, $v{Context.getPosInfos(b.pos)});
	}

	#if !macro

	static var pendingModifs: Array<{pos: haxe.macro.Expr.Position, content: String}> = [];
	static var updateMode = false;

	public static function init() {
		if (Sys.args().contains("-update-snapshot")) {
			updateMode = true;
		}
	}

	static function assertSnapshotImpl(actual: Dynamic, snapshotTest: String, testPos: haxe.macro.Expr.Position) {
		var ser = haxe.Serializer.run(actual);

		if (snapshotTest != ser) {
			var previous = try haxe.Unserializer.run(snapshotTest) catch(e) {"invalid": "data"};

			Sys.stdout().writeString('Snapshot test failed. Had :\r\n');
			Sys.stdout().writeString(haxe.Json.stringify(actual, null, "\t"));
			Sys.stdout().writeString('Wanted :\r\n');
			Sys.stdout().writeString(haxe.Json.stringify(previous, null, "\t"));

			if (!updateMode) {
				Sys.stdout().writeString("Tip: use -update-snapshot to update all the data if you are sure that the current data is correct");
			}
			Sys.stdout().flush();

			if (!updateMode) {
				throw "Snapshot failed";
			}
			else {
				pendingModifs.push({pos: testPos, content: ser});
			}
		}
	}

	public static function writeSnapshotModifs() {
		if (!updateMode)
			return;
		pendingModifs.sort((a,b) -> {
			var r = Reflect.compare(a.pos.file, b.pos.file);
			if (r != 0)
				return r;
			Reflect.compare(a.pos.min, b.pos.min);
		});

		var currentFile = null;
		var offset = 0;
		var currentContent = null;

		function flushContent() {
			if (currentFile != null && currentContent != null) {
				var finalPath = currentFile;
				trace("patched", finalPath);
				sys.io.File.saveContent(finalPath, currentContent);
			}
		}
		for (modif in pendingModifs) {
			if (currentFile != modif.pos.file) {
				flushContent();

				currentFile = modif.pos.file;
				if (!sys.FileSystem.exists(currentFile)) {
					currentContent = null;
					continue;
				}
				trace('starting patching ', currentFile);
				currentContent = sys.io.File.getContent(currentFile);
			}
			// the file doesn't exists, skip all remaining modifs for this file
			if (currentContent == null) {
				continue;
			}

			var toInsert = '\'${modif.content}\'';
			currentContent = currentContent.substring(0, modif.pos.min + offset) + toInsert + currentContent.substring(modif.pos.max + offset);
			offset += toInsert.length - (modif.pos.max - modif.pos.min);
		}

		flushContent();
	}
	#end
}

#end
package hide.html.comp;

import hide.html.WebComponent;

typedef AnimTarget = { path : String, match : Float };

@:keep
class ModelAnimPicker extends WebComponent {
	public var onPick : (modelPath : String) -> Void;
	public var onCancel : Void -> Void;

	var selected : String;

	public function new() {
		super();
		attachShadow({mode: OPEN});
		adoptStyleSheets([styleSheet]);
	}

	// animPath and previewModelPath are relative to the resource directory
	public function load( animPath : String, previewModelPath : Null<String> ) {
		var ide = hide.Ide.inst;
		var targets = findTargets(animPath);
		selected = previewModelPath ?? targets[0]?.path;

		var panel = js.Browser.document.createDivElement();
		panel.className = "panel";
		shadowRoot.append(panel);
		hide.html.Html.build(panel,
			<div class="content">
				<h2>This file does not contain any model</h2>
				<p>${targets.length > 0
					? "Pick a model to preview its animation on. Models are ranked by the ratio of animated objects found in their skeleton."
					: "No model plays the animations of this folder (same folder or hmd.animPaths)."}</p>
				<input id="filter" type="search" placeholder="Filter models..." hidden={targets.length == 0}/>
				<div id="list" class="targets" hidden={targets.length == 0}></div>
				<div class="footer">
					<hide-button label="Browse..." onclick={() -> ide.chooseFile(["fbx", "hmd"], (path) -> pick(path))}/>
					<hide-button label="Cancel" onclick={() -> onCancel()}/>
					<hide-button label="Preview" hidden={targets.length == 0} onclick={() -> pick(selected)}/>
				</div>
			</div>
		);

		var rows : Array<js.html.Element> = [];
		for (t in targets) {
			var name = t.path.split("/").pop();
			hide.html.Html.build(list,
				<div id="row" class="target" title={t.path}>
					<div class="name">
						<span>${name}</span>
						<span class="dir">${t.path.substr(0, t.path.length - name.length)}</span>
					</div>
					<span class="match">${Math.round(t.match * 100) + "%"}</span>
				</div>
			);
			row.classList.toggle("selected", t.path == selected);
			row.onclick = () -> {
				for (r in rows)
					r.classList.toggle("selected", r == row);
				selected = t.path;
			};
			row.ondblclick = () -> pick(t.path);
			rows.push(row);
		}

		filter.oninput = () -> {
			var text = filter.value.toLowerCase();
			for (i => r in rows)
				r.hidden = targets[i].path.toLowerCase().indexOf(text) < 0;
		};
	}

	function pick( path : Null<String> ) {
		if (path != null)
			onPick(hide.Ide.inst.makeRelative(path));
	}

	public static function findTargets( animPath : String ) : Array<AnimTarget> {
		var ide = hide.Ide.inst;
		var animDir = normalizeDir(haxe.io.Path.directory(ide.getPath(animPath)));
		var animated = [for (a in loadHeader(animPath).animations) for (o in a.objects) o.name => true];
		var count = Lambda.count(animated);
		if (count == 0)
			return [];

		var targets : Array<AnimTarget> = [];
		var dirCanPlayAnims : Map<String, Bool> = [];
		for (ext in ["fbx", "hmd"]) {
			for (f in hide.tools.FileManager.inst.getFilesWithExt(ext)) {
				if (f.ignored || h3d.anim.Animation.isAnimation(f.name))
					continue;
				var dir = f.parent.getPath();
				var canPlay = dirCanPlayAnims.get(dir);
				if (canPlay == null) {
					canPlay = canPlayAnimsFrom(f.getPath(), animDir);
					dirCanPlayAnims.set(dir, canPlay);
				}
				if (!canPlay)
					continue;

				// a broken asset of the folder must not prevent picking the others
				var header = try loadHeader(f.getPath()) catch (e : Dynamic) continue;
				var names = new Map();
				for (m in header.models) {
					names.set(m.getObjectName(), true);
					if (m.skin != null)
						for (j in m.skin.joints)
							names.set(j.name, true);
				}
				var found = 0;
				for (n in animated.keys())
					if (names.exists(n))
						found++;
				if (found > 0)
					targets.push({ path : f.getRelPath(), match : found / count });
			}
		}
		targets.sort((a, b) -> a.match != b.match ? (a.match < b.match ? 1 : -1) : Reflect.compare(a.path, b.path));
		return targets;
	}

	static function loadHeader( path : String ) {
		return hxd.res.Loader.currentInstance.load(hide.Ide.inst.makeRelative(path)).toModel().toHmd().header;
	}

	static function canPlayAnimsFrom( modelPath : String, animDir : String ) {
		var ide = hide.Ide.inst;
		if (normalizeDir(haxe.io.Path.directory(modelPath)) == animDir)
			return true;
		var dirs : Array<String> = hide.Config.loadForFile(ide, modelPath).get("hmd.animPaths", []);
		for (d in dirs) {
			var recursive = StringTools.endsWith(d, "*");
			if (recursive)
				d = d.substr(0, -1);
			var dir = normalizeDir(haxe.io.Path.join([ide.resourceDir, d]));
			if (animDir == dir || (recursive && StringTools.startsWith(animDir, dir + "/")))
				return true;
		}
		return false;
	}

	static function normalizeDir( dir : String ) {
		return haxe.io.Path.removeTrailingSlashes(haxe.io.Path.normalize(dir)).toLowerCase();
	}

	static var _ = register(ModelAnimPicker, "hide-model-anim-picker");
}

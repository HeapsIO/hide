package hide.view.settings;

typedef LocalSetting = {
	var folder : String;
	var file : String;
	var content : Dynamic;
}

enum Filter {
	NONE;
	LOD;
	MATLIB;
	RENDERPROPS;
}

class ProjectSettings extends hide.ui.View<{}> {
	public static var SETTINGS_FILE = "props.json";

	public static var MATLIB_ENTRY = "materialLibraries";
	public static var RENDERPROPS_ENTRY = "scene.renderProps";
	public static var LOD_ENTRY = "lods.screenRatio";

	var settings : Array<LocalSetting>;
	var currentFilter = Filter.NONE;

	public function new( ?state ) {
		super(state);
		settings = [];
		getPropsFiles(ide.projectDir);
	}

	override function getTitle() {
		return "Project Settings";
	}

	override function onDisplay() {
		keys.register("undo", function() undo.undo());
		keys.register("redo", function() undo.redo());

		var root = new Element('<div class="project-settings">
			<h1>Project settings</h1>
			<div class="body">
				<div class="left-panel">
					<h2>Settings</h2>
					<div class="filter-container">
						<p>Filter : </p>
						<select class="filter">
							<option value="0" selected>None</option>
							<option value="1">LODs</option>
							<option value="2">Material libraries</option>
							<option value="3">Render props</option>
						</select>
					</div>
				</div>
				<div class="right-panel">
				</div>
			</div>
		</div>').appendTo(element);

		var overridesEl = new Element('<div class="array">
			<div class="rows">
			</div>
			<div class="buttons">
				<div class="add-btn icon ico ico-plus"></div>
				<div class="remove-btn icon ico ico-minus"></div>
			</div>
		</div>').appendTo(element.find(".left-panel"));

		function updateOverrides() {
			var rows = overridesEl.find(".rows");
			rows.empty();

			for (s in settings) {
				var row = new Element('<div class="row">
					<div class="ico ico-circle"></div>
				</div>').appendTo(rows);

				var filtered = false;
				if (!currentFilter.match(Filter.NONE)) {
					filtered = filtered || currentFilter.match(Filter.LOD) && !Reflect.hasField(s.content, LOD_ENTRY);
					filtered = filtered || currentFilter.match(Filter.MATLIB) && !Reflect.hasField(s.content, MATLIB_ENTRY);
					filtered = filtered || currentFilter.match(Filter.RENDERPROPS) && !Reflect.hasField(s.content, RENDERPROPS_ENTRY);
				}

				row.toggleClass('filtered', filtered);

				row.click(function(e) {
					overridesEl.find(".selected").removeClass('selected');
					row.addClass("selected");
					inspect(s);
				});

				var fileSelect = new hide.comp.FileSelect(null, row, null);
				fileSelect.path = s.folder;
			}
		}

		updateOverrides();

		var filterEl = root.find(".filter");
		filterEl.on('change', function(e) {
			currentFilter = haxe.EnumTools.createByIndex(Filter, Std.parseInt(filterEl.val()));
			updateOverrides();
		});

		overridesEl.find(".add-btn").click(function(e){
			ide.chooseDirectory(function(path) {
				var fpath = '${path}/${SETTINGS_FILE}';
				if (sys.FileSystem.exists(fpath)) {
					ide.quickError("Settings already exist in this folder");
					return;
				}
				sys.io.File.saveContent(fpath, "{}");
				settings.push({folder: path, file: fpath, content: {}});
				updateOverrides();
			}, true, false);
		});

		overridesEl.find(".remove-btn").click(function(e){
			if (settings == null || settings.length == 0)
				return;

			var selIdx = getSelectionIdxInArray(overridesEl, settings);

			sys.FileSystem.deleteFile(settings[selIdx].file);
			settings.remove(settings[selIdx]);
			updateOverrides();
			element.find(".right-panel").empty();
		});
	}

	function inspect(s : LocalSetting) {
		element.find(".right-panel").empty();

		var obj = s.content;

		function onChange(file : String, oldObj : Dynamic, newObj : Dynamic) {
			sys.io.File.saveContent(file, haxe.Json.stringify(newObj, '\t'));
			inspect(s);

			undo.change(Custom(function(undo) {
				// TODO
				// var o = oldObj;
				// var n = newObj;
				// obj = undo ? o : n;
				// sys.io.File.saveContent(settings[0].file, haxe.Json.stringify(obj, '\t'));
				// onDisplay();
			}));
		}

		// Material library
		var matLibs : Array<Dynamic> = Reflect.field(obj, MATLIB_ENTRY);
		var matLibsEl = new Element('<div>
			<h2>Material libraries</h2>
			<div class="array">
				<div class="rows"></div>
				<div class="buttons">
					<div class="add-btn icon ico ico-plus"></div>
					<div class="remove-btn icon ico ico-minus"></div>
				</div>
			</div>
		</div>').appendTo(element.find(".right-panel"));

		if (matLibs != null) {
			for (ml in matLibs) {
				var row = new Element('<div class="row">
					<div class="ico ico-circle"></div>
					<input value="${Reflect.field(ml, "name")}"/>
				</div>').appendTo(matLibsEl.find(".rows"));

				row.click(function(e) {
					matLibsEl.find(".row").removeClass("selected");
					row.addClass("selected");
				});

				var nameInput = row.find("input");
				nameInput.change(function(e) {
					var oldObj = Reflect.copy(obj);
					Reflect.setField(ml, "name", nameInput.val());
					onChange(s.file, oldObj, obj);
				});

				var file = new hide.comp.FileSelect(["prefab"], row, null);
				file.path = Reflect.field(ml, "path");
				file.onChange = function() {
					var oldObj = Reflect.copy(obj);
					Reflect.setField(ml, "path", file.path);
					onChange(s.file, oldObj, obj);
				};
			}
		}

		matLibsEl.find(".add-btn").click(function(e) {
			if (matLibs == null) {
				matLibs = [];
				Reflect.setField(obj, MATLIB_ENTRY, matLibs);
			}

			var selIdx = getSelectionIdxInArray(matLibsEl, matLibs);
			var oldObj = Reflect.copy(obj);
			matLibs.insert(selIdx + 1, {name:"New", path:null});
			onChange(s.file, oldObj, obj);
		});

		matLibsEl.find(".remove-btn").click(function(e) {
			if (matLibs == null)
				return;

			var selIdx = getSelectionIdxInArray(matLibsEl, matLibs);
			var oldObj = Reflect.copy(obj);
			matLibs.remove(matLibs[selIdx]);
			if (matLibs.length == 0) {
				Reflect.deleteField(obj, MATLIB_ENTRY);
				matLibs = null;
			}
			onChange(s.file, oldObj, obj);

		});

		// Render props
		var renderProps : Array<Dynamic> = Reflect.field(obj, RENDERPROPS_ENTRY);
		var renderPropsEl = new Element('<div>
			<h2>Render props</h2>
			<div class="array">
				<div class="rows"></div>
				<div class="buttons">
					<div class="add-btn icon ico ico-plus"></div>
					<div class="remove-btn icon ico ico-minus"></div>
				</div>
			</div>
		</div>').appendTo(element.find(".right-panel"));

		renderPropsEl.find(".add-btn").click(function(e) {
			if (renderProps == null) {
				renderProps = [];
				Reflect.setField(obj, RENDERPROPS_ENTRY, renderProps);
			}

			var selIdx = getSelectionIdxInArray(renderPropsEl, renderProps);
			var oldObj = Reflect.copy(obj);
			renderProps.insert(selIdx + 1, {name:"New", value:null});
			onChange(s.file, oldObj, obj);
		});

		renderPropsEl.find(".remove-btn").click(function(e) {
			if (renderProps == null)
				return;

			var selIdx = getSelectionIdxInArray(renderPropsEl, renderProps);
			var oldObj = Reflect.copy(obj);
			renderProps.remove(renderProps[selIdx]);
			if (renderProps.length == 0) {
				Reflect.deleteField(obj, RENDERPROPS_ENTRY);
				renderProps = null;
			}
			onChange(s.file, oldObj, obj);

		});

		if (renderProps != null) {
			for (rp in renderProps) {
				var row = new Element('<div class="row">
					<div class="ico ico-circle"></div>
					<input value="${Reflect.field(rp, "name")}"/>
				</div>').appendTo(renderPropsEl.find(".rows"));

				row.click(function(e) {
					renderPropsEl.find(".row").removeClass("selected");
					row.addClass("selected");
				});

				var nameInput = row.find("input");
				nameInput.change(function(e) {
					var oldObj = Reflect.copy(obj);
					Reflect.setField(rp, "name", nameInput.val());
					onChange(s.file, oldObj, obj);
				});

				var file = new hide.comp.FileSelect(["prefab"], row, null);
				file.path = Reflect.field(rp, "value");
				file.onChange = function() {
					var oldObj = Reflect.copy(obj);
					Reflect.setField(rp, "value", file.path);
					onChange(s.file, oldObj, obj);
				};
			}
		}
	}

	function getSelectionIdxInArray(arrEl : Element, arr : Array<Dynamic>) {
		var selIdx = arr.length - 1;
			for (idx in 0...arr.length)
				if (arrEl.find(".row").eq(idx).hasClass("selected"))
					selIdx = idx;
			return selIdx;
	}

	function getPropsFiles(path: String) {
		var res : Array<LocalSetting> = [];
		var settingsPath = '${path}/${ProjectSettings.SETTINGS_FILE}';

		if (sys.FileSystem.exists(settingsPath)) {
			var content = sys.io.File.getContent(settingsPath);
			var obj = try haxe.Json.parse(content) catch( e : Dynamic ) throw "Failed to parse " + settingsPath + "("+e+")";
			var tmp = settingsPath.split('/');
			tmp.pop();
			settings.push({folder: tmp.join("/"), file: settingsPath, content: obj});
		}

		for (f in sys.FileSystem.readDirectory(path)) {
			if (!sys.FileSystem.isDirectory('${path}/${f}'))
				continue;

			getPropsFiles('${path}/${f}');
		}
	}

	static var _ = hide.ui.View.register(ProjectSettings);
}

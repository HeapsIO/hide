package hide.kit;

#if domkit

class Matlib extends Widget<String> {

	var path : String;
	var libSelect : Select;
	var matSelect : Select;
	var category : Element;

	override public function new(parent: Element, id: String, path: String) {
		super(parent, id);
		this.path = path;

		build(
			<category("Material Library") id="cat">
				<select([]) value={null} id="libSelect" label="Library"/>
				<select([]) value={null} id="matSelect" label="Material"/>
				<button("Go to library") onClick={goToLibrary}/>
			</category>
		);

		this.category = cat;
		this.libSelect = libSelect;
		this.matSelect = matSelect;

		libSelect.onValueChange = (_) -> {
			var newValue = libSelect.value;
			if (newValue == null) {
				value = null;
				broadcastValueChange(false);
				matSelect.setEntries([]);
			} else {
				if (newValue != value) {
					value = null;
					broadcastValueChange(false);
					matSelect.setEntries(getMaterialList(newValue));
				}
			}
		}

		matSelect.onValueChange = (_) -> {
			if (libSelect.value != null && matSelect.value != null) {
				value = libSelect.value + "/" + matSelect.value;
			} else {
				value = null;
			}
			broadcastValueChange(false);
			syncValueUI();
		}
	}

	function goToLibrary() {
		if (libSelect.value != null)
			root.editor.openPrefab(libSelect.value, (api) -> {
				var root = api.getRootPrefab();
				for (p in root.flatten(hrt.prefab.Material)) {
					if (p.name == matSelect.value) {
						api.selectPrefabs([p]);
						#if editor
						api.focusObjects([@:privateAccess p.previewSphere]);
						#end
					}
				}
			});
	}

	override public function makeSelf() : Void {
		#if js
		native = js.Browser.document.createDivElement();
		#end
		syncValueUI();
	}

	override function propagateChange(kind: hide.kit.Element.ChangeKind) {
		switch (kind) {
			case Value(inputs, isTemporary):
				for (input in inputs) {
					input.onValueChange(isTemporary);
				}
			case Click(button):
				button.onClick();
		}
	}

	function getMaterialList(library: String) {
		var none = {value: null, label:"None"};
		var entries = [];

		var prefab = try hxd.res.Loader.currentInstance.load(library).toPrefab().load() catch(e) return [none];

		var mats = prefab.findAll(hrt.prefab.Material);
		for (m in mats)
			entries.push({value: m.name, label: m.name});
		entries.sort((a, b) -> Reflect.compare(a.label, b.label));
		entries.unshift(none);
		return entries;
	}

	function getLibraryList() {
		var matLibs = root.editor.listMaterialLibraries(path);
		var libEntries = [{value: null, label: "None"}];
		for (lib in matLibs) {
			libEntries.push({value: lib.path, label: lib.name});
		}
		return libEntries;
	}

	override function syncValueUI() {
		if (libSelect != null) {
			var lib = value == null ? null : value.substring(0, value.lastIndexOf("/"));
			var mat = value == null ? null : value.substring(value.lastIndexOf("/") + 1);
			libSelect.setEntries(getLibraryList());
			matSelect.setEntries(getMaterialList(lib));
			libSelect.value = lib;
			matSelect.value = mat;
		}
	}

	function makeInput():NativeElement {
		return native;
	}

	function stringToValue(str:String):Null<String> {
		return str;
	}

	function getDefaultFallback():String {
		return null;
	}
}

#end
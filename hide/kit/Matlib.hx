package hide.kit;

#if domkit

// class Matlib extends Widget<String> {

// 	var path : String;

// 	var libSelect : Select;
// 	var matSelect : Select;

// 	override public function new(parent: Element, id: String, path: String) {
// 		super(parent, id);
// 		this.path = path;

// 		build(
// 			<category("Material Library") id="cat">
// 				<select([]) value={null} id="libSelect"/>
// 				<select([]) value={null} id="matSelect"/>
// 			</category>
// 		);

// 		this.libSelect = libSelect;
// 		this.matSelect = matSelect;

// 		libSelect.onValueChange = (_) -> {
// 			var newValue = libSelect.value;
// 			if (newValue == null) {
// 				value = null;
// 				broadcastValueChange(false);
// 			} else {
// 				if (newValue != value) {
// 					value = null;
// 					broadcastValueChange(false);
// 				}
// 			}
// 		}

// 		matSelect.onValueChange = (_) -> {
// 			if (libSelect.value != null && matSelect.value != null) {
// 				value = libSelect.value + "/" + matSelect.value;
// 			} else {
// 				value = null;
// 			}
// 			broadcastValueChange(false);
// 		}
// 	}

// 	override public function makeSelf() : Void {

// 		var matLibs = root.editor.listMatLibraries(path);

// 		var libEntries = [{value: null, label: "None"}];
// 		for (lib in matLibs) {
// 			libEntries.push({value: lib.path, label: lib.name});
// 		}

// 		build(
// 			<category("Material Library") id="cat">
// 				<select(libEntries) value={null} id="libSelect"/>
// 				<select([]) value={null} id="matSelect"/>
// 			</category>
// 		);

// 		this.libSelect = libSelect;
// 		this.matSelect = matSelect;

// 		libSelect.onValueChange = (_) -> {
// 			var newValue = libSelect.value;
// 			if (newValue == null) {
// 				value = null;
// 				broadcastValueChange(false);
// 			} else {
// 				if (newValue != value) {
// 					value = null;
// 					broadcastValueChange(false);
// 				}
// 			}
// 		}

// 		matSelect.onValueChange = (_) -> {
// 			if (libSelect.value != null && matSelect.value != null) {
// 				value = libSelect.value + "/" + matSelect.value;
// 			} else {
// 				value = null;
// 			}
// 			broadcastValueChange(false);
// 		}

// 		cat.make();
// 		native = cat.native;
// 		input = native;

// 		syncValueUI();
// 	}

// 	function refreshMatSelect() {
// 		var mats = root.editor.listMaterialFromLibrary(path, libSelect.value);
// 		var entries = [{value: null, label:"None"}];
// 		for (mat in mats) {
// 			entries.push({value: mat.path, label: mat.path});
// 		}
// 		matSelect.entries = entries;
// 	}

// 	function refreshLibSelect() {
// 		var matLibs = root.editor.listMatLibraries(path);
// 		var libEntries = [{value: null, label: "None"}];
// 		for (lib in matLibs) {
// 			libEntries.push({value: lib.path, label: lib.name});
// 		}
// 		libSelect.entries = libEntries;
// 	}

// 	override function syncValueUI() {
// 		if (libSelect != null) {
// 			libSelect.value = value == null ? null : value.substring(0, value.lastIndexOf("/"));
// 			matSelect.value = value == null ? null : value.substring(0, value.lastIndexOf("/"));
// 			refreshLibSelect();
// 			refreshMatSelect();
// 		}
// 	}

// 	function makeInput():NativeElement {
// 		return native;
// 	}

// 	function stringToValue(str:String):Null<String> {
// 		return str;
// 	}

// 	function getDefaultFallback():String {
// 		return null;
// 	}
// }

#end
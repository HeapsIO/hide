package hrt.ui;

#if hui
enum MaterialLibraryMode {
	Model;
	Folder;
}

@:allow(hide.view.Model)
class HuiMaterialInspector extends HuiElement {
	static var SRC = <hui-material-inspector>
		<hui-category("Material Library")>
			<hui-element class="horizontal"><hui-text("Library") class="label"/><hui-select class="value" id="library-el"/></hui-element>
			<hui-element class="horizontal"><hui-text("Material") class="label"/><hui-select class="value" id="material-el"/></hui-element>
			<hui-element class="horizontal"><hui-text("Mode") class="label"/><hui-select class="value" id="mode-el"/></hui-element>
			<hui-button class="full" id="goto-btn"><hui-text("Go to library")></hui-text></hui-button>
		</hui-category>
		<hui-category("Textures")>
		</hui-category>
		<hui-category("Material")>
		</hui-category>
	</hui-material-inspector>

	var model : hide.view.Model;
	var mat : h3d.mat.Material;
	var props : Dynamic = null;
	var selectedLib = null;
	var selectedMat = null;
	var materials = [];

	public function new(mat : h3d.mat.Material, model: hide.view.Model, ?parent: h2d.Object) {
		super(parent);
		this.model = model;
		this.mat = mat;

		initComponent();

		updateMaterialLibraryInspector();
	}

	function updateMaterialLibraryInspector() {
		var def = false;
		props = @:privateAccess model.materialSettings.get(mat.name);
		if (props != null && props.__ref != null && !def) {
			selectedMat = props.__ref + "/" + props.name;
			selectedLib = props.__ref;
		}
		else {
			def = true;
		}

		var matLibs : Array<{ path : String, name : String}> = cast HuiSceneEditor.getMaterialLibraries(@:privateAccess model.state.path);
		materials = [];

		modeEl.items = [{ value: MaterialLibraryMode.Model, label: "Model Specific" },
		{ value: MaterialLibraryMode.Folder, label: "Shared By Folder" }];

		libraryEl.items = [ for (m in matLibs) { value: m.path, label: m.name}];
		libraryEl.items.insert(0, { value: null, label: "None" });

		materialEl.items.insert(0, { value: null, label: "None" });

		if (def) {
			libraryEl.value = null;
			materialEl.value = null;
			modeEl.value = MaterialLibraryMode.Folder;
		}
		else {
			if (props?.__ref != null) {
				libraryEl.value = props.__ref;
				for (matLib in matLibs) {
					if (matLib.path == libraryEl.value)
						selectedLib = matLib;
				}
				materials = HuiSceneEditor.getMaterialsFromLibrary(@:privateAccess model.state.path, selectedLib.name);
				materialEl.items = [ for (mat in materials) { value: mat.path + "/" + mat.mat.name, label: mat.mat.name }];
				materialEl.items.insert(0, { value: null, label: "None" });
			}
			if (props?.name != null) {
				var material = findMaterial(libraryEl.value + "/" + props.name);
				materialEl.value = material.path + "/" + material.mat.name;
				selectedMat = materialEl.value;
			}
			var isModelMode = props != null && props.__refMode != null && ((props: Dynamic).__refMode == "modelSpec");
			modeEl.value = isModelMode ? MaterialLibraryMode.Model : MaterialLibraryMode.Folder;
		}

		libraryEl.onValueChanged = () -> {
			selectedLib = null;
			for (matLib in matLibs) {
				if (matLib.path == libraryEl.value)
					selectedLib = matLib;
			}

			materials = selectedLib == null ? [] : HuiSceneEditor.getMaterialsFromLibrary(@:privateAccess model.state.path, selectedLib.name);
			materialEl.value = null;
			materialEl.items = [ for (mat in materials) { value: mat.path + "/" + mat.mat.name, label: mat.mat.name }];
			materialEl.items.insert(0, { value: null, label: "None" });
			onChange();
		}

		materialEl.onValueChanged = () -> {
			onChange();
		}

		gotoBtn.onClick = (_) -> {
			var material = findMaterial(selectedMat);
			if (material != null) {
				var matName = material.mat.name;
				hide.Ide.inst.openFile(Reflect.field(material, "path"), (v) -> {
					var prefabView = Std.downcast(v, hide.view.Prefab);
					var sceneEditor = @:privateAccess prefabView.sceneEditor;
					haxe.Timer.delay(() -> {
						for (p in @:privateAccess prefabView.prefab.flatten(hrt.prefab.Material)) {
							if (p != null && p.name == matName) @:privateAccess {
								prefabView.setSelection([p], NoRecordUndo);
								if (p.previewSphere != null) {
									prefabView.sceneEditor.focusObjects([p.previewSphere]);
								}
							}
						}
					}, 0);
				});
			}
			else if (selectedLib.path != null) {
				hide.Ide.inst.openFile(selectedLib.path);
			}
		}
	}

	function onChange() {
		var prevV = selectedMat;
		selectedMat = materialEl.value;
		var newV = selectedMat;

		function exec(undo : Bool) {
			selectedMat = undo ? prevV : newV;
			var material = findMaterial(selectedMat);
			if (material != null) {
				@:privateAccess material.mat.update(mat, material.mat.renderProps(), function(path: String) {
					return hxd.res.Loader.currentInstance.load(path).toTexture();
				});
			}
			else {
				var defaultMat = h3d.mat.MaterialSetup.current.createMaterial();
				for (f in Reflect.fields(mat)) {
					if (f == "name" || f == "model")
						continue;
					Reflect.setField(mat, f, Reflect.field(defaultMat, f));
				}
				mat.props = defaultMat.getDefaultProps();
			}

			materialEl.value = material == null ? null : material.path + "/" + material.mat.name;

			if (material?.mat?.name != null) {
				props = { __ref: libraryEl.value, name: material?.mat?.name };
				@:privateAccess model.materialSettings.set(mat.name, props);
			}
			else {
				props = null;
				@:privateAccess model.materialSettings.remove(mat.name);
			}
		}

		exec(false);
		getView().undo.record(exec, true);
	}

	function findMaterial(mname : String) {
		var material : { path : String, mat : hrt.prefab.Material } = null;
		for (mat in materials) {
			if (mat.path + "/" + mat.mat.name == mname)
				material = mat;
		}

		return material;
	}
}
#end
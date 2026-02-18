package hrt.ui;

#if hui

enum SelectionFlag {
	NoRefreshTree;
	NoRecordUndo;
}

typedef SelectionFlags = haxe.EnumFlags<SelectionFlag>;

@:access(hrt.prefab.Prefab)
class HuiPrefabEditor extends HuiElement {
	static var SRC =
		<hui-prefab-editor>
			<hui-split-container id="main-split">

				<hui-split-container id="scene-tree-split">
					<hui-element id="scene-panel">
						<hui-element id="scene-toolbar"/>
						<hui-scene id="scene"/>
					</hui-element>
					<hui-element id="panel-tree">

					</hui-element>
				</hui-split-container>

				<hui-element id="inspector-panel">
					<hui-text("inspector")/>
				</hui-element>
			</hui-split-container>
		</hui-prefab-editor>

	var prefab: hrt.prefab.Prefab;
	var errorMessage : h2d.Text;
	var cameraController : h3d.scene.CameraController;
	var treePrefab: hrt.ui.HuiTree<hrt.prefab.Prefab>;

	var selectedPrefabs: Map<hrt.prefab.Prefab, Bool> = [];

	var config : hide.Config;

	override function new(?parent) {
		super(parent);
		initComponent();

		errorMessage = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
		cameraController = new h3d.scene.CameraController(scene.s3d);

		treePrefab = new hrt.ui.HuiTree<hrt.prefab.Prefab>(panelTree);
		treePrefab.getItemChildren = treePrefabGetItemChildren;
		treePrefab.getItemName = (p: hrt.prefab.Prefab) -> p.name;
		treePrefab.onUserSelectionChanged = () -> {
			setSelection(treePrefab.getSelectedItems(), NoRefreshTree);
		}
	}

	function setSelection(selection: Array<hrt.prefab.Prefab>, flags: SelectionFlags) {
		if (!flags.has(NoRecordUndo)) {

		}

		selectedPrefabs.clear();

		for (prefab in selection) {
			selectedPrefabs.set(prefab, true);
		}

		if (!flags.has(NoRefreshTree)) {
			treePrefab.setSelection(selection);
		}

		refreshInspector();
	}

	function refreshInspector() {
		var selection : Array<hrt.prefab.Prefab> = [ for (prefab => _ in selectedPrefabs) prefab];

		var commonClass = hrt.tools.ClassUtils.getCommonClass(selection, hrt.prefab.Prefab);

		var isMultiEdit = selection.length > 1;
		var editPrefab : hrt.prefab.Prefab = if (isMultiEdit) {
			var p = Type.createInstance(commonClass, [null, new hrt.prefab.ContextShared(selection[0].shared.currentPath)]);
			p.load(haxe.Json.parse(haxe.Json.stringify(selection[0].save())));
			p;
		} else {
			selection[0];
		}

		var editContext = new EditContext(this, null);
		var baseRoot = new hide.kit.KitRoot(null, null, editPrefab, editContext);
		@:privateAccess baseRoot.isMultiEdit = isMultiEdit;

		//@:privateAccess editContext.saveKey = Type.getClassName(commonClass);
		editContext.root = baseRoot;

		editPrefab.edit2(editContext);
		baseRoot.postEditStep();

		if (isMultiEdit) {
			for (i => prefab in selection) {
				var childEditContext = new EditContext(this, editContext);
				//@:privateAccess childEditContext.saveKey = Type.getClassName(commonClass);
				var childRoot = new hide.kit.KitRoot(null, null, prefab, childEditContext);
				@:privateAccess childRoot.isMultiEdit = true;
				childEditContext.root = childRoot;
				prefab.edit2(childEditContext);
				childRoot.postEditStep();
			}
		}

		baseRoot.make();

		inspectorPanel.removeChildElements();
		inspectorPanel.addChild(@:privateAccess baseRoot.native);
	}

	function treePrefabGetItemChildren(prefab: hrt.prefab.Prefab) {
		prefab = prefab ?? this.prefab;
		return cast prefab.children;
	}

	function getEnvMap() {
		var env = config.get("scene.environment") ?? "";
		var path = "";
		var image = if (hxd.res.Loader.currentInstance.exists(env)) {
			path = env;
			hxd.res.Loader.currentInstance.load(env).toImage();
		} else {
			path = "env/defaultEnv.jpg";
			HuiRes.loader.load(path).toImage();
		}
		var pix = image.getPixels();
		var t = h3d.mat.Texture.fromPixels(pix, h3d.mat.Texture.nativeFormat); // sync
		t.setName(path);
		return t;
	}


	public function setPrefab(newPrefab: hrt.prefab.Prefab) {
		if (prefab != null) {
			prefab.shared.root2d.remove();
			prefab.shared.root3d.remove();
			prefab = null;
		}

		prefab = newPrefab;

		if (prefab.shared.prefabSource != null) {
			config = hide.Config.loadForFile(hide.Ide.inst, prefab.shared.prefabSource);
		} else {
			config = hide.Ide.inst.currentConfig;
		}

		var env = new h3d.scene.pbr.Environment(getEnvMap());
		env.compute();
		scene.s3d.renderer = new hide.Renderer.PbrRenderer(env);
		scene.s3d.lightSystem = new h3d.scene.pbr.LightSystem();

		tryMake(prefab);
		makeRenderProps();

		focusObjects([for (i in 0...scene.s3d.numChildren) scene.s3d.getChildAt(i)]);
	}

	function getRenderPropsPaths() : Array<{name: String, value: String}> {
		var renderProps = config.getLocal("scene.renderProps");
		if (renderProps == null)
			return [];

		if (renderProps is String) {
			return [{name: "", value: (cast renderProps: String)}];
		}

		if (renderProps is Array) {
			return cast renderProps;
		}
		return [];
	}

	public function focusObjects(objs : Array<h3d.scene.Object>) {
		var focusChanged = false;
		// for (o in objs) {
		// 	if (!lastFocusObjects.contains(o)) {
		// 		focusChanged = true;
		// 		break;
		// 	}
		// }

		if(objs.length > 0) {
			var bnds = new h3d.col.Bounds();
			var centroid = new h3d.Vector();
			for(obj in objs) {
				centroid = centroid.add(obj.getAbsPos().getPosition());
				bnds.add(obj.getBounds());
			}
			if(!bnds.isEmpty()) {
				var s = bnds.toSphere();
				var r = focusChanged ? null : s.r * 4.0;
				cameraController.set(r, null, null, s.getCenter());
			}
			else {
				centroid.scale(1.0 / objs.length);
				cameraController.set(centroid.toPoint());
			}
		}
		//lastFocusObjects = objs;
	}


	public function tryMake(prefab: hrt.prefab.Prefab) : Bool {
		if (prefab != null) {
			prefab.shared.root2d?.remove();
			prefab.shared.root3d?.remove();
		}
		errorMessage.text = "";

		@:privateAccess prefab.shared.root2d = prefab.shared.current2d = new h2d.Object(scene.s2d);
		@:privateAccess prefab.shared.root3d = prefab.shared.current3d = new h3d.scene.Object(scene.s3d);

		try {
			prefab.make();
		} catch (e) {
			prefab.shared.root2d?.remove();
			prefab.shared.root3d?.remove();

			errorMessage.text = "Error loading prefab : " + e;

			trace("Error loading prefab " + e);
			return false;
		}

		var fx = Std.downcast(prefab.findFirstLocal3d(), hrt.prefab.fx.FX.FXAnimation);
		if (fx != null) {
			fx.loop = true;
		}

		treePrefab.rebuild();
		return true;
	}

	public function makeRenderProps() {
		var paths = getRenderPropsPaths();
		for (path in paths) {
			var renderProp = hxd.res.Loader.currentInstance.load(path.value).toPrefab().load().clone();
			if (tryMake(renderProp))
				break;
		}
	}
}

@:access(hrt.ui.HuiPrefabEditor)
class EditContext extends hrt.prefab.EditContext2 {
	var editor : HuiPrefabEditor;

	public function new(editor: HuiPrefabEditor, parent: hrt.prefab.EditContext2) {
		super(parent);
		this.editor = editor;
	}

	public function rebuildInspector() : Void {
		throw "implement";
	};

	public function rebuildPrefab(prefab: hrt.prefab.Prefab) : Void {
		throw "implement";
	}

	/**
		Request that the scene tree widget should be rebuild for the given prefab
	**/
	public function rebuildTree(prefab: hrt.prefab.Prefab) : Void {
		editor.treePrefab.rebuild();
	}


	public function getScene3d() : h3d.scene.Scene {
		return editor.scene.s3d;
	}

	public function getScene2d() : h2d.Scene {
		return editor.scene.s2d;
	}

	/**
		Return the camera controller of the current editor
	**/
	public function getCameraController3d() : Dynamic {
		return editor.cameraController;
	}

	public function openFile(path: String) : Void {
		return hide.Ide.inst.openFile(path);
	}

	public function openPrefab(path: String, ?afterOpen : (ctx: hrt.prefab.SceneEditorAPI) -> Void) : Void {
		throw "implement";
		return hide.Ide.inst.openFile(path);
	}

	/**
		Prompt the user to select a file, and then call callback with the chosen path.
	**/
	public function chooseFileSave(path: String, callback:(absPath: String) -> Void, allowNull: Bool = false) : Void {
		throw "implement";
	}

	public function listMaterialLibraries(path: String) : Array<{path: String, name: String}> {
		throw "implement";
	}

	public function quickError(message: String) : Void {
		hide.Ide.showError(message);
	}

	public function screenToGround(sx: Float, sy: Float, ?paintOn : hrt.prefab.Prefab, ignoreTerrain: Bool = false) : h3d.Vector {
		throw "implement";
	}

	public function recordUndo(callback: (isUndo: Bool) -> Void ) : Void {
		throw "implement";
	}

	function saveSetting(category: hrt.prefab.EditContext2.SettingCategory, key: String, value: Dynamic) : Void {
		throw "implement";
	}
	function getSetting(category: hrt.prefab.EditContext2.SettingCategory, key: String) : Null<Dynamic> {
		throw "implement";
	}

	function getRootObjects3d() : Array<h3d.scene.Object> {
		throw "implement";
	}
}

#end
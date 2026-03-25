package hrt.ui;

#if hui

using Lambda;

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
				</hui-element>
			</hui-split-container>
		</hui-prefab-editor>

	static public var gizmoSwitchModeCommand = new hrt.ui.HuiCommands.HuiCommand("Copy", {key: hxd.Key.SPACE});
	static public var gizmoTranslateCommand = new hrt.ui.HuiCommands.HuiCommand("Paste", {key: hxd.Key.W});
	static public var gizmoRotateCommand = new hrt.ui.HuiCommands.HuiCommand("Save", {key: hxd.Key.E});
	static public var gizmoScaleCommand = new hrt.ui.HuiCommands.HuiCommand("Cut", {key: hxd.Key.R});

	var prefab: hrt.prefab.Prefab;
	var renderProps: hrt.prefab.Prefab;

	var errorMessage : h2d.Text;
	var cameraController : h3d.scene.CameraController;
	var treePrefab: hrt.ui.HuiTree<hrt.prefab.Prefab>;
	var interactives: Map<hrt.prefab.Prefab, h3d.scene.Interactive> = [];
	var lastSaveUndo: Any = null;

	var selectedPrefabs: Map<hrt.prefab.Prefab, Bool> = [];

	var config : hide.Config;

	// Gizmos and guides
	var grid : hrt.tools.Grid = null;
	var viewportAxis : hrt.tools.ViewportAxis = null;
	var gizmo : hrt.tools.Gizmo = null;

	var lastPushX : Float = -100;
	var lastPushY : Float = -100;
	var movedSinceLastPush : Bool = false;

	var debugGraph: h2d.Graphics;

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

		scene.s3d.addEventListener(onSceneEvents);

		registerCommand(hrt.ui.HuiCommands.HuiDebugCommands.debugReload, View, reload);

		debugGraph = new h2d.Graphics(scene.s2d);
	}

	override function sync(ctx : h2d.RenderContext) {
		super.sync(ctx);
		gizmo.update(ctx.elapsedTime);
	}

	function setSelection(selection: Array<hrt.prefab.Prefab>, flags: SelectionFlags) {
		var oldSelection = [for (p => _ in selectedPrefabs) p];

		for (s in selectedPrefabs.keys()) {
			var obj3d = Std.downcast(s, hrt.prefab.Object3D);
			if (obj3d != null && obj3d.local3d != null) {
				for (m in obj3d.local3d.getMaterials()) {
					var p = m.getPass("highlight");
					if (p == null) continue;
					m.removePass(p);
				}
			}
		}

		selectedPrefabs.clear();

		var objs = [];
		for (prefab in selection) {
			selectedPrefabs.set(prefab, true);
			var obj3d = Std.downcast(prefab, hrt.prefab.Object3D);
			if (obj3d != null && obj3d.local3d != null) {
				objs.push(obj3d.local3d);
				for (m in obj3d.local3d.getMaterials()) {
					var p = m.allocPass("highlight");
					p.culling = None;
					p.depthWrite = false;
					p.depthTest = Always;
				}
			}
		}

		if (objs.length > 0)
			gizmo.moveToObjects(objs);
		gizmo.visible = objs.length > 0;

		if (!flags.has(NoRefreshTree)) {
			treePrefab.setSelection(selection);
		}

		if (!flags.has(NoRecordUndo)) {
			getView().undo.record((isUndo) -> setSelection(isUndo ? oldSelection : selection, NoRecordUndo), false);
		}

		refreshInspector();
	}

	public function hasUnsavedChanges() : Bool {
		return getView()?.undo.hasDataChanges(lastSaveUndo);
	}

	function reload() {
		if (selectedPrefabs.empty()) {
			setPrefab(prefab);
		} else {
			for (prefab => _ in selectedPrefabs) {
				tryMake(prefab);
			}
		}
		hide.Ide.showInfo("Reloaded prefab");
	}

	function save() {
		trySavePrefab(prefab);
	}

	function trySavePrefab(prefab: hrt.prefab.Prefab) {
		var path = prefab.shared.parentPrefab != null ? prefab.shared.parentPrefab.source : prefab.shared.currentPath;

		try {
			var data = prefab.serialize();
			var realPath = hide.Ide.inst.getPath(path);
			var text = hide.Ide.inst.toJSON(data);
			sys.io.File.saveContent(realPath, text);

			hide.App.defer(() -> saveBackup(text, path));
			hide.Ide.showInfo('Saved $path');

			lastSaveUndo = getView().undo.getCurrentUndo();
		} catch(e) {
			hide.Ide.showError('Save failed for $path : $e');
		}
	}

	function saveBackup(content: String, basePath: String) {
		var tmpPath = hide.Ide.inst.resourceDir + "/.tmp/" + basePath;
		var baseName = haxe.io.Path.withoutExtension(tmpPath);
		var tmpDir = haxe.io.Path.directory(tmpPath);

		// Save backup file
		try {
			sys.FileSystem.createDirectory(tmpDir);
			var dateFmt = DateTools.format(Date.now(), "%Y%m%d-%H%M%S");
			sys.io.File.saveContent(baseName + "-backup" + dateFmt + "." + haxe.io.Path.extension(basePath), content);
		}
		catch (e: Dynamic) {
			hide.Ide.showError('Backup save failed for $basePath : $e');
		}

		// Delete old files
		var allTemp = [];
		for( f in try sys.FileSystem.readDirectory(tmpDir) catch( e : Dynamic ) [] ) {
			if(~/-backup[0-9]{8}-[0-9]{6}$/.match(haxe.io.Path.withoutExtension(f))) {
				allTemp.push(f);
			}
		}
		allTemp.sort(Reflect.compare);
		while(allTemp.length > 10) {
			sys.FileSystem.deleteFile(tmpDir + "/" + allTemp.shift());
		}
	}


	function refreshInspector() {
		var prefabs = [for (prefab => _ in selectedPrefabs) prefab];

		inspectorPanel.removeChildElements();

		if (prefabs.length == 0)
			return;

		var commonClass = hrt.tools.ClassUtils.getCommonClassInstance(prefabs, hrt.prefab.Prefab);

		var isMultiEdit = prefabs.length > 1;
		var editPrefab : hrt.prefab.Prefab = if (isMultiEdit) {
			var p = Type.createInstance(commonClass, [null, new hrt.prefab.ContextShared(prefabs[0].shared.currentPath)]);
			p.load(haxe.Json.parse(haxe.Json.stringify(prefabs[0].save())));
			p;
		} else {
			prefabs[0];
		}

		var editContext = new EditContext(this, null);
		var baseRoot = new hide.kit.KitRoot(null, null, editPrefab, editContext);
		@:privateAccess baseRoot.isMultiEdit = isMultiEdit;

		@:privateAccess editContext.saveKey = Type.getClassName(commonClass);
		editContext.root = baseRoot;

		editPrefab.edit2(editContext);
		baseRoot.postEditStep();

		if (isMultiEdit) {
			for (i => prefab in prefabs) {
				var childEditContext = new EditContext(this, editContext);
				@:privateAccess childEditContext.saveKey = Type.getClassName(commonClass);
				var childRoot = new hide.kit.KitRoot(null, null, prefab, childEditContext);
				@:privateAccess childRoot.isMultiEdit = true;
				baseRoot.editedPrefabsProperties.push(childRoot);
				childEditContext.root = childRoot;
				prefab.edit2(childEditContext);
				childRoot.postEditStep();
			}
		}

		baseRoot.make();

		inspectorPanel.addChild(@:privateAccess baseRoot.native);
		@:privateAccess baseRoot.native.get().dom.applyStyle(uiBase.style);
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
			removePrefabInstance(prefab);
			prefab.shared.root2d.remove();
			prefab.shared.root3d.remove();
			interactives.clear();
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

		scene.s3d.renderer?.dispose();
		scene.s3d.renderer = new hide.Renderer.PbrRenderer(env);

		scene.s3d.lightSystem?.dispose();
		scene.s3d.lightSystem = new h3d.scene.pbr.LightSystem();

		var o = new hrt.prefab.rfx.Outline(null, null);
		o.outlineColor = 0xFF6600;
		scene.s3d.renderer.effects.push(o);

		makeGizmos();
		tryMake(prefab);
		makeRenderProps();

		focusObjects([for (i in 0...scene.s3d.numChildren) scene.s3d.getChildAt(i)]);

		trace("=========================");
		trace('Num objects in scene after reload :  ${scene.s3d.flatten().length}');
		trace("\n" + dumpObject(scene.s3d));
		trace("=========================");
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
		removePrefabInstance(prefab);
		if (prefab.parent == null && prefab.shared.parentPrefab == null) {
			@:privateAccess prefab.shared.root2d = prefab.shared.current2d = new h2d.Object(scene.s2d);
			@:privateAccess prefab.shared.root3d = prefab.shared.current3d = new h3d.scene.Object(scene.s3d);
		} else {
			prefab.shared.current2d = prefab.findFirstLocal2d(true);
			prefab.shared.current3d = prefab.findFirstLocal3d(true);
		}

		try {
			prefab.make();
			for (p in prefab.flatten()) {
				makePrefabInteractive(p);
			}
		} catch (e) {
			removePrefabInstance(prefab);

			errorMessage.text = "Error loading prefab : " + e;

			hide.Ide.showError("Error loading prefab " + e);
			return false;
		}

		var fx = Std.downcast(prefab.findFirstLocal3d(), hrt.prefab.fx.FX.FXAnimation);
		if (fx != null) {
			fx.loop = true;
		}

		treePrefab.rebuild();
		setSelection([for (p in selectedPrefabs.keys()) p], NoRecordUndo | NoRefreshTree);

		return true;
	}

	public function makePrefabInteractive(prefab: hrt.prefab.Prefab) {
		var int = prefab.makeInteractive();
		if (int != null) {
			var i3d = Std.downcast(int, h3d.scene.Interactive);
			if (i3d != null) {
				interactives.set(prefab, i3d);
				i3d.cursor = Default;
			}
		}
	}

	public function getAllPrefabsUnder(x: Float, y: Float) : Array<{d: Float, prefab: hrt.prefab.Prefab}> {
		var camera = scene.s3d.camera;
		var ray = camera.rayFromScreen(x, y, Std.int(scene.calculatedWidth), Std.int(scene.calculatedHeight));

		var selectables = getAllSelectable(true, true);

		var hits : Array<{d: Float, prefab: hrt.prefab.Prefab}> = [];
		var order2d : Map<hrt.prefab.Prefab, Int> = null;

		var tmpRay = new h3d.col.Ray();

		for (selectable in selectables) {
			var int3d = interactives.get(selectable);
			if (int3d != null) {
				var localRay = tmpRay;
				localRay.load(ray);
				localRay.transform(int3d.getAbsPos().getInverse());

				var distance = int3d.shape?.rayIntersection(localRay, false);
				if (distance < 0)
					continue;

				var distance = int3d.preciseShape?.rayIntersection(localRay, true) ?? distance;

				if (distance > 0) {
					hits.push({d: distance, prefab: selectable});
				}
			}
		}

		hits.sort((a,b) -> Reflect.compare(a.d, b.d));

		return hits;
	}

	public function getAllSelectable(include3d: Bool, include2d: Bool) : Array<hrt.prefab.Prefab> {
		var ret = [];

		function rec(prefab: hrt.prefab.Prefab) {
			if (prefab == null)
				return;

			var o3d = prefab.to(hrt.prefab.Object3D);
			var o2d = prefab.to(hrt.prefab.Object2D);

			var visible = if (o3d != null) {
				o3d.visible;
			} else if (o2d != null) {
				o2d.visible;
			} else true;

			if (interactives.get(prefab) != null) ret.push(prefab);

			// if (!visible || isHidden(prefab))
			// 	return;
			// if (!isLocked(prefab)) {
			// 	if (interactives.get(prefab) != null) ret.push(prefab);
			// 	//else if (interactives2d.get(prefab) != null) ret.push(prefab);
			// }

			for (child in prefab.children) {
				rec(child);
			}

			var ref = Std.downcast(prefab, hrt.prefab.Reference);
			if (ref != null && ref.editMode != None) {
				rec(ref.refInstance);
			}
		}

		rec(prefab);

		return ret;
	}

	/** Remove all the prefab instantiated objects from the scene**/
	public function removePrefabInstance(prefab: hrt.prefab.Prefab) {
		if (prefab == null)
			return;
		prefab.editorRemoveObjects();
		for (child in prefab.flatten()) {
			interactives.get(child)?.remove();
			interactives.remove(child);
		}
		if (prefab.parent == null && prefab.shared.parentPrefab == null) {
			prefab.shared.root3d.remove();
			prefab.shared.root2d.remove();
		}
	}

	static function dumpObject(obj: h3d.scene.Object, pad: String = "") : String {
		var str = "";
		str += '$pad${obj.name}[${Type.getClassName(Type.getClass(obj))}]\n';
		var nextPad = pad + "\t";
		for (i in 0...obj.numChildren) {
			str += dumpObject(obj.getChildAt(i), nextPad);
		}
		return str;
	}

	public function makeRenderProps() {
		var paths = getRenderPropsPaths();
		for (path in paths) {
			removePrefabInstance(renderProps);

			renderProps = hxd.res.Loader.currentInstance.load(path.value).toPrefab().load().clone();
			if (tryMake(renderProps))
				break;
		}
	}

	public function makeGizmos() {
		grid?.remove();
		gizmo?.remove();
		viewportAxis?.remove();

		viewportAxis = new hrt.tools.ViewportAxis(scene.s3d.camera, cameraController, scene.s2d);

		grid = new hrt.tools.Grid(scene.s3d);
		gizmo = new hrt.tools.Gizmo(scene.s3d);
		gizmo.visible = false;
		gizmo.isLocalTransform = true;
		registerCommand(gizmoSwitchModeCommand, View, gizmo.switchMode);
		registerCommand(gizmoTranslateCommand, View, gizmo.translationMode);
		registerCommand(gizmoRotateCommand, View, gizmo.rotationMode);
		registerCommand(gizmoScaleCommand, View, gizmo.scalingMode);

		var initialTransform = new h3d.Matrix();
		var obj3ds : Array<hrt.prefab.Object3D> = [];
		gizmo.onStartMove = (handle : hrt.tools.Gizmo.Handle) -> {
			obj3ds = [];
			for (p in selectedPrefabs.keys()) {
				var o = Std.downcast(p, hrt.prefab.Object3D);
				if (o == null)
					continue;
				obj3ds.push(o);
			}
			if (obj3ds.length > 0)
				initialTransform.load(obj3ds[0].getTransform());
		};

		gizmo.onMove = (offsetPosition, offsetRotation, offsetScale) -> {
			if (obj3ds.length <= 0)
				return;

			var obj3d = obj3ds[0];
			if (offsetRotation != null) {
				var euler = offsetRotation.toMatrix().getEulerAngles();
				obj3d.rotationX = hxd.Math.radToDeg(initialTransform.getEulerAngles().x) + hxd.Math.radToDeg(euler.x);
				obj3d.rotationY = hxd.Math.radToDeg(initialTransform.getEulerAngles().y) + hxd.Math.radToDeg(euler.y);
				obj3d.rotationZ = hxd.Math.radToDeg(initialTransform.getEulerAngles().z) + hxd.Math.radToDeg(euler.z);
			}

			if (offsetPosition != null) {
				obj3d.x = initialTransform.getPosition().x + offsetPosition.x;
				obj3d.y = initialTransform.getPosition().y + offsetPosition.y;
				obj3d.z = initialTransform.getPosition().z + offsetPosition.z;
			}

			if (offsetScale != null) {
				var transform = initialTransform.clone();
				transform.prependScale(offsetScale.x, offsetScale.y, offsetScale.z);
				obj3d.scaleX = transform.getScale().x;
				obj3d.scaleY = transform.getScale().y;
				obj3d.scaleZ = transform.getScale().z;
			}

			// if (!gizmo.isLocalTransform)
			// 	transform.multiplied(initialTransform.getInverse());

			obj3d.applyTransform();
		};

		gizmo.onFinishMove = () -> {
			var prevTransforms = [];
			var newTransforms = [];
			var modifiedObj3ds = obj3ds.copy();
			for (idx => o in modifiedObj3ds) {
				prevTransforms.push(initialTransform.clone());
				newTransforms.push(o.getTransform());
			}

			getView().undo.record((isUndo) -> {
				var objs = [];
				for (idx => o in modifiedObj3ds) {
					o.setTransform(isUndo ? prevTransforms[idx] : newTransforms[idx]);
					o.applyTransform();
					if (o.local3d != null)
						objs.push(o.local3d);
				}
				gizmo.moveToObjects(objs);
			}, true);
		};
	}

	function onSceneEvents(e: hxd.Event) : Void {
		// debugGraph.clear();
		// debugGraph.setColor(0xFF00FF, 1.0);
		// debugGraph.lineStyle(1, 0xFF00FF);
		// debugGraph.drawCircle(e.relX, e.relY, 10);

		switch (e.kind) {
			case EMove:
				onSceneMove(e);
			case EPush:
				onScenePush(e);
			default:
		}
	}

	function onScenePush(e: hxd.Event) : Void {
		if (e.button == 0) {
			var mouseX = e.relX - scene.absX;
			var mouseX = e.relY - scene.absY;

			lastPushX = e.relX;
			lastPushY = e.relY;

			var prefabs = getAllPrefabsUnder(e.relX, e.relY);

			var newPrefab : hrt.prefab.Prefab = null;

			if (prefabs.length > 0) {

				newPrefab = prefabs[0].prefab;

				if (!movedSinceLastPush) {
					// select next prefab in the selection stack
					for (i => under in prefabs) {
						if (selectedPrefabs.get(under.prefab)) {
							newPrefab = prefabs[(i + 1) % prefabs.length].prefab;
							break;
						}
					}
				}
			}

			var newSelection : Array<hrt.prefab.Prefab> = [];
			if (hxd.Key.isDown(hxd.Key.CTRL)) {
				newSelection = [for (p in selectedPrefabs.keys()) p];
			}

			if (newPrefab != null)
				newSelection.push(newPrefab);

			setSelection(newSelection, SelectionFlags.ofInt(0));

			e.propagate = false;
			movedSinceLastPush = false;
		}
	}

	function onSceneMove(e: hxd.Event) : Void {
		if (hxd.Math.distance(lastPushX - e.relX, lastPushY - e.relY) > 5.0) {
			movedSinceLastPush = true;
		}
	}
}

@:access(hrt.ui.HuiPrefabEditor)
class EditContext extends hrt.prefab.EditContext2 {
	var editor : HuiPrefabEditor;
	var saveKey: String;

	public function new(editor: HuiPrefabEditor, parent: hrt.prefab.EditContext2) {
		super(parent);
		this.editor = editor;
	}

	public function rebuildInspector() : Void {
		editor.refreshInspector();
	};

	public function rebuildPrefabImpl(prefab: hrt.prefab.Prefab) : Void {
		editor.tryMake(prefab);
	}

	/**
		Request that the scene tree widget should be rebuild for the given prefab
	**/
	public function rebuildTreeImpl() : Void {
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

	public function listModelAnimations(path: String) : Array<String> {
		return hide.Ide.inst.listAnims(path);
	}


	public function quickError(message: String) : Void {
		hide.Ide.showError(message);
	}

	public function screenToGround(sx: Float, sy: Float, ?paintOn : hrt.prefab.Prefab, ignoreTerrain: Bool = false) : h3d.Vector {
		throw "implement";
	}

	public function recordUndo(callback: (isUndo: Bool) -> Void ) : Void {
		editor.findParent(HuiView).undo.record(callback, true);
	}

	function saveSetting(category: hrt.prefab.EditContext2.SettingCategory, key: String, value: Dynamic) : Void {
		if (parent != null)
			return;

		if (value == null) {
			hide.Ide.inst.deleteLocalStorage(getSaveKey(category, key));
			return;
		}
		hide.Ide.inst.saveLocalStorage(getSaveKey(category, key), value);
	}

	function getSetting(category: hrt.prefab.EditContext2.SettingCategory, key: String) : Null<Dynamic> {
		var v = hide.Ide.inst.getLocalStorage(getSaveKey(category, key));
		if (v == null)
			return null;
		return v;
	}

	function getRootObjects3d() : Array<h3d.scene.Object> {
		throw "implement";
	}

	function getSaveKey(category: hrt.prefab.EditContext2.SettingCategory, key: String) {
		var mid = switch(category) {
			case Global:
				"global";
			case SameKind:
				saveKey;
		};

		return 'inspector/$mid/$key';
	}
}

#end
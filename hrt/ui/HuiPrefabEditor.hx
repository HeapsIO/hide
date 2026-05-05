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

	static public var gizmoSwitchModeCommand = new hrt.ui.HuiCommands.HuiCommand("Gizmo Switch Mode", {key: hxd.Key.SPACE});
	static public var gizmoTranslateCommand = new hrt.ui.HuiCommands.HuiCommand("Gizmo Translate", {key: hxd.Key.W});
	static public var gizmoRotateCommand = new hrt.ui.HuiCommands.HuiCommand("Gizmo Rotate", {key: hxd.Key.E});
	static public var gizmoScaleCommand = new hrt.ui.HuiCommands.HuiCommand("Gizmo Scale", {key: hxd.Key.R});
	static public var focusCommand = new hrt.ui.HuiCommands.HuiCommand("Focus Selection", {key: hxd.Key.F});


	public var gizmoShouldSnap(default, set) : Bool = true;
	public function set_gizmoShouldSnap(v : Bool) {
		hide.Ide.inst.currentConfig.set(hide.view.Prefab.GIZMO_SNAP_CONFIG_KEY, v);
		return gizmoShouldSnap = v;
	}
	public var gizmoSnapStep(default, set) : Float = 1.0;
	public function set_gizmoSnapStep(v : Float) {
		hide.Ide.inst.currentConfig.set(hide.view.Prefab.GIZMO_SNAP_STEP_CONFIG_KEY, v);
		return gizmoSnapStep = v;
	}
	public var gizmoForceSnapOnGrid(default, set) : Bool = true;
	public function set_gizmoForceSnapOnGrid(v : Bool) {
		hide.Ide.inst.currentConfig.set(hide.view.Prefab.GIZMO_SNAP_GRID_CONFIG_KEY, v);
		return gizmoForceSnapOnGrid = v;
	}

	var rethrowMakeErrors: Bool = false;

	var prefab: hrt.prefab.Prefab;
	var renderProps: hrt.prefab.Prefab;

	var errorMessage : h2d.Text;
	var cameraController : h3d.scene.CameraController;
	var treePrefab: hrt.ui.HuiTree<hrt.prefab.Prefab>;
	var interactives: Map<hrt.prefab.Prefab, h3d.scene.Interactive> = [];
	var lastSaveUndo: Any = null;

	var selectedPrefabs: Map<hrt.prefab.Prefab, Bool> = [];

	var config : hide.Config;

	var lastPushX : Float = -100;
	var lastPushY : Float = -100;
	var movedSinceLastPush : Bool = false;

	var lastFocusObjects: Array<h3d.scene.Object> = [];

	var inspectorRoot : hide.kit.KitRoot;
	var disableSceneRender : Bool = false;

	// Gizmos and guides
	var grid : hrt.tools.Grid = null;
	var viewportAxis : hrt.tools.ViewportAxis = null;
	var gizmo : hrt.tools.Gizmo = null;
	var outline : hrt.prefab.rfx.Outline;

	// Debugs
	var debugGraph: h2d.Graphics;
	var rootDebugCollider : h3d.scene.Object = null;

	override function new(?parent) {
		super(parent);
		initComponent();

		errorMessage = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);

		var ctrlClass = h3d.scene.CameraController.getCameraControllersClass()[hide.Ide.inst.currentConfig.get(hide.view.Prefab.CAM_CTRL_CONFIG_KEY, 0)];
		cameraController = Type.createInstance(ctrlClass, []);
		scene.s3d.addChild(cameraController);

		treePrefab = new hrt.ui.HuiTree<hrt.prefab.Prefab>(panelTree);
		treePrefab.getItemChildren = treePrefabGetItemChildren;
		treePrefab.getItemName = (p: hrt.prefab.Prefab) -> p.name;
		treePrefab.onUserSelectionChanged = () -> {
			setSelection(treePrefab.getSelectedItems(), NoRefreshTree);
		}
		treePrefab.onItemContextMenu = contextMenu;
		treePrefab.onItemDoubleClick = (_, prefab) -> {
			var obj = prefab.findFirstLocal3d();
			if (obj != null)
				focusObjects([obj]);
		};

		treePrefab.dragAndDropInterface = {
			onDragStart: function(p: hrt.prefab.Prefab): Void {
				startDrag("prefabs", getSelectionOrdered());
			},
			getItemDropFlags: function(target: hrt.prefab.Prefab, op: HuiDragOp) : hrt.ui.HuiTree.DropFlags {
				if (op.type == "prefabs") {
					var prefabs : Array<hrt.prefab.Prefab> = cast op.data;
					prefabs = prefabs.copy();
					sanitizeReparent(target, prefabs);
					if (prefabs.length == 0) {
						return hrt.ui.HuiTree.DropFlags.ofInt(0);
					}

					return Reorder | Reparent;
				}
				return  hrt.ui.HuiTree.DropFlags.ofInt(0);
			},
			onDrop: function(target: hrt.prefab.Prefab, operation: hrt.ui.HuiTree.DropOperation, op: HuiDragOp) : Void {
				if (op.type == "prefabs") {
					var prefabs : Array<hrt.prefab.Prefab> = cast op.data;
					prefabs = prefabs.copy();
					sanitizeReparent(target, prefabs);
					if (prefabs.length == 0) {
						return;
					}
					var reparentTo = target;
					var index = 0;
					switch(operation) {
						case Before:
							reparentTo = target.parent;
							index = reparentTo.children.indexOf(target);
						case After:
							reparentTo = target.parent;
							index = reparentTo.children.indexOf(target) + 1;
						case Inside:
					}
					trace(operation, target, reparentTo, index);
					getView().undo.run(actionReparentPrefabs(prefabs, reparentTo, index), true);
				}
			}
		}

		scene.s3d.addEventListener(onSceneEvents);

		registerCommand(hrt.ui.HuiCommands.HuiDebugCommands.debugReload, View, reload);
		registerCommand(hrt.ui.HuiCommands.rename, View, () -> {
			var lastSelection = getSelectionOrdered()[0];
			if (lastSelection != null) {
				renamePrefab(lastSelection);
			}
		});

		registerCommand(hrt.ui.HuiCommands.cut, View, () -> getView().undo.run(actionCutToClipboard(), true));
		registerCommand(hrt.ui.HuiCommands.copy, View, () -> copySelectionToClipboard());
		registerCommand(hrt.ui.HuiCommands.paste, View, () -> getView().undo.run(actionPasteFromClipboard(), true));

		registerCommand(hrt.ui.HuiCommands.delete, View, () -> getView().undo.run(actionRemovePrefabs([for (p => _ in selectedPrefabs) p]), true));
		registerCommand(focusCommand, View, () -> focusSelection());

		debugGraph = new h2d.Graphics(scene.s2d);

		makeGizmos();
	}

	/**
		Returns the list of prefabs that don't have a parent in the list
	**/
	function getRoots(prefabs: Array<hrt.prefab.Prefab>) : Array<hrt.prefab.Prefab> {
		var newList = [];
		for (prefab in prefabs) {
			if (prefab.findParent((p) -> prefabs.contains(p)) != null) {
				continue;
			}
			newList.push(prefab);
		}
		return newList;
	}

	function sanitizeReparent(target: hrt.prefab.Prefab, elements: Array<hrt.prefab.Prefab>) {
		// Avoid moving target onto itelf
		for (prefab in elements.copy()) {
			if (target.findParent((p) -> p == prefab, true) != null) {
				elements.remove(prefab);
			}
		}
	}

	function getSelectionOrdered() : Array<hrt.prefab.Prefab> {
		var selection : Array<hrt.prefab.Prefab> = [];
		var flatten = prefab.flatten();
		for (p in flatten) {
			if (selectedPrefabs.get(p) == true) {
				selection.push(p);
			}
		}

		return selection;
	}

	override function sync(ctx : h2d.RenderContext) {
		super.sync(ctx);
		gizmo.update(ctx.elapsedTime);
	}

	function setSelection(selection: Array<hrt.prefab.Prefab>, flags: SelectionFlags, force: Bool = false) {
		var oldSelection = [for (p => _ in selectedPrefabs) p];
		if (selection.length == oldSelection.length && !force) {
			var same = true;
			for (p in selection) {
				if (selectedPrefabs.get(p) == null) {
					same = false;
					break;
				}
			}
			if (same) {

				return;
			}
		}

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
			@:privateAccess treePrefab.forceRefreshTree();
			treePrefab.setSelection(selection);
			for (item in selection) {
				treePrefab.revealItem(item);
			}
		}

		if (!flags.has(NoRecordUndo)) {
			getView().undo.record((isUndo) -> setSelection(isUndo ? oldSelection : selection, NoRecordUndo), false);
		}

		refreshInspector();
	}

	function getSelectedObjects() : Array<h3d.scene.Object> {
		var objs = [];
		var selection = selectedPrefabs.keys();
		for (prefab in selection) {
			selectedPrefabs.set(prefab, true);
			var obj3d = Std.downcast(prefab, hrt.prefab.Object3D);
			if (obj3d != null && obj3d.local3d != null) {
				objs.push(obj3d.local3d);
			}
		}

		return objs;
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
		inspectorRoot = null;

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
		inspectorRoot = new hide.kit.KitRoot(null, null, editPrefab, editContext);
		@:privateAccess inspectorRoot.isMultiEdit = isMultiEdit;

		@:privateAccess editContext.saveKey = Type.getClassName(commonClass);
		editContext.root = inspectorRoot;

		editPrefab.edit2(editContext);
		inspectorRoot.postEditStep();

		if (isMultiEdit) {
			for (i => prefab in prefabs) {
				var childEditContext = new EditContext(this, editContext);
				@:privateAccess childEditContext.saveKey = Type.getClassName(commonClass);
				var childRoot = new hide.kit.KitRoot(null, null, prefab, childEditContext);
				@:privateAccess childRoot.isMultiEdit = true;
				inspectorRoot.editedPrefabsProperties.push(childRoot);
				childEditContext.root = childRoot;
				prefab.edit2(childEditContext);
				childRoot.postEditStep();
			}
		}

		inspectorRoot.make();

		inspectorPanel.addChild(@:privateAccess inspectorRoot.native);
		if (uiBase != null) {
			@:privateAccess inspectorRoot.native.get().dom.applyStyle(uiBase.style);
		}
	}

	function contextMenu(target: hrt.prefab.Prefab) {
		if (target == null) {
			target = prefab;
		}

		var entries: Array<hrt.ui.HuiMenu.MenuItem> = [];

		entries.push({label: "Add Child Prefab", menu: createPrefabMenu((cl) -> getView().undo.run(actionCreatePrefab(target, target.children.length, cl), true))});
		entries.push(HuiMenu.itemFromCommand(HuiCommands.rename, this));

		entries.push({isSeparator: true});
		entries.push(HuiMenu.itemFromCommand(HuiCommands.cut, this));
		entries.push(HuiMenu.itemFromCommand(HuiCommands.copy, this));
		entries.push(HuiMenu.itemFromCommand(HuiCommands.paste, this));

		entries.push(HuiMenu.itemFromCommand(HuiCommands.delete, this));

		entries.push({isSeparator: true});

		entries.push(HuiMenu.itemFromCommand(focusCommand, this));

		uiBase.contextMenu(entries);
	}

	function actionCutToClipboard() : hrt.tools.Undo.Action {
		copySelectionToClipboard();
		return actionRemovePrefabs(getSelectionOrdered());
	}

	function copySelectionToClipboard() {
		var selection = getSelectionOrdered();
		selection = getRoots(selection);
		hxd.System.setClipboardText(hide.Ide.inst.toJSON([for (p in selection) p.serialize()]));
	}

	function actionPasteFromClipboard() : hrt.tools.Undo.Action {

		var content = hxd.System.getClipboardText();
		var json = try haxe.Json.parse(content) catch(e) return null;

		if (!(json is Array))
			return null;

		var json : Array<Dynamic> = json;

		var makePrefabs: Array<hrt.tools.Undo.Action> = [];
		var selectPrefabs: Array<hrt.prefab.Prefab> = [];
		var selection = getSelectionOrdered();
		if (selection.length == 0) {
			selection.push(prefab);
		}
		for (parent in selection) {
			var createdPrefabs : Array<hrt.prefab.Prefab> = [];
			for (data in json) {
				if (!Reflect.hasField(data, "type"))
					continue;

				try {
					var prefab = hrt.prefab.Prefab.createFromDynamic(data, null);
					createdPrefabs.push(prefab);
					selectPrefabs.push(prefab);
				} catch (e) {
					continue;
				}
			}

			makePrefabs.push(actionReparentPrefabs(createdPrefabs, parent, parent.children.length));
		}

		var selection = actionMakeSelection(selectPrefabs);

		return (isUndo) -> {
			for (makePrefab in makePrefabs){
				makePrefab(isUndo);
			}
			selection(isUndo);
		};
	}


	function renamePrefab(target: hrt.prefab.Prefab) {
		treePrefab.rename(target, (newName: String) -> {
			getView().undo.run(actionRenamePrefab(target, newName), true);
		});
	}

	function actionRenamePrefab(target: hrt.prefab.Prefab, name: String) : hrt.tools.Undo.Action {
		var oldName = target.name;

		return (isUndo) -> {
			target.name = isUndo ? oldName : name;
			target.updateInstance("name");
			treePrefab.rebuild(target);
		}
	}

	function actionCreatePrefab(parent: hrt.prefab.Prefab, index: Int, cl: Class<hrt.prefab.Prefab>) : hrt.tools.Undo.Action {
		var newPrefab = Type.createInstance(cl, []);
		newPrefab.name = Type.getClassName(cl).split(".").pop();

		var reparent = actionReparentPrefab(newPrefab, parent, index);
		var select = actionMakeSelection([newPrefab]);

		return (isUndo) -> {
			reparent(isUndo);
			select(isUndo);
		};
	}

	function actionRemovePrefabs(prefabs: Array<hrt.prefab.Prefab>) : hrt.tools.Undo.Action {

		var reparents = [for (prefab in prefabs) actionReparentPrefab(prefab, null, 0)];
		var select = actionMakeSelection([]);

		return (isUndo) -> {
			select(isUndo);
			for (reparent in reparents)
				reparent(isUndo);
		};
	}

	function actionReparentPrefabs(prefabs: Array<hrt.prefab.Prefab>, newParent: hrt.prefab.Prefab, index: Int) : hrt.tools.Undo.Action {

		var reparents = [];
		var i = 0;
		for (prefab in prefabs) {
			reparents.push(actionReparentPrefab(prefab, newParent, index + i));

			if (prefab.parent == newParent && newParent.children.indexOf(prefab) < index) {
				// fix offset
				i--;
			}
			i++;
		}

		return (isUndo) -> {
			for (reparent in reparents)
				reparent(isUndo);
		};

	}

	function actionMakeSelection(newSelection: Array<hrt.prefab.Prefab>) : hrt.tools.Undo.Action {
		var oldSelection = [for (p => _ in selectedPrefabs) p];

		return (isUndo) -> {
			setSelection(isUndo ? oldSelection : newSelection, NoRecordUndo);
		}
	}

	static public function worldMat(?obj: h3d.scene.Object, ?elt: hrt.prefab.Prefab) {
		var obj = obj ?? elt?.findFirstLocal3d(true);
		if(obj != null) {
			if(obj.defaultTransform != null) {
				var m = obj.defaultTransform.clone();
				m.invert();
				m.multiply(m, obj.getAbsPos());
				return m;
			}
			else {
				return obj.getAbsPos().clone();
			}
		}
		return h3d.Matrix.I();
	}

	function actionReparentPrefab(prefab: hrt.prefab.Prefab, parent: hrt.prefab.Prefab, index: Int) : hrt.tools.Undo.Action {
		var oldParent = prefab.parent;
		var oldIndex = -1;
		var currentWorldTransform = worldMat(prefab);
		var oldTransform = prefab.to(hrt.prefab.Object3D)?.saveTransform();
		var newTransform = oldTransform;
		if (oldParent != null) {
			oldIndex = oldParent.children.indexOf(prefab);
			if (oldParent == parent && oldIndex > index)
				oldIndex += 1;
		}

		if (parent != null && oldTransform != null)
		{
			var parentTransform = worldMat(parent);
			parentTransform.invert();
			var mat = currentWorldTransform;
			mat.multiply(mat, parentTransform);
			newTransform = hrt.prefab.Object3D.makeTransform(mat);
		}

		return (isUndo: Bool) -> {
			var newParent = isUndo ? oldParent : parent;
			var newIndex = isUndo ? oldIndex : index;
			var transform = isUndo ? oldTransform : newTransform;

			removePrefabInstance(prefab);

			if (newParent == null) {
				prefab.remove();
			} else {
				newParent.addChildAt(prefab, newIndex);
				if (transform != null) {
					prefab.to(hrt.prefab.Object3D)?.loadTransform(transform);
				}
				tryMakeChildren(newParent);
			}

			if (newParent != null)
				treePrefab.toggleItemOpen(newParent, true);
			rebuildPrefabTree(isUndo ? parent : oldParent);
			rebuildPrefabTree(newParent);
			updateDebugOverlayVisibility();
			checkRemakeRenderProps(prefab);
		};
	}

	function rebuildPrefabTree(prefab: hrt.prefab.Prefab) {
		if (prefab == null)
			return;
		if (prefab == this.prefab)
			treePrefab.rebuild(null);
		else
			treePrefab.rebuild(prefab);
	}

	function createPrefabMenu(click: (cl: Class<hrt.prefab.Prefab>) -> Void) : Array<hrt.ui.HuiMenu.MenuItem> {
		var lines: Array<hrt.ui.HuiMenu.MenuItem> = [];

		var submenus : Map<String, Array<hrt.ui.HuiMenu.MenuItem>> = [];

		for (prefab in hrt.prefab.Prefab.registry) {
			var category = getPrefabCategoryLabel(prefab.prefabClass);
			var label = Type.getClassName(prefab.prefabClass).split(".").pop();
			var submenu = hrt.tools.MapUtils.getOrPut(submenus, category, []);
			submenu.push({label: label, click: click.bind(prefab.prefabClass)});
		}

		for (category => submenu in submenus) {
			lines.sort((a,b) -> Reflect.compare(a.label, b.label));
			lines.push({label: category, menu: submenu});
		}

		lines.sort((a,b) -> Reflect.compare(a.label, b.label));

		return lines;
	}

	function getPrefabCategoryLabel(cl: Class<hrt.prefab.Prefab>) : String {
		static var categories : Array<{label: String, cl: Array<Class<hrt.prefab.Prefab>>}> = [
			{label: "3D", cl: [hrt.prefab.Object3D]},
			{label: "2D", cl: [hrt.prefab.Object2D]},
			{label: "RFX", cl: [hrt.prefab.rfx.RendererFX]},
			{label: "Spawn", cl: [hrt.prefab.fx.gpuemitter.SpawnShader]},
			{label: "Simulation", cl: [hrt.prefab.fx.gpuemitter.SimulationShader]},
		];

		var currentClass = cl;
		while (currentClass != null) {
			for (category in categories) {
				if (category.cl.contains(currentClass))
					return category.label;
			}

			currentClass = cast Type.getSuperClass(currentClass);
		}
		return "Unknown";
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
		if (!newPrefab.shared.isInstance) {
			throw "prefab must be an instance prefab to be editable";
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

		outline = new hrt.prefab.rfx.Outline(null, null);
		outline.outlineColor = 0xFF6600;
		scene.s3d.renderer.effects.push(outline);

		tryMake(prefab);
		makeRenderProps();

		hide.App.defer(resetCamera);

		updateDebugOverlayVisibility();
	}

	function resetCamera() {
		cameraController.set(20.0);
		var objs = prefab.shared.root3d.findAll((f) -> f);
		focusObjects(objs);
		lastFocusObjects = [];
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
		for (o in objs) {
			if (!lastFocusObjects.contains(o)) {
				focusChanged = true;
				break;
			}
		}

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
		lastFocusObjects = objs;
	}

	public function focusSelection() {
		var objects = [];
		for (prefab => _ in selectedPrefabs) {
			var object3d = prefab.findFirstLocal3d();
			if (object3d != null)
				objects.push(object3d);
		}
		if (objects.length == 0) {
			resetCamera();
		} else {
			focusObjects(objects);
		}
	}


	/**
		Try to make the given prefab. If the prefab is already instantiated, tries do cleanup it first.
		It should be an error to call this on a prefab that is not the root without also rebuilding this prefab sibiling,
		as it will change the ordering of the heaps objects in the scene (which can cause subtle differences, espetially with 2d scenes where the order really matters).
		For that you should call tryMakeChildren(prefab.parent) instead.
	**/
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
			if (prefab.parent != null) {
				prefab.parent.makeChild(prefab);
			} else {
				prefab.make();
			}
			for (p in prefab.flatten()) {
				makePrefabInteractive(p);
			}
		} catch (e) {
			removePrefabInstance(prefab);

			if (rethrowMakeErrors) {
				hl.Api.rethrow(e);
			} else {
				errorMessage.text = "Error loading prefab : " + e;
				hide.Ide.showError("Error loading prefab " + e);
				return false;
			}
		}

		var fx = Std.downcast(prefab.findFirstLocal3d(), hrt.prefab.fx.FX.FXAnimation);
		if (fx != null) {
			fx.loop = true;
		}

		treePrefab.rebuild();

		return true;
	}

	public function tryMakeChildren(prefab: hrt.prefab.Prefab) : Void {
		for (child in prefab.children) {
			removePrefabInstance(child);
		}

		removePrefabInteractives(prefab);

		for (child in prefab.children) {
			tryMake(child);
		}

		makePrefabInteractive(prefab);
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
			removePrefabInteractives(child);
		}
		if (prefab.parent == null && prefab.shared.parentPrefab == null) {
			prefab.shared.root3d.remove();
			prefab.shared.root2d.remove();
		}
	}

	public function removePrefabInteractives(prefab: hrt.prefab.Prefab) {
		interactives.get(prefab)?.remove();
		interactives.remove(prefab);
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


	public function checkRemakeRenderProps(changedPrefab: hrt.prefab.Prefab = null) : Bool {
		if (changedPrefab != null) {
			if (changedPrefab.findParent(hrt.prefab.RenderProps) == renderProps) {
				makeRenderProps();
				return true;
			}
		}
		if (prefab.find(hrt.prefab.RenderProps) != renderProps) {
			makeRenderProps();
			return true;
		}
		return false;
	}

	public function makeRenderProps() {

		var paths = getRenderPropsPaths();

		var candidates: Array<hrt.prefab.Prefab> = [];

		var prefabRenderProp = prefab.find(hrt.prefab.RenderProps);
		if (prefabRenderProp != null)
			candidates.push(prefabRenderProp);

		for (path in paths) {
			hxd.res.Loader.currentInstance.load(path.value).toPrefab().load();
		}

		removePrefabInstance(renderProps);
		renderProps = null;

		for (candidate in candidates) {
			renderProps = candidate;
			if (tryMake(renderProps)) {
				var trueRenderProps = renderProps.find(hrt.prefab.RenderProps);
				if (trueRenderProps == null)
					throw 'Render props ${renderProps.shared.prefabSource} does not contains a render props prefab';
				trueRenderProps.applyProps(scene.s3d.renderer);
				break;
			}
			removePrefabInstance(renderProps);
			renderProps = null;
		}

	}

	public function updateRenderProps() {
		if (!checkRemakeRenderProps()) {
			var trueRenderProps = renderProps.find(hrt.prefab.RenderProps);
			if (trueRenderProps == null)
				throw 'Render props ${renderProps.shared.prefabSource} does not contains a render props prefab';
			trueRenderProps.applyProps(scene.s3d.renderer);
		}
	}


	public function makeGizmos() {
		this.gizmoShouldSnap = hide.Ide.inst.currentConfig.get(hide.view.Prefab.GIZMO_SNAP_CONFIG_KEY, true);
		this.gizmoSnapStep = hide.Ide.inst.currentConfig.get(hide.view.Prefab.GIZMO_SNAP_STEP_CONFIG_KEY, 1.0);
		this.gizmoForceSnapOnGrid = hide.Ide.inst.currentConfig.get(hide.view.Prefab.GIZMO_SNAP_GRID_CONFIG_KEY, true);

		grid?.remove();
		gizmo?.remove();
		viewportAxis?.remove();

		viewportAxis = new hrt.tools.ViewportAxis(scene.s3d.camera, cameraController, scene.s2d);

		grid = new hrt.tools.Grid(scene.s3d);
		grid.lineSpacing = this.gizmoSnapStep;
		gizmo = new hrt.tools.Gizmo(scene.s3d);
		gizmo.visible = false;
		registerCommand(gizmoSwitchModeCommand, View, gizmo.switchMode);
		registerCommand(gizmoTranslateCommand, View, gizmo.translationMode);
		registerCommand(gizmoRotateCommand, View, gizmo.rotationMode);
		registerCommand(gizmoScaleCommand, View, gizmo.scalingMode);

		var initialTransform = new h3d.Matrix();
		var initialAbs = new h3d.Matrix();
		var obj3ds : Array<hrt.prefab.Object3D> = [];
		gizmo.shouldSnap = () -> { return this.gizmoShouldSnap; };
		gizmo.snap = (v: Float, mode: hrt.tools.Gizmo.EditMode) -> {
			if ((!gizmo.shouldSnap() && !hxd.Key.isDown(hxd.Key.CTRL)) || mode.match(hrt.tools.Gizmo.EditMode.Rotation))
				return v;
			v = hxd.Math.round(v / this.gizmoSnapStep) * this.gizmoSnapStep;
			if (!gizmoForceSnapOnGrid)
				return v;
			return hxd.Math.round(v / this.grid.lineSpacing) * this.grid.lineSpacing;
		};
		gizmo.onStartMove = (handle : hrt.tools.Gizmo.Handle) -> {
			obj3ds = [];
			for (p in selectedPrefabs.keys()) {
				var o = Std.downcast(p, hrt.prefab.Object3D);
				if (o == null)
					continue;
				obj3ds.push(o);
			}
			if (obj3ds.length > 0) {
				initialTransform.load(obj3ds[0].getTransform());
				initialAbs.load(obj3ds[0].getAbsPos(true));
			}
		};

		gizmo.onMove = (offsetPosition, offsetRotation, offsetScale) -> {
			if (obj3ds.length <= 0)
				return;

			var obj3d = obj3ds[0];
			var parent3d = Std.downcast(obj3d.parent, hrt.prefab.Object3D);
			var parentAbs = parent3d != null ? parent3d.getAbsPos(true) : h3d.Matrix.I();
			var parentInv = parentAbs.getInverse();

			var trs = new h3d.Matrix();
			trs.identity();

			if (offsetRotation != null) {
				offsetRotation.toMatrix(trs);
				var t = initialAbs.getPosition();
				trs.prependTranslation(-t.x, -t.y, -t.z);
				trs.translate(t.x, t.y, t.z);
			}

			if (offsetPosition != null)
				trs.translate(offsetPosition.x, offsetPosition.y, offsetPosition.z);

			trs.multiply(initialAbs, trs);

			if (gizmo.shouldSnap() && gizmoForceSnapOnGrid) {
				var p = trs.getPosition();
				p.x = hxd.Math.round(p.x / grid.lineSpacing) * grid.lineSpacing;
				p.y = hxd.Math.round(p.y / grid.lineSpacing) * grid.lineSpacing;
				p.z = hxd.Math.round(p.z / grid.lineSpacing) * grid.lineSpacing;
				trs.setPosition(p);
				gizmo.setPosition(p.x, p.y, p.z);
			}

			trs.multiply(trs, parentInv);

			if (offsetScale != null)
				trs.prependScale(offsetScale.x, offsetScale.y, offsetScale.z);

			obj3d.setTransform(trs);
			obj3d.applyTransform();

			inspectorRoot?.refreshFields();
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

	public function gizmoSnap(v: Float, mode: hrt.tools.Gizmo.EditMode) {
		return hxd.Math.round(v / this.gizmoSnapStep) * this.gizmoSnapStep;
	}


	public function updateDebugOverlayVisibility() {
		var visibility = hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_OVERLAY_CONFIG_KEY, true);

		grid.visible = visibility && hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_GRID_CONFIG_KEY, true);
		gizmo.setVisible(visibility && hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_GIZMO_CONFIG_KEY, true));
		setJointsDebugVisibility(visibility && hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_JOINTS_CONFIG_KEY, true));
		setColliderDebugVisibility(visibility && hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_COLLIDERS_CONFIG_KEY, true));
		setMiscDebugVisibility(visibility && hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_COLLIDERS_CONFIG_KEY, true));
		setOutlineVisibility(visibility && hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_OUTLINE_CONFIG_KEY, true));
		setSceneInfoVisibility(visibility && hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_SCENE_INFOS_CONFIG_KEY, true));
		setWireframeVisibility(visibility && hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_WIREFRAME_CONFIG_KEY, true));
		setSceneVisibility(!hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_DISABLE_SCENE_RENDER_CONFIG_KEY, false));
	}

	@:access(h3d.scene.Skin)
	public function setJointsDebugVisibility(visible : Bool) {
		for (m in scene.s3d.getMeshes()) {
			var sk = Std.downcast(m,h3d.scene.Skin);
			if (sk != null)
				sk.showJoints = visible;
		}
	}

	public function setColliderDebugVisibility(visible : Bool) {
		if (visible) {
			if (rootDebugCollider == null) {
				rootDebugCollider = new h3d.scene.Object(scene.s3d);
				rootDebugCollider.name = "rootDebugCollider";
			}

			rootDebugCollider.removeChildren();

			var root3d = prefab.findFirstLocal3d();
			var meshes = root3d.getMeshes();
			var gizmos = root3d.findAll((f) -> Std.downcast(f, hrt.tools.Gizmo));
			meshes = meshes.filter(function (m : h3d.scene.Mesh) {
				if (Std.isOfType(m, h3d.scene.Graphics))
					return false;
				for (g in gizmos)
					if (g.isGizmo(m))
						return false;
				return true;
			});

			for (m in meshes) {
				var col = try {
					m.getCollider();
				} catch(e : Dynamic) {
					hide.Ide.showError('Error while trying to display debug colliders');
					null;
				}
				if (col == null)
					continue;
				var d = col.makeDebugObj();
				for (mat in d.getMaterials()) {
					mat.name = "$collider";
					mat.mainPass.setPassName("overlay");
					mat.shadows = false;
					mat.mainPass.wireframe = true;
				}
				rootDebugCollider.addChild(d);
			}
		} else if (rootDebugCollider != null) {
			rootDebugCollider.remove();
			rootDebugCollider = null;
		}
	}

	public function setMiscDebugVisibility(visible : Bool) {
		if (scene?.s3d?.renderer == null)
			return;
		scene.s3d.renderer.showEditorGuides = visible;
	}

	public function setOutlineVisibility(visible : Bool) {
		if (scene?.s3d?.renderer == null)
			return;
		for (e in scene.s3d.renderer.effects)
			if (e == outline)
				e.enabled = visible;
	}

	public function setSceneInfoVisibility(visible : Bool) {
		#if editor_hl
		scene?.showSceneInfos = visible;
		#end
	}

	public function setWireframeVisibility(visible : Bool) {
		var engine = h3d.Engine.getCurrent();
		if (engine.driver.hasFeature(Wireframe)) {
			for (mesh in scene.s3d.getMeshes()) {
				if (gizmo.isGizmo(mesh) || @:privateAccess grid.plane == mesh)
					continue;
				for (mat in mesh.getMaterials()) {
					if (mat.name == "$collider")
						continue;
					mat.mainPass.wireframe = visible;
				}
			}
		}
	}

	public function setSceneVisibility(visible : Bool) {
		scene.disableSceneRender = !visible;
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

	public function rebuildRenderProps() : Void {
		editor.updateRenderProps();
	}


	public function rebuildPrefabImpl(prefab: hrt.prefab.Prefab) : Void {
		if (prefab == null || prefab.parent == null) {
			editor.tryMake(editor.prefab);
			return;
		}

		editor.tryMakeChildren(prefab.parent);
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
		return [];
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
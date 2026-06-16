package hide.view;
import hrt.ui.*;

#if hui

enum SelectionFlag {
	NoRefreshTree;
	NoRecordUndo;
}

typedef SelectionFlags = haxe.EnumFlags<SelectionFlag>;
typedef TagInfo = {id: String, color: String};

typedef PrefabError = {
	var title: String;
	var exception: haxe.Exception;
};
@:access(hrt.ui.HuiSceneEditor)
class Prefab extends HuiView<{path: String}> {
	static var SRC =
		<prefab>
			<hui-scene-editor id="scene-editor"/>
		</prefab>

	static var _ = HuiView.register("prefab", Prefab);

	public static var TAGS_CONFIG_KEY = "sceneeditor.tags";
	public static var HIDDEN_CONFIG_KEY = "editor.hidden";
	public static var GIZMO_SNAP_CONFIG_KEY = "editor.gizmoSnap";
	public static var GIZMO_SNAP_STEP_CONFIG_KEY = "editor.gizmoSnapStep";
	public static var GIZMO_SNAP_GRID_CONFIG_KEY = "editor.gizmoSnapOnGrid";

	public var gizmoShouldSnap(default, set) : Bool = true;
	public function set_gizmoShouldSnap(v : Bool) {
		hide.Ide.inst.currentConfig.set(hide.view.Prefab.GIZMO_SNAP_CONFIG_KEY, v);
		return gizmoShouldSnap = v;
	}
	public var gizmoForceSnapOnGrid(default, set) : Bool = true;
	public function set_gizmoForceSnapOnGrid(v : Bool) {
		hide.Ide.inst.currentConfig.set(hide.view.Prefab.GIZMO_SNAP_GRID_CONFIG_KEY, v);
		return gizmoForceSnapOnGrid = v;
	}

	public var config(default, null) : hide.Config;
	public var hidden : Map<hrt.prefab.Prefab, Bool> = new Map();

	var prefabLookup : Map<h3d.scene.Object, hrt.prefab.Object3D> = new Map();
	var gizmo : hrt.tools.Gizmo = null;
	var rethrowMakeErrors: Bool = false;
	var prefab: hrt.prefab.Prefab;
	var interactives: Map<hrt.prefab.Prefab, h3d.scene.Interactive> = [];
	var selectedPrefabs: Map<hrt.prefab.Prefab, Bool> = [];
	var lastPushX : Float = -100;
	var lastPushY : Float = -100;
	var movedSinceLastPush : Bool = false;

	// List of prefabs that have make errors
	var errorPrefabs : Map<hrt.prefab.Prefab, PrefabError> = new Map();

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		hrt.tools.FileManager.inst.watchFileChange(onFileChange);

		if (state != null) {
			config = hide.Config.loadForFile(hide.Ide.inst, state.path);
			saveDisplayKey = 'prefabEditor:${state.path}';

		} else {
			config = hide.Ide.inst.currentConfig;
			saveDisplayKey = "prefabEditor:__empty";
		}

		sceneEditor.load = () -> reload();
		sceneEditor.getConfig = () -> { return config; };
		sceneEditor.getSelectedObjects = () -> {
			var selectedObjects = [];
			for (s in selectedPrefabs.keys()) {
				var obj3d = Std.downcast(s, hrt.prefab.Object3D);
				if (obj3d != null)
					selectedObjects.push(obj3d.local3d);
			}
			return selectedObjects;
		}

		registerCommand(HuiCommands.save, View, () -> { save();});

		sceneEditor.load();

		var hiddenArr : Array<String> = getDisplayState(HIDDEN_CONFIG_KEY, []);
		if (this.prefab != null) {
			for (p in this.prefab.flatten())
				if (hiddenArr.contains(p.getAbsPath(true, true)))
					setEditorVisibility(p, false);
		}

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

		registerCommand(hrt.ui.HuiCommands.selectAll, View, () -> {
			var all = this.prefab.flatten();
			all.remove(this.prefab);
			setSelection(all, SelectionFlags.ofInt(0));
		});

		@:privateAccess sceneEditor.debugGraph = new h2d.Graphics(sceneEditor.scene.s2d);

		sceneEditor.onScenePush = onScenePush;
		sceneEditor.onSceneMove = onSceneMove;

		sceneEditor.tree.getItemChildren = (el) -> {
			var prefab : hrt.prefab.Prefab = cast el ?? this.prefab;
			return cast prefab?.children;
		}

		sceneEditor.tree.getItemName = (el) -> {
			var prefab : hrt.prefab.Prefab = cast el;
			return return prefab.name;
		}

		sceneEditor.tree.onUserSelectionChanged = () -> {
			setSelection(cast sceneEditor.tree.getSelectedItems(), NoRefreshTree);
		}

		sceneEditor.tree.onItemDoubleClick = (_, el) -> {
			var prefab : hrt.prefab.Prefab = cast el;
			var obj = prefab.findFirstLocal3d();
			if (obj != null)
				sceneEditor.focusObjects([obj]);
		};

		sceneEditor.tree.getIdentifier = (el) -> {
			var prefab : hrt.prefab.Prefab = cast el;
			prefab.getAbsPath(true, true);
		}

		sceneEditor.tree.onItemContextMenu = (el) -> {
			var prefab : hrt.prefab.Prefab = cast el;
			if (prefab == null)
				prefab = this.prefab;

			var entries: Array<hrt.ui.HuiMenu.MenuItem> = [];

			entries.push({label: "Add Child Prefab", menu: createPrefabMenu((cl) -> getView().undo.run(actionCreatePrefab(prefab, prefab.children.length, cl), true))});

			entries.push({ label : "Enable", checked: prefab.enabled, click: () -> { setEnable(cast sceneEditor.tree.getSelectedItems(), !prefab.enabled); }});
			entries.push({ label : "Editor Only", checked: prefab.editorOnly, click: () -> { setEditorOnly(cast sceneEditor.tree.getSelectedItems(), !prefab.editorOnly); }});
			entries.push({ label : "In Game Only", checked: prefab.inGameOnly, click: () -> { setInGameOnly(cast sceneEditor.tree.getSelectedItems(), !prefab.inGameOnly); }});
			entries.push({ label : "Show In Editor", checked: getEditorVisibility(prefab), click: () -> { setEditorVisibility(prefab, !getEditorVisibility(prefab)); }});
			entries.push({ label : "Locked", checked: prefab.locked, click: () -> { setLock(cast sceneEditor.tree.getSelectedItems(), !prefab.locked);}});
			entries.push({ label : "Tag", menu: getTagMenu(cast sceneEditor.tree.getSelectedItems()) });
			entries.push({isSeparator: true});

			entries.push({ label: "Collapse", click: () -> {
				var items = sceneEditor.tree.getSelectedItems();
				for (i in items)
					sceneEditor.tree.toggleItemOpen(i, false);
			}});
			entries.push({ label : "Collapse All", click: () -> { sceneEditor.tree.closeAll(); }});

			entries.push({isSeparator: true});

			entries.push(HuiMenu.itemFromCommand(HuiCommands.selectAll, this));
			entries.push({ label : "Select Children", click: () -> { setSelection(prefab._children ?? [], SelectionFlags.ofInt(0)); }});
			entries.push(HuiMenu.itemFromCommand(HuiSceneEditor.focusCommand, this));

			entries.push({isSeparator: true});
			entries.push(HuiMenu.itemFromCommand(HuiCommands.cut, this));
			entries.push(HuiMenu.itemFromCommand(HuiCommands.copy, this));
			entries.push(HuiMenu.itemFromCommand(HuiCommands.paste, this));

			entries.push(HuiMenu.itemFromCommand(HuiCommands.delete, this));
			entries.push(HuiMenu.itemFromCommand(HuiCommands.rename, this));
			entries.push({ label : "Locked", checked: prefab.locked, click: () -> { setLock(cast sceneEditor.tree.getSelectedItems(), !prefab.locked); }});

			uiBase.contextMenu(entries);
		};

		sceneEditor.tree.dragAndDropInterface = {
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

		sceneEditor.tree.applyTreeStyle = (item, el) -> {
			function is(p: hrt.prefab.Prefab, status : (p : hrt.prefab.Prefab) -> Bool) {
				var res = status(p);
				var parent = p.parent;
				while (parent != null) {
					res = res || status(parent);
					parent = parent.parent;
				}

				return res;
			}

			el.dom.toggleClass("disable", is(item, (p) -> !p.enabled));
			el.dom.toggleClass("editor-only", is(item, (p) -> p.editorOnly));
			el.dom.toggleClass("ingame-only", is(item, (p) -> p.inGameOnly));
			el.dom.toggleClass("hidden", is(item, (p) -> !getEditorVisibility(p)));
			el.dom.toggleClass("locked", is(item, (p) -> p.locked));

			var t = getTag(item);
			if (t != null) {
				var c = hrt.impl.ColorSpace.Color.intFromString(t.color, true);
				@:privateAccess el.tagColor.visible = true;
				@:privateAccess el.tagColor.huiBg.background = c;
			}
			else {
				@:privateAccess el.tagColor.visible = false;
			}
		}

		sceneEditor.tree.getItemIcon = (item: hrt.prefab.Prefab) -> {
			if (errorPrefabs.get(item) != null) {
				return HuiRes.icons.error;
			}
			return return HuiRes.icons.file_blank;
		}

		this.gizmoShouldSnap = hide.Ide.inst.currentConfig.get(hide.view.Prefab.GIZMO_SNAP_CONFIG_KEY, true);
		this.gizmoForceSnapOnGrid = hide.Ide.inst.currentConfig.get(hide.view.Prefab.GIZMO_SNAP_GRID_CONFIG_KEY, true);


		sceneEditor.scene.onDragMove = sceneDragMove;
		sceneEditor.scene.onDragOut = sceneDragOut;
		sceneEditor.scene.onDragOver = sceneDragOver;
		sceneEditor.scene.onDrop = sceneDrop;



		gizmo = new hrt.tools.Gizmo(sceneEditor.scene.s3d);
		gizmo.visible = false;
		registerCommand(hrt.tools.Gizmo.gizmoSwitchModeCommand, View, gizmo.switchMode);
		registerCommand(hrt.tools.Gizmo.gizmoTranslateCommand, View, gizmo.translationMode);
		registerCommand(hrt.tools.Gizmo.gizmoRotateCommand, View, gizmo.rotationMode);
		registerCommand(hrt.tools.Gizmo.gizmoScaleCommand, View, gizmo.scalingMode);

		var initialTransform = new h3d.Matrix();
		var initialAbs = new h3d.Matrix();
		var obj3ds : Array<hrt.prefab.Object3D> = [];
		gizmo.shouldSnap = () -> { return this.gizmoShouldSnap; };
		gizmo.snap = (v: Float, mode: hrt.tools.Gizmo.EditMode) -> {
			if ((!gizmo.shouldSnap() && !hxd.Key.isDown(hxd.Key.CTRL)) || mode.match(hrt.tools.Gizmo.EditMode.Rotation))
				return v;
			v = hxd.Math.round(v / sceneEditor.gizmoSnapStep) * sceneEditor.gizmoSnapStep;
			if (!gizmoForceSnapOnGrid)
				return v;
			return hxd.Math.round(v / sceneEditor.grid.lineSpacing) * sceneEditor.grid.lineSpacing;
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
				p.x = hxd.Math.round(p.x / sceneEditor.grid.lineSpacing) * sceneEditor.grid.lineSpacing;
				p.y = hxd.Math.round(p.y / sceneEditor.grid.lineSpacing) * sceneEditor.grid.lineSpacing;
				p.z = hxd.Math.round(p.z / sceneEditor.grid.lineSpacing) * sceneEditor.grid.lineSpacing;
				trs.setPosition(p);
				gizmo.setPosition(p.x, p.y, p.z);
			}

			trs.multiply(trs, parentInv);

			if (offsetScale != null)
				trs.prependScale(offsetScale.x, offsetScale.y, offsetScale.z);

			obj3d.setTransform(trs);
			obj3d.applyTransform();

			sceneEditor.inspectorRoot?.refreshFields();
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

		buildToolbar();
	}

	function getDropPath(op: HuiDragOp) : Null<String> {
		if (op.type != HuiFileBrowser.fileDragOp)
			return null;
		var files : Array<String> = op.data;
		if (files == null)
			return null;
		if (files.length == 0)
			return null;
		var file = files[0];
		if (!StringTools.endsWith(file, ".prefab") && !StringTools.endsWith(file, ".fx"))
			return null;
		return file;
	}

	function sceneDragOver(op: HuiDragOp) {
		op.acceptDrop = false;
		var path = getDropPath(op);
		if (path == null)
			return;
		op.acceptDrop = true;
	}

	function sceneDragOut(op: HuiDragOp) {

	}

	function sceneDragMove(op: HuiDragOp) {
		sceneDragOver(op);
	}

	function sceneDrop(op: HuiDragOp) {
		var pathAbs = getDropPath(op);
		if (pathAbs == null)
			return;

		var path = Ide.inst.makeRelative(pathAbs);

		if (!hxd.res.Loader.currentInstance.exists(path)) {
			Ide.showError('Path "$path" is not available from this project resource folder');
			return;
		}

		var pos = sceneEditor.screenToGround(op.event.relX, op.event.relY);
		if (pos == null) {
			pos = new h3d.Vector();
			Ide.showWarning("Couldn't find a position to place the droppped prefab. It was created at the scene origin");
		}

		var parent = getSelectionOrdered()[0] ?? prefab;
		var ref : hrt.prefab.Reference = if (StringTools.endsWith(path, ".fx")) {
			new hrt.prefab.fx.SubFX(null, prefab.shared);
		} else {
			new hrt.prefab.Reference(null, prefab.shared);
		}

		ref.name = new haxe.io.Path(path).file;
		ref.source = path;
		if (ref.hasCycle()) {
			Ide.showError('Adding $path to scene would create a cycle');
			return;
		}

		var reparent = actionReparentPrefab(ref, parent, parent.children.length);
		var select = actionMakeSelection([ref]);

		var action = (isUndo) -> {
			reparent(isUndo);
			select(isUndo);
		};

		getView().undo.run(action, true);
	}


	var crashSync = false;
	var crashSyncOneFrame = false;


	override function safeSync(ctx) {
		super.safeSync(ctx);
		gizmo.update(ctx.elapsedTime);

		if (crashSync) {
			throw "test crash sync";
		}

		if (crashSyncOneFrame) {
			crashSyncOneFrame = false;
			throw "test crash sync one frame";
		}
	}

	override function getContextMenuContent(content: Array<hide.comp.ContextMenu.MenuItem>) {
		content.push({label: "Save", click: () -> execCommand(HuiCommands.save)});
		content.push({label: "Rebuild", click: () -> tryMake(prefab)});
		content.push({isSeparator: true});
		content.push({label: "Debug dump", click: () -> {
			var ser = @:privateAccess prefab.serialize();
			trace(haxe.Json.stringify(ser, "\t"));
		}});
	}

	function onFileChange(fileEntry: hrt.tools.FileManager.FileEntry) {
		if (fileEntry.getPath() == state.path) {
			onExternalChange();
		}
	}

	override function getViewName():String {
		return state.path.split("/").splice(-1, 2).join("/");
	}

	override function requestClose(cb: (canClose:Bool) -> Void) {
		if (hasUnsavedChanges) {
			uiBase.confirm("Save change before closing ?", Save | DontSave | Cancel, (choice: hrt.ui.HuiConfirmPopup.ConfirmButton) -> {
				switch (choice) {
					case Save:
						execCommand(HuiCommands.save);
						cb(true);
					case DontSave:
						cb(true);
					case Cancel:
						cb(false);
					default:
						throw "???";
				}
			});
		} else {
			cb(true);
		}
	}

	override function getToolbarWidgets() : Array<HuiElement> {
		var widgets : Array<HuiElement> = [];

		widgets.push(new hrt.ui.HuiToolbar.HuiTransformWidgets(gizmo));
		widgets.push(new hrt.ui.HuiToolbar.HuiSnapWidget(this));

		var cameraBtn = new HuiButton();
		new HuiIcon("camera", cameraBtn);
		cameraBtn.onClick = (_) -> {
			uiBase.addPopup(new hrt.ui.HuiToolbar.HuiCameraSettingsPopup(sceneEditor), { object: Element(cameraBtn), directionX: StartInside, directionY: EndOutside });
		}
		widgets.push(cameraBtn);

		var helpBtn = new HuiButton();
		helpBtn.onClick = (_) -> {
			uiBase.addPopup(new hrt.ui.HuiToolbar.HuiHelpPopup(this.registeredCommands), { object: Element(helpBtn), directionX: StartInside, directionY: EndOutside });
		};
		new HuiIcon("question_mark", helpBtn);
		widgets.push(helpBtn);

		widgets.push(new hrt.ui.HuiToolbar.HuiVisibilityWidget(sceneEditor));
		widgets.push(new hrt.ui.HuiToolbar.HuiViewModesWidget(sceneEditor.scene.s3d));
		widgets.push(new hrt.ui.HuiToolbar.HuiSceneFiltersWidget(sceneEditor));
		widgets.push(new hrt.ui.HuiToolbar.HuiRenderPropsWidget(sceneEditor));


		var crashButton = new HuiButton();
		new HuiIcon("error", crashButton);
		crashButton.onClick = (e) -> {
			uiBase.contextMenu([
				{label: "Crash sync", click: () -> crashSync = !crashSync, checked: crashSync},
				{label: "Crash sync one frame", click: () -> crashSyncOneFrame = true},
				{label: "Crash instant", click: () -> throw "crash instant"},
			]);
		};
		widgets.push(crashButton);

		return widgets;
	}

	override function onRemove() {
		super.onRemove();
		hrt.tools.FileManager.inst.unwatchFileChange(onFileChange);
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

		tryMake(prefab);
		// makeRenderProps();

		// hide.App.defer(resetCamera);

		sceneEditor.updateDebugOverlayVisibility();
	}

	/**
		Try to make the given prefab. If the prefab is already instantiated, tries do cleanup it first.
		It should be an error to call this on a prefab that is not the root without also rebuilding this prefab sibiling,
		as it will change the ordering of the heaps objects in the scene (which can cause subtle differences, espetially with 2d scenes where the order really matters).
		For that you should call tryMakeChildren(prefab.parent) instead.
	**/
	public function tryMake(prefab: hrt.prefab.Prefab) {
		removePrefabInstance(prefab);

		if (prefab.parent == null && prefab.shared.parentPrefab == null) {
			@:privateAccess prefab.shared.root2d = prefab.shared.current2d = new h2d.Object(sceneEditor.scene.s2d);
			@:privateAccess prefab.shared.root3d = prefab.shared.current3d = new h3d.scene.Object(sceneEditor.scene.s3d);
		} else {
			prefab.shared.current2d = prefab.findFirstLocal2d(true);
			prefab.shared.current3d = prefab.findFirstLocal3d(true);
		}

		prefab.shared.customMake = customTryMake;

		if (prefab.parent != null) {
			prefab.parent.makeChild(prefab);
		} else {
			customTryMake(prefab);
		}

		var fx = Std.downcast(prefab.findFirstLocal3d(), hrt.prefab.fx.FX.FXAnimation);
		if (fx != null) {
			fx.loop = true;
		}

		sceneEditor.tree.rebuild();
	}

	function customTryMake(prefab: hrt.prefab.Prefab) {
		// Don't make prefab that have error in their parents
		var prevError = errorPrefabs.get(prefab.parent);
		if (prefab.parent != null && prevError != null) {
			errorPrefabs.set(prefab, {title: "Didn't make prefab, parent has error", exception: prevError.exception});
			return;
		}

		var errorState = errorPrefabs.get(prefab) != null;
		var newErrorState = false;
		errorPrefabs.remove(prefab);

		try {
			prefab.make();
			for (p in prefab.flatten()) {
				makePrefabInteractive(p);
				var obj3d = Std.downcast(p, hrt.prefab.Object3D);
				if (obj3d != null && obj3d.local3d != null) {
					var objects = obj3d.local3d.findAll((o) -> Std.downcast(o, h3d.scene.Mesh));
					for (o in objects)
						prefabLookup.set(o, obj3d);
				}
			}
		} catch (e) {
			removePrefabInstance(prefab);
			errorPrefabs.set(prefab, {title: "Prefab make raised an exception", exception: e});

			var parentPrefab = prefab.shared.parentPrefab;
			while(parentPrefab != null) {
				var ref = Std.downcast(parentPrefab, hrt.prefab.Reference);
				if (ref != null && ref.editMode == None) {
					errorPrefabs.set(parentPrefab, {title: "Referenced prefab has errors", exception: e});
				}
				parentPrefab = parentPrefab.shared.parentPrefab;
			}

			for (child in prefab.flatten()) {
				if (child == prefab)
					continue;
				errorPrefabs.set(child, {title: "Parent prefab has errors", exception: e});
			}

			@:privateAccess sceneEditor.tree.requestRefresh(Refresh);

			if (rethrowMakeErrors) {
				hl.Api.rethrow(e);
			} else {
				hide.Ide.showError('Error making prefab ${prefab.getAbsPath(true)} : $e');
			}
			newErrorState = true;
		}

		if (errorState != newErrorState && selectedPrefabs.exists(prefab)) {
			App.defer(() -> refreshInspector());
		}
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

	function load(path : String) {
		try {
			var prefabData = hxd.res.Loader.currentInstance.load(path).toPrefab().loadBypassCache().clone();
			setPrefab(prefabData);
		} catch(e) {
			sceneEditor.setCriticalError('Couldn\'t load $path', e);
		}
	}

	var waitingExternal = false;
	function onExternalChange() {
		if (waitingExternal)
			return;

		if (hasUnsavedChanges) {
			waitingExternal = true;
			uiBase.confirm('${state.path} has been modified on disk, reload and ignore local changes ?', Ok | Cancel, (result) -> {
				waitingExternal = false;
				if (result == Ok) {
					reload();
				}
			});
		} else {
			reload();
		}
	}

	function reload() {
		var path = Ide.inst.getRelPath(state.path);
		load(path);
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
			@:privateAccess sceneEditor.tree.forceRefreshTree();
			sceneEditor.tree.setSelection(selection);
			for (item in selection) {
				sceneEditor.tree.revealItem(item);
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

	function getEditorVisibility(prefab: hrt.prefab.Prefab) {
		return hidden.get(prefab) == null;
	}

	function setEditorVisibility(prefab : hrt.prefab.Prefab, isVisible : Bool) {
		if (isVisible)
			hidden.remove(prefab);
		else
			hidden.set(prefab, true);

		var hiddenArr = [for (h in hidden.keys()) h.getAbsPath(true, true)];
		saveDisplayState(HIDDEN_CONFIG_KEY, hiddenArr);

		var obj3d = Std.downcast(prefab, hrt.prefab.Object3D);
		obj3d.local3d?.visible = isVisible;
	}

	public function setEnable(prefabs : Array<hrt.prefab.Prefab>, isEnable: Bool) {
		var old = [for(p in prefabs) p.enabled];
		function apply(on) {
			for (i in 0...prefabs.length) {
				prefabs[i].enabled = on ? isEnable : old[i];
				tryMake(prefabs[i]);
			}
		}
		apply(true);
		undo.record((undo) -> {
			if (undo)
				apply(false);
			else
				apply(true);
		}, true);
	}

	public function setEditorOnly(prefabs : Array<hrt.prefab.Prefab>, isEditorOnly: Bool) {
		var old = [for(p in prefabs) p.enabled];
		function apply(on) {
			for (i in 0...prefabs.length) {
				prefabs[i].editorOnly = on ? isEditorOnly : old[i];
				tryMake(prefabs[i]);
			}
		}
		apply(true);
		undo.record((undo) -> {
			if (undo)
				apply(false);
			else
				apply(true);
		}, true);
	}

	public function setInGameOnly(prefabs : Array<hrt.prefab.Prefab>, isInGameOnly: Bool) {
		var old = [for(p in prefabs) p.enabled];
		function apply(on) {
			for (i in 0...prefabs.length) {
				prefabs[i].inGameOnly = on ? isInGameOnly : old[i];
				tryMake(prefabs[i]);
			}
		}
		apply(true);
		undo.record((undo) -> {
			if (undo)
				apply(false);
			else
				apply(true);
		}, true);
	}

	public function setLock(prefabs : Array<hrt.prefab.Prefab>, isLocked: Bool) {
		var old = [for(p in prefabs) p.enabled];
		function apply(on) {
			for (i in 0...prefabs.length) {
				prefabs[i].locked = on ? isLocked : old[i];
				tryMake(prefabs[i]);
			}
		}
		apply(true);
		undo.record((undo) -> {
			if (undo)
				apply(false);
			else
				apply(true);
		}, true);
	}

	function getTagMenu(prefabs: Array<hrt.prefab.Prefab>) : Array<hide.comp.ContextMenu.MenuItem> {
		var tags = getAvailableTags();
		if (tags == null) return null;
		tags = tags.copy();
		var ret = [];
		var noTag : hide.view.TagInfo = cast { id: "None" };
		tags.unshift(noTag);
		for (tag in tags) {
			var style = 'background-color: ${tag.color};';
			var checked = false;
			for (p in prefabs) {
				if (getTag(p) == tag)
					checked = true;
			}
			ret.push({
				label: tag.id,
				color: tag.color == null ? null : hrt.impl.ColorSpace.Color.intFromString(tag.color, true),
				click: function () {
					if (tag == noTag) {
						setTags(prefabs, null);
					} else {
						setTags(prefabs, tag.id);
					}
				},
				stayOpen: true,
				radio: () -> {
					for (p in prefabs) {
						if ((p.props:Dynamic)?.tag == tag.id || ((p.props:Dynamic)?.tag == null && tag == noTag))
							return true;
					}
					return false;
				}
			});
		}
		return ret;
	}

	function getAvailableTags() : Array<TagInfo>{
		return cast Ide.inst.config.current.get(TAGS_CONFIG_KEY);
	}

	public function getTag(p: hrt.prefab.Prefab) : TagInfo {
		if (p.props != null) {
			var tagId = Reflect.field(p.props, "tag");
			if(tagId != null) {
				var tags = getAvailableTags();
				if(tags != null)
					return Lambda.find(tags, t -> t.id == tagId);
			}
		}
		return null;
	}

	public function setTags(prefabs: Array<hrt.prefab.Prefab>, tag: String) {
		var oldValues = [for (prefab in prefabs) (prefab.props:Dynamic)?.tag];

		function exec(isUndo : Bool) {
			for (i => prefab in prefabs) {
				prefab.props ??= {};
				if (!isUndo) {
					(prefab.props:Dynamic).tag = tag;
				}
				else {
					(prefab.props:Dynamic).tag = oldValues[i];
				}
			}
		}
		exec(false);
		undo.record(exec, true);
	}


	function save() {
		if (!hasUnsavedChanges)
			return;

		undo.markClean();
		hasUnsavedChanges = false;
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
			try {
				sys.FileSystem.deleteFile(tmpDir + "/" + allTemp.shift());
			} catch (e) {

			}
		}
	}

	function inspectorDoTry(prefab: hrt.prefab.Prefab, callback: Void -> Void) {
		try {
			callback();

			// try to make the prefab if it it's in a error state even if
			// callback didn't throw
			if (errorPrefabs.exists(prefab)) {
				tryMake(prefab);
			}
		} catch(e) {
			trace(e);
			tryMake(prefab);
		}
	}

	function refreshInspector() {
		var prefabs = [for (prefab => _ in selectedPrefabs) prefab];

		sceneEditor.inspectorPanel.removeChildElements();
		sceneEditor.inspectorRoot = null;

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

		var anyPrefabErrors : PrefabError = null;
		for (prefab in prefabs) {
			anyPrefabErrors  = errorPrefabs.get(prefab);
			if (anyPrefabErrors != null)
				break;
		}

		var editContext = new EditContext(this, null);
		sceneEditor.inspectorRoot = new hide.kit.KitRoot(null, null, editPrefab, editContext);
		sceneEditor.inspectorRoot.doTry = inspectorDoTry.bind(editPrefab);
		@:privateAccess sceneEditor.inspectorRoot.isMultiEdit = isMultiEdit;

		@:privateAccess editContext.saveKey = Type.getClassName(commonClass);
		editContext.root = sceneEditor.inspectorRoot;

		static final inspectorErrorMsg = "Couldn't create the inspector";

		var inspectorError : PrefabError = null; // If building the inspector results in an error
		try {
			editPrefab.edit2(editContext);
			sceneEditor.inspectorRoot.postEditStep();
		} catch(e) {
			inspectorError = {title: inspectorErrorMsg, exception: e};
		}

		if (isMultiEdit && inspectorError == null) {
			for (i => prefab in prefabs) {
				var childEditContext = new EditContext(this, editContext);
				@:privateAccess childEditContext.saveKey = Type.getClassName(commonClass);
				var childRoot = new hide.kit.KitRoot(null, null, prefab, childEditContext);
				sceneEditor.inspectorRoot.doTry = inspectorDoTry.bind(prefab);
				@:privateAccess childRoot.isMultiEdit = true;
				sceneEditor.inspectorRoot.editedPrefabsProperties.push(childRoot);
				childEditContext.root = childRoot;
				try {
					prefab.edit2(childEditContext);
					childRoot.postEditStep();
				} catch (e) {
					inspectorError = {title: inspectorErrorMsg, exception: e};
					break;
				}
			}
		}

		if (inspectorError != null) {
			sceneEditor.inspectorPanel.removeChildElements();
			sceneEditor.inspectorRoot = null;
		}

		var error = inspectorError ?? anyPrefabErrors;

		var wrapper = new HuiElement(sceneEditor.inspectorPanel);
		var className = new HuiText(Type.getClassName(commonClass).split(".").pop(), wrapper);
		className.dom.addClass("italic");
		wrapper.dom.addClass("class-name");

		if (error != null) {
			var errorDisplay = new HuiPrefabInspectorError(sceneEditor.inspectorPanel);
			errorDisplay.errorText.text = "This <i>prefab</i> had an error : " + error.title + "<br/>Exception : " + error.exception.message;

			errorDisplay.button.onClick = (e) -> {
				var errorInfo = new HuiErrorDisplay();
				errorInfo.setError(error.title, error.exception);
				uiBase.addPopup(errorInfo);
			}
		}

		if (inspectorError != null)
			return;

		sceneEditor.inspectorRoot.make();

		sceneEditor.inspectorPanel.addChild(@:privateAccess sceneEditor.inspectorRoot.native);
		if (uiBase != null) {
			@:privateAccess sceneEditor.inspectorRoot.native.get().dom.applyStyle(uiBase.style);
		}
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
		sceneEditor.tree.rename(target, (newName: String) -> {
			getView().undo.run(actionRenamePrefab(target, newName), true);
		});
	}

	function actionRenamePrefab(target: hrt.prefab.Prefab, name: String) : hrt.tools.Undo.Action {
		var oldName = target.name;

		return (isUndo) -> {
			target.name = isUndo ? oldName : name;
			target.updateInstance("name");
			sceneEditor.tree.rebuild(target);
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
				sceneEditor.tree.toggleItemOpen(newParent, true);
			rebuildPrefabTree(isUndo ? parent : oldParent);
			rebuildPrefabTree(newParent);
			// updateDebugOverlayVisibility();
			// checkRemakeRenderProps(prefab);
			sceneEditor.tree.revealItem(prefab);
		};
	}

	function rebuildPrefabTree(prefab: hrt.prefab.Prefab) {
		if (prefab == null)
			return;
		if (prefab == this.prefab)
			sceneEditor.tree.rebuild(null);
		else
			sceneEditor.tree.rebuild(prefab);
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


	public function getRenderPropsPaths() : Array<{name: String, value: String}> {
		// var renderProps = config.getLocal("scene.renderProps");
		// if (renderProps == null)
		// 	return [];

		// if (renderProps is String) {
		// 	return [{name: "", value: (cast renderProps: String)}];
		// }

		// if (renderProps is Array) {
		// 	return cast renderProps;
		// }
		return [];
	}

	function setRenderProps(path: String) {

	}

	function onScenePush(e: hxd.Event) : Void {
		if (e.button == 0) {
			var prefabs = [];
			var objs = sceneEditor.getObjectsAt(cast e.relX, cast e.relY, prefab.findFirstLocal3d(), (o) -> Std.isOfType(o, h3d.scene.Mesh));
			var newSelection : Array<hrt.prefab.Prefab> = [];
			for (o in objs) {
				var p = prefabLookup.get(o);
				if (p == null || p.locked)
					continue;
				prefabs.push(p);
			}

			var mouseX = e.relX - sceneEditor.scene.absX;
			var mouseX = e.relY - sceneEditor.scene.absY;

			lastPushX = e.relX;
			lastPushY = e.relY;

			var newPrefab : hrt.prefab.Prefab = null;
			if (prefabs.length > 0) {
				newPrefab = prefabs[0];
				if (!movedSinceLastPush) {
					// select next prefab in the selection stack
					for (idx => p in prefabs) {
						if (selectedPrefabs.get(p)) {
							newPrefab = prefabs[(idx + 1) % prefabs.length];
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

	static function dumpObject(obj: h3d.scene.Object, pad: String = "") : String {
		var str = "";
		str += '$pad${obj.name}[${Type.getClassName(Type.getClass(obj))}]\n';
		var nextPad = pad + "\t";
		for (i in 0...obj.numChildren) {
			str += dumpObject(obj.getChildAt(i), nextPad);
		}
		return str;
	}
}

@:access(hide.view.Prefab)
@:access(hrt.ui.HuiSceneEditor)
class EditContext extends hrt.prefab.EditContext2 {
	var editor : Prefab;
	var saveKey: String;

	public function new(editor: Prefab, parent: hrt.prefab.EditContext2) {
		super(parent);
		this.editor = editor;
	}

	public function rebuildInspector() : Void {
		editor.refreshInspector();
	};

	public function rebuildRenderProps() : Void {
		// editor.updateRenderProps();
	}


	public function rebuildPrefabImpl(prefab: hrt.prefab.Prefab) : Void {
		editor.tryMake(prefab);
	}

	/**
		Request that the scene tree widget should be rebuild for the given prefab
	**/
	public function rebuildTreeImpl() : Void {
		// editor.treePrefab.rebuild();
	}


	public function getScene3d() : h3d.scene.Scene {
		return editor.sceneEditor.scene.s3d;
	}

	public function getScene2d() : h2d.Scene {
		return editor.sceneEditor.scene.s2d;
	}

	/**
		Return the camera controller of the current editor
	**/
	public function getCameraController3d() : Dynamic {
		return editor.sceneEditor.cameraController;
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

class HuiPrefabInspectorError extends HuiElement {
	static var SRC =
		<hui-prefab-inspector-error>
			<hui-element id="error-text-container">
				<hui-text public id="error-text"/>
			</hui-element>
			<hui-button public id="button">
				<hui-text("Stack Trace")/>
			</hui-button>
		</hui-prefab-inspector-error>
}

#end
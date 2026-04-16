package hide.view;
import hrt.ui.*;

#if hui

class Prefab extends HuiView<{path: String}> {
	static var SRC =
		<prefab>
			<hui-prefab-editor id="prefab-editor"/>
		</prefab>

	static var _ = HuiView.register("prefab", Prefab);

	public static var GIZMO_SNAP_CONFIG_KEY = "editor.gizmoSnap";
	public static var GIZMO_SNAP_STEP_CONFIG_KEY = "editor.gizmoSnapStep";
	public static var GIZMO_SNAP_GRID_CONFIG_KEY = "editor.gizmoSnapOnGrid";

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		var path = Ide.inst.getRelPath(state.path);

		try {
			var prefabData = hxd.res.Loader.currentInstance.load(path).toPrefab().load().clone();
			prefabEditor.setPrefab(prefabData);
		} catch(e) {
			prefabEditor.remove();
			var error = 'Couldn\'t load $path : $e';
			hide.Ide.showError(error);
			new HuiText(error, this);
		}

		undo.onAfterChange = () -> {
			hasUnsavedChanges = prefabEditor.hasUnsavedChanges();
		}

		registerCommand(HuiCommands.save, View, () -> {@:privateAccess prefabEditor.save(); hasUnsavedChanges = prefabEditor.hasUnsavedChanges();});

		buildToolbar();
	}

	override function sync(ctx) {
		super.sync(ctx);
	}

	override function getContextMenuContent(content: Array<hide.comp.ContextMenu.MenuItem>) {
		content.push({label: "Save", click: () -> execCommand(HuiCommands.save)});
		content.push({label: "Rebuild", click: () -> @:privateAccess prefabEditor.tryMake(prefabEditor.prefab)});
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

		widgets.push(new hrt.ui.HuiToolbar.HuiTransformWidgets(@:privateAccess prefabEditor.gizmo));

		var snapBtn = new HuiToggle();
		snapBtn.dom.addClass("group-start");
		snapBtn.toggled = prefabEditor.gizmoShouldSnap;
		snapBtn.onClick = (_) -> {
			prefabEditor.gizmoShouldSnap = !prefabEditor.gizmoShouldSnap;
			snapBtn.toggled = prefabEditor.gizmoShouldSnap;
		}
		new HuiIcon("grid-magnet", snapBtn);
		widgets.push(snapBtn);

		var snapPopupBtn = new HuiButton();
		snapPopupBtn.dom.addClass("group-end");
		snapPopupBtn.dom.addClass("tiny");
		new HuiIcon("dropDown", snapPopupBtn);
		snapPopupBtn.onClick = (_) -> {
			uiBase.addPopup(new hrt.ui.HuiToolbar.HuiGridSettingsPopup(prefabEditor), { object: Element(snapPopupBtn), directionX: StartInside, directionY: EndOutside });
		}
		widgets.push(snapPopupBtn);

		var cameraBtn = new HuiButton();
		new HuiIcon("camera", cameraBtn);
		cameraBtn.onClick = (_) -> {
			uiBase.addPopup(new hrt.ui.HuiToolbar.HuiCameraSettingsPopup(@:privateAccess prefabEditor), { object: Element(cameraBtn), directionX: StartInside, directionY: EndOutside });
		}
		widgets.push(cameraBtn);

		var helpBtn = new HuiButton();
		helpBtn.onClick = (_) -> {
			uiBase.addPopup(new hrt.ui.HuiToolbar.HuiHelpPopup(this.registeredCommands), { object: Element(helpBtn), directionX: StartInside, directionY: EndOutside });
		};
		new HuiIcon("question_mark", helpBtn);
		widgets.push(helpBtn);

		var rulerBtn = new HuiToggle();
		rulerBtn.onClick = (_) -> {
			// TODO
		};
		new HuiIcon("ruler", rulerBtn);
		widgets.push(rulerBtn);

		var viewportOverlayBtn = new HuiToggle();
		viewportOverlayBtn.onClick = (_) -> {
			// TODO
		};
		new HuiIcon("visibility", viewportOverlayBtn);
		widgets.push(viewportOverlayBtn);

		var viewModesBtn = new HuiButton();
		viewModesBtn.onClick = (_) -> {
			// TODO
		};
		new HuiText("View Modes", viewModesBtn);
		new HuiIcon("dropDown", viewModesBtn);
		widgets.push(viewModesBtn);

		var graphicsFilterBtn = new HuiButton();
		graphicsFilterBtn.onClick = (_) -> {
			// TODO
		};
		new HuiText("Graphics Filters", graphicsFilterBtn);
		new HuiIcon("dropDown", graphicsFilterBtn);
		widgets.push(graphicsFilterBtn);

		var sceneFilterBtn = new HuiButton();
		sceneFilterBtn.onClick = (_) -> {
			// TODO
		};
		new HuiText("Scene Filters", sceneFilterBtn);
		new HuiIcon("dropDown", sceneFilterBtn);
		widgets.push(sceneFilterBtn);

		var renderPropsBtn = new HuiButton();
		renderPropsBtn.onClick = (_) -> {
			// TODO
		};
		new HuiText("Render Props", renderPropsBtn);
		new HuiIcon("dropDown", renderPropsBtn);
		widgets.push(renderPropsBtn);

		return widgets;
	}
}

#end
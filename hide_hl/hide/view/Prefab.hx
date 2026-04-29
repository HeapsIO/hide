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

	public static var CAM_CTRL_CONFIG_KEY = "editor.camera.type";
	public static var CAM_CTRL_FOV_CONFIG_KEY = "editor.camera.fov";
	public static var CAM_CTRL_NEAR_CONFIG_KEY = "editor.camera.near";
	public static var CAM_CTRL_FAR_CONFIG_KEY = "editor.camera.far";

	public static var VISIBILITY_OVERLAY_CONFIG_KEY = "editor.visibility.overlay";
	public static var VISIBILITY_GRID_CONFIG_KEY = "editor.visibility.grid";
	public static var VISIBILITY_JOINTS_CONFIG_KEY = "editor.visibility.joints";
	public static var VISIBILITY_COLLIDERS_CONFIG_KEY = "editor.visibility.colliders";
	public static var VISIBILITY_MISC_CONFIG_KEY = "editor.visibility.misc";
	public static var VISIBILITY_GIZMO_CONFIG_KEY = "editor.visibility.gizmo";
	public static var VISIBILITY_OUTLINE_CONFIG_KEY = "editor.visibility.outline";
	public static var VISIBILITY_SCENE_INFOS_CONFIG_KEY = "editor.visibility.sceneInfos";
	public static var VISIBILITY_WIREFRAME_CONFIG_KEY = "editor.visibility.wireframe";
	public static var VISIBILITY_DISABLE_SCENE_RENDER_CONFIG_KEY = "editor.visibility.disableSceneRender";

	public static var VIEW_MODE_TYPE = "editor.visibility.viewModeType";

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
		content.push({isSeparator: true});
		content.push({label: "Debug dump", click: () -> {
			var ser = @:privateAccess prefabEditor.prefab.serialize();
			trace(haxe.Json.stringify(ser, "\t"));
		}});
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
		widgets.push(new hrt.ui.HuiToolbar.HuiSnapWidget(prefabEditor));

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

		widgets.push(new hrt.ui.HuiToolbar.HuiVisibilityWidget(prefabEditor));
		widgets.push(new hrt.ui.HuiToolbar.HuiViewModesWidget(@:privateAccess prefabEditor.scene.s3d));

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
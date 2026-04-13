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

		var gizmo = @:privateAccess prefabEditor.gizmo;

		var translationBtn = new HuiToggle();
		translationBtn.dom.addClass("group-start");
		translationBtn.onClick = (_) -> { gizmo?.translationMode(); };
		new HuiIcon("translation", translationBtn);
		translationBtn.toggled = true;
		widgets.push(translationBtn);

		var rotationBtn = new HuiToggle();
		rotationBtn.dom.addClass("group");
		new HuiIcon("rotation", rotationBtn);
		rotationBtn.onClick = (_) -> { gizmo?.rotationMode(); };
		widgets.push(rotationBtn);

		var scaleBtn = new HuiToggle();
		scaleBtn.dom.addClass("group-end");
		scaleBtn.onClick = (_) -> { gizmo?.scalingMode(); };
		new HuiIcon("scale", scaleBtn);
		widgets.push(scaleBtn);

		gizmo.onChangeMode = (mode) -> {
			translationBtn.toggled = mode.match(Translation);
			rotationBtn.toggled = mode.match(Rotation);
			scaleBtn.toggled = mode.match(Scale);
		}

		var localTransformBtn = new HuiButton();
		localTransformBtn.onClick = (_) -> {
			gizmo?.isLocalTransform = !gizmo?.isLocalTransform;
			var objs = @:privateAccess prefabEditor.getSelectedObjects();
			if (objs != null && objs.length > 0)
				@:privateAccess prefabEditor.gizmo.moveToObjects(objs);
		};
		var localTransformIcon = new HuiIcon("world", localTransformBtn);
		widgets.push(localTransformBtn);

		gizmo.onChangeTransformSpace = (isLocalTransform) -> {
			localTransformIcon.setIcon(isLocalTransform ? "local" : "world");
		}

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
			uiBase.addPopup(new HuiGridSettingsPopup(prefabEditor), { object: Element(snapPopupBtn), directionX: StartInside, directionY: EndOutside });
		}
		widgets.push(snapPopupBtn);

		var cameraBtn = new HuiButton();
		new HuiIcon("camera", cameraBtn);
		cameraBtn.onClick = (_) -> {
			uiBase.addPopup(new HuiCameraSettingsPopup(@:privateAccess prefabEditor.cameraController), { object: Element(cameraBtn), directionX: StartInside, directionY: EndOutside });
		}
		widgets.push(cameraBtn);

		var helpBtn = new HuiButton();
		helpBtn.onClick = (_) -> {
			uiBase.addPopup(new HuiHelpPopup(this.registeredCommands), { object: Element(helpBtn), directionX: StartInside, directionY: EndOutside });
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

class HuiCameraSettingsPopup extends HuiPopup {
	static var SRC =
		<hui-camera-settings-popup class="vertical">
			<hui-text("Camera settings") id="title"/>
			<hui-element class="horizontal">
				<hui-text("Camera Type") class="label"/>
				<hui-select id="cam-type" class="value"/>
			</hui-element>
			<hui-element class="horizontal">
				<hui-text("FOV") class="label"/>
				<hui-slider step={0.1} min={0} max={120} decimals={2} id="fov" class="value"/>
			</hui-element>
			<hui-element class="horizontal">
				<hui-text("zNear") class="label"/>
				<hui-slider step={0.1} min={0.00001} max={100000} decimals={2} id="zNear" class="value"/>
			</hui-element>
			<hui-element class="horizontal">
				<hui-text("zFar") class="label"/>
				<hui-slider step={0.1} min={0.00001} max={100000} decimals={2} id="zFar" class="value"/>
			</hui-element>
			<hui-element class="horizontal">
				<hui-text("Min zoom distance") class="label"/>
				<hui-slider step={0.1} min={0} max={10} decimals={2} id="minZoom" class="value"/>
			</hui-element>
			<hui-element class="horizontal hidden">
				<hui-text("Speed") class="label"/>
				<hui-slider step={0.1} min={0} max={10} decimals={2} class="value"/>
			</hui-element>
		</hui-camera-settings-popup>

	public function new(ctrl : h3d.scene.CameraController, ?parent: h2d.Object) {
		super(parent);
		initComponent();

		camType.items = [ {label: "Classic", value: 0}, {label: "FPS", value: 1} ];
		camType.value = 0;
		// TODO : manage FPS camera controller (not implemented yet)

		var cam = ctrl.getScene().camera;
		fov.value = ctrl.fovY;
		fov.onValueChanged = (_) -> { @:privateAccess ctrl.fov(fov.value - cam.fovY); }
		zNear.value = cam.zNear;
		zNear.onValueChanged = (_) -> { cam.zNear = zNear.value; }
		zFar.value = cam.zFar;
		zFar.onValueChanged = (_) -> { cam.zFar = zFar.value; }
		minZoom.value = ctrl.minDistance;
		minZoom.onValueChanged = (_) -> { ctrl.minDistance = minZoom.value; }
	}
}

class HuiGridSettingsPopup extends HuiPopup {
	static var SRC =
		<hui-grid-settings-popup class="vertical">
			<hui-text("Snap settings") id="title"/>
			<hui-element class="horizontal">
				<hui-text("Grid Size") class="label"/>
				<hui-slider step={0.01} min={0} max={100} decimals={2} id="gridSize" class="value"/>
			</hui-element>
			<hui-element class="horizontal">
				<hui-text("Force On Grid") class="label"/>
				<hui-checkbox id="forceOnGrid" class="value"/>
			</hui-element>
		</hui-grid-settings-popup>

	public function new(prefabEditor: HuiPrefabEditor, ?parent: h2d.Object) {
		super(parent);
		initComponent();

		forceOnGrid.value = prefabEditor.gizmoForceSnapOnGrid;
		forceOnGrid.onValueChanged = () -> {
			prefabEditor.gizmoForceSnapOnGrid = forceOnGrid.value;
		}

		gridSize.value = prefabEditor.gizmoSnapStep;
		gridSize.onValueChanged = (_) -> {
			prefabEditor.gizmoSnapStep = gridSize.value;
			@:privateAccess prefabEditor.grid.lineSpacing = gridSize.value;
		};
	}
}

class HuiHelpPopup extends HuiPopup {
	static var SRC =
		<hui-help-popup class="vertical">
			<hui-text("Shortcuts") id="title"/>
			<hui-element class="vertical" id="commands-container">
			</hui-element>
		</hui-help-popup>

	public function new(registeredCommands : Array<hrt.ui.HuiElement.RegisteredCommand>, ?parent: h2d.Object) {
		super(parent);
		initComponent();

		for (c in registeredCommands) {
			var container = new HuiElement(commandsContainer);
			container.dom.addClass("horizontal");
			var label = new HuiText(c.command.display, container);
			label.dom.addClass("label");
			new HuiText((c.command.registeredShortcut.alt ? "Alt-" : "") +
			(c.command.registeredShortcut.shift ? "Shift-" : "") +
			(c.command.registeredShortcut.ctrl ? "Ctrl-" : "") +
			hxd.Key.getKeyName(c.command.registeredShortcut.key), container);
		}
	}
}

#end
package hrt.ui;

#if hui
class HuiToolbar extends HuiElement {
	static var SRC = <hui-toolbar>
	</hui-toolbar>

	var widgets : Array<HuiElement>;

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
		this.makeInteractive();
	}

	public function addWidget(widget : HuiElement) {
		this.addChild(widget);
	}
}

class HuiTransformWidgets extends HuiElement {
	static var SRC = <hui-transform-widgets>
		<hui-toggle class="group-start" id="translationBtn">
			<hui-icon("translation")/>
		</hui-toggle>
		<hui-toggle class="group" id="rotationBtn">
			<hui-icon("rotation")/>
		</hui-toggle>
		<hui-toggle class="group-end" id="scaleBtn">
			<hui-icon("scale")/>
		</hui-toggle>
		<hui-button id="transform-space-btn">
			<hui-icon("world") id="transform-space-icon"/>
		</hui-button>
	</hui-transform-widgets>

	public function new(gizmo : hrt.tools.Gizmo, ?parent: h2d.Object) {
		super(parent);
		initComponent();

		translationBtn.toggled = true;
		translationBtn.onClick = (_) -> { gizmo?.translationMode(); };
		rotationBtn.onClick = (_) -> { gizmo?.rotationMode(); };
		scaleBtn.onClick = (_) -> { gizmo?.scalingMode(); };

		gizmo.onChangeMode = (mode) -> {
			translationBtn.toggled = mode.match(Translation);
			rotationBtn.toggled = mode.match(Rotation);
			scaleBtn.toggled = mode.match(Scale);
		}

		transformSpaceBtn.onClick = (_) -> {
			gizmo.isLocalTransform = !gizmo?.isLocalTransform;
			gizmo.updateTransformSpace();
		};

		gizmo.onChangeTransformSpace = (isLocalTransform) -> {
			transformSpaceIcon.setIcon(isLocalTransform ? "local" : "world");
		}
	}
}

class SnapWidget extends HuiElement {
	static var SRC = <snap-widget>
		<hui-toggle class="group-start" id="snap-btn">
			<hui-icon("grid-magnet")/>
		</hui-toggle>
		<hui-button class="grup-end tiny" id="snap-popup-btn">
			<hui-icon("dropDown")/>
		</hui-button>
	</snap-widget>

	public function new(editor: HuiPrefabEditor, ?parent : h2d.Object) {
		super(parent);
		initComponent();

		snapBtn.toggled = editor.gizmoShouldSnap;
		snapBtn.onClick = (_) -> {
			editor.gizmoShouldSnap = !editor.gizmoShouldSnap;
			snapBtn.toggled = editor.gizmoShouldSnap;
		}

		snapPopupBtn.onClick = (_) -> {
			uiBase.addPopup(new hrt.ui.HuiToolbar.HuiGridSettingsPopup(editor), { object: Element(snapPopupBtn), directionX: StartInside, directionY: EndOutside });
		}
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
			<hui-element class="horizontal" id="zoom-distance">
				<hui-text("Min zoom distance") class="label"/>
				<hui-slider step={0.1} min={0} max={10} decimals={2} id="minZoom" class="value"/>
			</hui-element>
			<hui-element class="horizontal" id="speed">
				<hui-text("Speed") class="label"/>
				<hui-slider step={0.1} min={0} max={10} decimals={2} class="value"/>
			</hui-element>
		</hui-camera-settings-popup>

	public function new(editor : HuiPrefabEditor, ?parent: h2d.Object) {
		super(parent);
		initComponent();

		var s3d = @:privateAccess editor.scene.s3d;

		camType.items = [ {label: "Orbital", value: 0}, {label: "FPS", value: 1} ];
		camType.value = h3d.scene.CameraController.getCameraControllerClassIdx(@:privateAccess editor.cameraController);
		camType.onValueChanged = () -> {
			@:privateAccess editor.cameraController = switch (camType.value) {
				case 0:
					new h3d.scene.CameraController.OrbitCameraController(s3d);
				case 1:
					new h3d.scene.CameraController.FPSCameraController(s3d);
				default:
					null;
			};

			hide.Ide.inst.currentConfig.set(hide.view.Prefab.CAM_CTRL_CONFIG_KEY,  h3d.scene.CameraController.getCameraControllerClassIdx(@:privateAccess editor.cameraController));

			@:privateAccess editor.cameraController.loadFromCamera();
			zoomDistance.dom.toggleClass("hidden", camType.value != 0);
			speed.dom.toggleClass("hidden", camType.value != 1);
		};

		zoomDistance.dom.toggleClass("hidden", camType.value != 0);
		speed.dom.toggleClass("hidden", camType.value != 1);

		var cam = s3d.camera;
		var ctrl = @:privateAccess editor.cameraController;

		fov.value = ctrl.fovY;
		fov.onValueChanged = (_) -> { @:privateAccess ctrl.wantedFOV = fov.value; }
		zNear.value = cam.zNear;
		zNear.onValueChanged = (_) -> { cam.zNear = zNear.value; }
		zFar.value = cam.zFar;
		zFar.onValueChanged = (_) -> { cam.zFar = zFar.value; }

		var orbitCtrl = Std.downcast(ctrl, h3d.scene.CameraController.OrbitCameraController);
		if (orbitCtrl != null) {
			minZoom.value = orbitCtrl.minDistance;
			minZoom.onValueChanged = (_) -> { orbitCtrl.minDistance = minZoom.value; }
		}
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
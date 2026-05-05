package hrt.ui;
import h3d.scene.pbr.Renderer;

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

class HuiSnapWidget extends HuiElement {
	static var SRC = <hui-snap-widget>
		<hui-toggle class="group-start" id="snap-btn">
			<hui-icon("grid-magnet")/>
		</hui-toggle>
		<hui-button class="group-end tiny" id="snap-popup-btn">
			<hui-icon("dropDown")/>
		</hui-button>
	</hui-snap-widget>

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

class HuiVisibilityWidget extends HuiElement {
	static var SRC = <hui-visibility-widget>
		<hui-toggle class="group-start" id="visibility-btn">
			<hui-icon("visibility")/>
		</hui-toggle>
		<hui-button class="group-end tiny" id="visibility-popup-btn">
			<hui-icon("dropDown")/>
		</hui-button>
	</hui-visibility-widget>

	public function new(editor: HuiPrefabEditor, ?parent : h2d.Object) {
		super(parent);
		initComponent();

		visibilityBtn.toggled = hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_OVERLAY_CONFIG_KEY, true);
		visibilityBtn.onClick = (_) -> {
			visibilityBtn.toggled = !visibilityBtn.toggled;
			hide.Ide.inst.currentConfig.set(hide.view.Prefab.VISIBILITY_OVERLAY_CONFIG_KEY, visibilityBtn.toggled);
			editor.updateDebugOverlayVisibility();
		}

		visibilityPopupBtn.onClick = (_) -> {
			uiBase.addPopup(new hrt.ui.HuiToolbar.HuiVisibilitySettingsPopup(editor), { object: Element(this), directionX: StartInside, directionY: EndOutside });
		}
	}
}

class HuiVisibilitySettingsPopup extends HuiPopup {
	static var SRC =
		<hui-visibility-settings-popup class="vertical">
			<hui-text("Visibility settings") class="title"/>
			<hui-text("Guides") class="sub-title"/>
			<hui-element class="horizontal">
				<hui-toggle id="grid-tog">
					<hui-icon("grid")/>
				</hui-toggle>
				<hui-text("Grid") class="label"/>
			</hui-element>
			<hui-element class="horizontal">
				<hui-toggle id="bone-tog">
					<hui-icon("bone")/>
				</hui-toggle>
				<hui-text("Joints") class="label"/>
			</hui-element>
			<hui-element class="horizontal">
				<hui-toggle id="collider-tog">
					<hui-icon("local")/>
				</hui-toggle>
				<hui-text("Colliders") class="label"/>
			</hui-element>
			<hui-element class="horizontal">
				<hui-toggle id="misc-tog">
					<hui-icon("question_mark")/>
				</hui-toggle>
				<hui-text("Others") class="label"/>
			</hui-element>

			<hui-text("Sélection") class="sub-title"/>
			<hui-element class="horizontal">
				<hui-toggle id="gizmo-tog">
					<hui-icon("translation")/>
				</hui-toggle>
				<hui-text("Gizmo") class="label"/>
			</hui-element>
			<hui-element class="horizontal">
				<hui-toggle id="outline-tog">
					<hui-icon("question_mark")/>
				</hui-toggle>
				<hui-text("Outline") class="label"/>
			</hui-element>

			<hui-text("Debug") class="sub-title"/>
			<hui-element class="horizontal">
				<hui-toggle id="scene-info-tog">
					<hui-icon("info")/>
				</hui-toggle>
				<hui-text("Scene info") class="label"/>
			</hui-element>
			<hui-element class="horizontal">
				<hui-toggle id="wireframe-tog">
					<hui-icon("grid")/>
				</hui-toggle>
				<hui-text("Wireframe") class="label"/>
			</hui-element>
			<hui-element class="horizontal">
				<hui-toggle id="disable-scene-tog">
					<hui-icon("visibility_off")/>
				</hui-toggle>
				<hui-text("Disable Scene Render") class="label"/>
			</hui-element>

			<hui-text("Icons") class="sub-title"/>
			<hui-element class="horizontal">
				<hui-toggle>
					<hui-icon("visibility")/>
				</hui-toggle>
				<hui-text("3D Icons") class="label"/>
			</hui-element>
		</hui-visibility-settings-popup>

	public function new(editor : HuiPrefabEditor, ?parent: h2d.Object) {
		super(parent);
		initComponent();

		var s3d = @:privateAccess editor.scene.s3d;

		gridTog.toggled = @:privateAccess editor.grid.visible;
		gridTog.onClick = (_) -> {
			@:privateAccess editor.grid.visible = @:privateAccess !editor.grid.visible;
			gridTog.toggled = !gridTog.toggled;
			hide.Ide.inst.currentConfig.set(hide.view.Prefab.VISIBILITY_GRID_CONFIG_KEY, @:privateAccess editor.grid.visible);
		}

		boneTog.toggled = hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_JOINTS_CONFIG_KEY, true);
		boneTog.onClick = (_) -> {
			boneTog.toggled = !boneTog.toggled;
			editor.setJointsDebugVisibility(boneTog.toggled);
			hide.Ide.inst.currentConfig.set(hide.view.Prefab.VISIBILITY_JOINTS_CONFIG_KEY, boneTog.toggled);
		}

		colliderTog.toggled = hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_COLLIDERS_CONFIG_KEY, true);
		colliderTog.onClick = (_) -> {
			colliderTog.toggled = !colliderTog.toggled;
			editor.setColliderDebugVisibility(colliderTog.toggled);
			hide.Ide.inst.currentConfig.set(hide.view.Prefab.VISIBILITY_COLLIDERS_CONFIG_KEY, colliderTog.toggled);
		}

		miscTog.toggled = hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_MISC_CONFIG_KEY, true);
		miscTog.onClick = (_) -> {
			miscTog.toggled = !miscTog.toggled;
			editor.setMiscDebugVisibility(miscTog.toggled);
			hide.Ide.inst.currentConfig.set(hide.view.Prefab.VISIBILITY_MISC_CONFIG_KEY, miscTog.toggled);
		}

		gizmoTog.toggled = hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_GIZMO_CONFIG_KEY, true);
		gizmoTog.onClick = (_) -> {
			gizmoTog.toggled = !gizmoTog.toggled;
			@:privateAccess editor.gizmo.setVisible(gizmoTog.toggled);
			hide.Ide.inst.currentConfig.set(hide.view.Prefab.VISIBILITY_GIZMO_CONFIG_KEY, gizmoTog.toggled);
		}

		outlineTog.toggled = hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_OUTLINE_CONFIG_KEY, true);
		outlineTog.onClick = (_) -> {
			outlineTog.toggled = !outlineTog.toggled;
			editor.setOutlineVisibility(outlineTog.toggled);
			hide.Ide.inst.currentConfig.set(hide.view.Prefab.VISIBILITY_OUTLINE_CONFIG_KEY, outlineTog.toggled);
		}

		sceneInfoTog.toggled = hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_SCENE_INFOS_CONFIG_KEY, true);
		sceneInfoTog.onClick = (_) -> {
			sceneInfoTog.toggled = !sceneInfoTog.toggled;
			editor.setSceneInfoVisibility(sceneInfoTog.toggled);
			hide.Ide.inst.currentConfig.set(hide.view.Prefab.VISIBILITY_SCENE_INFOS_CONFIG_KEY, sceneInfoTog.toggled);
		}

		wireframeTog.toggled = hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_WIREFRAME_CONFIG_KEY, true);
		wireframeTog.onClick = (_) -> {
			wireframeTog.toggled = !wireframeTog.toggled;
			editor.setWireframeVisibility(wireframeTog.toggled);
			hide.Ide.inst.currentConfig.set(hide.view.Prefab.VISIBILITY_WIREFRAME_CONFIG_KEY, wireframeTog.toggled);
		}

		disableSceneTog.toggled = hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_DISABLE_SCENE_RENDER_CONFIG_KEY, false);
		disableSceneTog.onClick = (_) -> {
			disableSceneTog.toggled = !disableSceneTog.toggled;
			editor.setSceneVisibility(!disableSceneTog.toggled);
			hide.Ide.inst.currentConfig.set(hide.view.Prefab.VISIBILITY_DISABLE_SCENE_RENDER_CONFIG_KEY, disableSceneTog.toggled);
		}
	}
}

class HuiViewModesWidget extends HuiElement {
	static var SRC = <hui-view-modes-widget>
		<hui-button id="btn">
			<hui-text("View Modes")/>
			<hui-icon("dropDown")/>
		</hui-button>
	</hui-view-modes-widget>

	var currentMode = 0;
	public function new(s3d: h3d.scene.Scene, ?parent : h2d.Object) {
		super(parent);
		initComponent();

		btn.onClick = (_) -> {
			var renderer = Std.downcast(@:privateAccess s3d.renderer, h3d.scene.pbr.Renderer);
			if (renderer != null) {
				uiBase.addPopup(new hrt.ui.HuiToolbar.HuiViewModesPopup(this, s3d), { object: Element(this), directionX: StartInside, directionY: EndOutside });
			}
		}
	}
}

@:access(h3d.scene.pbr.Renderer)
class HuiViewModesPopup extends HuiPopup {
	static var SRC =
		<hui-view-modes-popup class="vertical">
			<hui-text("View Modes") class="title"/>
			for (idx => m in modes) {
				<hui-element class="horizontal">
					<hui-checkbox id="cb[]" onValueChanged={() -> { updateChecked(cb[idx]); m.enable(renderer); }}/>
					<hui-text(m.label) class="label"/>
				</hui-element>
			}
		</hui-view-modes-popup>

	var modes : Array<Dynamic> = [];
	var currentMode : Int = 0;
	var widget : HuiViewModesWidget;
	var s3d : h3d.scene.Scene;

	public function new(widget : HuiViewModesWidget, s3d : h3d.scene.Scene, ?parent: h2d.Object) {
		super(parent);
		this.s3d = s3d;
		this.widget = widget;
		var renderer = @:privateAccess s3d.renderer;

		modes =  [
			{ label : "LIT", enable : (renderer : Renderer) -> { renderer.displayMode = Pbr; }},
			{ label : "Full", enable : (renderer : Renderer) -> { renderer.displayMode = Debug; renderer.slides.shader.mode = Full; }},
			{ label : "Albedo", enable : (renderer : Renderer) -> { renderer.displayMode = Debug; renderer.slides.shader.mode = Albedo; }},
			{ label : "Normal", enable : (renderer : Renderer) -> { renderer.displayMode = Debug; renderer.slides.shader.mode = Normal; }},
			{ label : "Roughness", enable : (renderer : Renderer) -> { renderer.displayMode = Debug; renderer.slides.shader.mode = Roughness; }},
			{ label : "Metalness", enable : (renderer : Renderer) -> { renderer.displayMode = Debug; renderer.slides.shader.mode = Metalness; }},
			{ label : "Emissive", enable : (renderer : Renderer) -> { renderer.displayMode = Debug; renderer.slides.shader.mode = Emissive; }},
			{ label : "AO", enable : (renderer : Renderer) -> { renderer.displayMode = Debug; renderer.slides.shader.mode = AO; }},
			{ label : "Shadows", enable : (renderer : Renderer) -> { renderer.displayMode = Debug; renderer.slides.shader.mode = Shadow; }},
			{ label : "Performance", enable : (renderer : Renderer) -> { renderer.displayMode = Performance; }},
			{ label : "UV Checker", disable : () -> { setUVChecker(false); }, enable : (renderer : Renderer) -> { renderer.displayMode = Pbr; renderer.slides.shader.mode = Normal; setUVChecker(true); }}
		];

		initComponent();
		@:privateAccess currentMode = widget.currentMode;
		cb[currentMode].value = true;
	}

	function updateChecked(checkbox : HuiCheckbox) {
		cb[currentMode].value = false;
		if (modes[currentMode].disable != null)
			modes[currentMode].disable();
		@:privateAccess widget.currentMode = currentMode = cb.indexOf(checkbox);
		cb[currentMode].value = true;
	}

	function setUVChecker(enable : Bool) {
		function checkUV(obj: h3d.scene.Object) {
			var mesh = Std.downcast(obj, h3d.scene.Mesh);
			if (mesh != null && mesh.primitive != null && mesh.primitive.buffer != null &&
				!mesh.primitive.buffer.isDisposed() &&
				mesh.primitive.buffer.format != null &&
				mesh.primitive.buffer.format.getInput("uv") != null) {
				for (mat in mesh.getMaterials(null, false)) {
					if (enable) {
						if (mat.mainPass.getShader(h3d.shader.Checker) == null)
							mat.mainPass.addShader(new h3d.shader.Checker());
					} else {
					var s = mat.mainPass.getShader(h3d.shader.Checker);
					if (s != null)
						mat.mainPass.removeShader(s);
					}
				}
			}
			for (idx in 0...obj.numChildren)
				checkUV(obj.getChildAt(idx));
		}

		checkUV(s3d);
	}
}

class HuiCameraSettingsPopup extends HuiPopup {
	static var SRC =
		<hui-camera-settings-popup class="vertical">
			<hui-text("Camera settings") class="title"/>
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
			<hui-text("Snap settings") class="title"/>
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
			<hui-text("Shortcuts") class="title"/>
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
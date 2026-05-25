package hrt.ui;

#if hui
class HuiSceneEditor extends HuiElement {
	static var SRC =
		<hui-scene-editor>
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
		</hui-scene-editor>

	static final RENDER_PROPS_SAVE_KEY = "renderPropsPath";
	static public var focusCommand = new hrt.ui.HuiCommands.HuiCommand("Focus Selection", {key: hxd.Key.F});

	public var tree :  hrt.ui.HuiTree<Dynamic>;
	var inspectorRoot : hide.kit.KitRoot;
	var cameraController : h3d.scene.CameraController;

	// public var renderPropsPath(get, never) : Null<String>; /**Null if the renderProps is in the scene**/
	var renderProps: hrt.prefab.Prefab;
	// function get_renderPropsPath() : Null<String> {
	// 	if (renderProps == null)
	// 		return null;
	// 	if (renderProps.getRoot(true) == prefab)
	// 		return null;
	// 	return renderProps.shared.currentPath;
	// }

	// Gizmos and guides
	var grid : hrt.tools.Grid = null;
	var viewportAxis : hrt.tools.ViewportAxis = null;
	var outline : hrt.prefab.rfx.Outline;

	// Debugs
	var debugGraph: h2d.Graphics;
	var rootDebugCollider : h3d.scene.Object = null;

	public var gizmoSnapStep(default, set) : Float = 1.0;
	public function set_gizmoSnapStep(v : Float) {
		hide.Ide.inst.currentConfig.set(hide.view.Prefab.GIZMO_SNAP_STEP_CONFIG_KEY, v);
		return gizmoSnapStep = v;
	}

	override function new(?parent) {
		super(parent);
		initComponent();

		tree = new hrt.ui.HuiTree<hrt.prefab.Prefab>(panelTree);

		var env = new h3d.scene.pbr.Environment(getEnvMap());
		env.compute();

		scene.s3d.renderer?.dispose();
		scene.s3d.renderer = new hide.Renderer.PbrRenderer(env);

		scene.s3d.lightSystem?.dispose();
		scene.s3d.lightSystem = new h3d.scene.pbr.LightSystem();

		scene.s3d.addEventListener(onSceneEvents);

		makeRenderProps();

		var ctrlClass = h3d.scene.CameraController.getCameraControllersClass()[hide.Ide.inst.currentConfig.get(hide.view.Prefab.CAM_CTRL_CONFIG_KEY, 0)];
		cameraController = Type.createInstance(ctrlClass, []);
		scene.s3d.addChild(cameraController);

		try {
			load();
		} catch(e) {
			remove();
			var error = 'Couldn\'t load $e';
			hide.Ide.showError(error);
			new HuiText(error, this);
		}

		outline = new hrt.prefab.rfx.Outline(null, null);
		outline.outlineColor = 0xFF6600;
		scene.s3d.renderer.effects.push(outline);

		makeGizmos();
		updateDebugOverlayVisibility();
	}

	public function getObjectsAt(sx : Int, sy : Int, ?root : h3d.scene.Object, ?f : h3d.scene.Object -> Bool) {
		var hits : Array<{ o : h3d.scene.Object, d : Float }> = [];
		var r = root ?? scene.s3d;
		var ray = scene.s3d.camera.rayFromScreen(sx, sy, cast scene.calculatedWidth, cast scene.calculatedHeight);
		for (o in r.findAll((o) -> o)) {
			var c = o.getCollider() ?? o.getBounds();
			if (c == null)
				continue;

			var dist = c.rayIntersection(ray, true);
			if ((f != null && f(o)) && dist >= 0) {
				var added = false;
				for (idx in 0...hits.length) {
					if (hits[idx].d > dist) {
						hits.insert(idx, { o: o, d : dist });
						added = true;
						break;
					}
				}

				if (!added)
					hits.push({ o: o, d : dist });
			}
		}

		return [for (h in hits) h.o];
	}

	public function updateDebugOverlayVisibility() {
		var visibility = hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_OVERLAY_CONFIG_KEY, true);

		grid.visible = visibility && hide.Ide.inst.currentConfig.get(hide.view.Prefab.VISIBILITY_GRID_CONFIG_KEY, true);
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

			var root3d = scene.s3d;
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
				if (@:privateAccess grid.plane == mesh)
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


	public function getRenderPropsPaths() : Array<{name: String, value: String}> {
		var renderProps = getConfig()?.getLocal("scene.renderProps");
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

	public function checkRemakeRenderProps(changedPrefab: hrt.prefab.Prefab = null) : Bool {
		if (changedPrefab != null) {
			if (changedPrefab.findParent(hrt.prefab.RenderProps) == renderProps) {
				makeRenderProps();
				return true;
			}
		}
		// if (prefab.find(hrt.prefab.RenderProps) != renderProps) {
		// 	makeRenderProps();
		// 	return true;
		// }
		return false;
	}

	public function makeRenderProps() {
		var paths = getRenderPropsPaths();

		// removePrefabInstance(renderProps);
		// renderProps = null;

		// var prefabRenderProp = prefab.find(hrt.prefab.RenderProps, (p) -> p.enabled);
		// if (prefabRenderProp != null) {
		// 	renderProps = prefabRenderProp;
		// 	if (tryMake(renderProps)) {
		// 		updateRenderPropsInternal();
		// 		return;
		// 	}
		// }

		var candidates: Array<hrt.prefab.Prefab> = [];

		for (path in paths) {
			var currentPath = getDisplayState(RENDER_PROPS_SAVE_KEY, "");
			var prefab = hxd.res.Loader.currentInstance.load(path.value).toPrefab().load().clone();
			if (path.value == currentPath)
				candidates.unshift(prefab);
			else
				candidates.push(prefab);
		}

		// for (candidate in candidates) {
		// 	renderProps = candidate;
		// 	if (tryMake(renderProps)) {
		// 		updateRenderPropsInternal();
		// 		break;
		// 	}
		// 	removePrefabInstance(renderProps);
		// 	renderProps = null;
		// }
	}

	public function focusSelection() {
		focusObjects(getSelectedObjects());
	}

	public function focusObjects(objs : Array<h3d.scene.Object>) {
		if (objs == null || objs.length < 0)
			return;
		var bnds = new h3d.col.Bounds();
		var centroid = new h3d.Vector();
		for(obj in objs) {
			centroid = centroid.add(obj.getAbsPos().getPosition());
			bnds.add(obj.getBounds());
		}
		if (!bnds.isEmpty()) {
			var s = bnds.toSphere();
			var r = s.r * 4.0;
			cameraController.set(r, null, null, s.getCenter());
		} else {
			centroid.scale(1.0 / objs.length);
			cameraController.set(centroid.toPoint());
		}
	}

	function makeGizmos() {
		this.gizmoSnapStep = hide.Ide.inst.currentConfig.get(hide.view.Prefab.GIZMO_SNAP_STEP_CONFIG_KEY, 1.0);
		grid?.remove();
		viewportAxis?.remove();

		viewportAxis = new hrt.tools.ViewportAxis(scene.s3d.camera, cameraController, scene.s2d);

		grid = new hrt.tools.Grid(scene.s3d);
		grid.lineSpacing = this.gizmoSnapStep;

		registerCommand(focusCommand, View, () -> focusSelection());
	}

	function getEnvMap() {
		var env = getConfig()?.get("scene.environment") ?? "";
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

	function resetCamera() {
		cameraController.set(20.0);
		var objs = [for (o in @:privateAccess scene.s3d.children) o];
		focusObjects(objs);
	}

	public function gizmoSnap(v: Float, mode: hrt.tools.Gizmo.EditMode) {
		return hxd.Math.round(v / this.gizmoSnapStep) * this.gizmoSnapStep;
	}

	public function setRenderPropsPath(newPath: String) : Void {
		// if (newPath == renderPropsPath)
		// 	return;
		saveDisplayState(RENDER_PROPS_SAVE_KEY, newPath);
		makeRenderProps();
	}

	public function updateRenderProps() {
		if (!checkRemakeRenderProps()) {
			updateRenderPropsInternal();
		}
	}

	function updateRenderPropsInternal() {
		var trueRenderProps = renderProps.find(hrt.prefab.RenderProps);
		if (trueRenderProps != null)
			trueRenderProps.applyProps(scene.s3d.renderer);
	}


	function onSceneEvents(e: hxd.Event) : Void {
		switch (e.kind) {
			case EMove:
				onSceneMove(e);
			case EPush:
				onScenePush(e);
			default:
		}
	}

	public dynamic function onScenePush(e: hxd.Event) {}
	public dynamic function onSceneMove(e: hxd.Event) {}
	public dynamic function getSelectedObjects() : Array<h3d.scene.Object> { return []; }
	public dynamic function load() {}
	public dynamic function getConfig() : hide.Config { return null; }
}
#end
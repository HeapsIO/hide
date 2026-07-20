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

			<hui-error-display id="critical-error" public/>
		</hui-scene-editor>

	public static var CAM_CTRL_CONFIG_KEY = "editor.camera.type";

	public static final VISIBILITY_OVERLAY_CONFIG_KEY = "editor.visibility.overlay";
	public static final VISIBILITY_GRID_CONFIG_KEY = "editor.visibility.grid";
	public static final VISIBILITY_JOINTS_CONFIG_KEY = "editor.visibility.joints";
	public static final VISIBILITY_COLLIDERS_CONFIG_KEY = "editor.visibility.colliders";
	public static final VISIBILITY_MISC_CONFIG_KEY = "editor.visibility.misc";
	public static final VISIBILITY_GIZMO_CONFIG_KEY = "editor.visibility.gizmo";
	public static final VISIBILITY_OUTLINE_CONFIG_KEY = "editor.visibility.outline";
	public static final VISIBILITY_SCENE_INFOS_CONFIG_KEY = "editor.visibility.sceneInfos";
	public static final VISIBILITY_WIREFRAME_CONFIG_KEY = "editor.visibility.wireframe";
	public static final VISIBILITY_DISABLE_SCENE_RENDER_CONFIG_KEY = "editor.visibility.disableSceneRender";
	public static final RENDER_PROPS_SAVE_KEY = "renderPropsPath";
	public static var RENDER_PROPS_KEY = "scene.renderProps";

	static public var focusCommand = new hrt.ui.HuiCommands.HuiCommand("Focus Selection", {key: hxd.Key.F});

	public var tree :  hrt.ui.HuiTree<Dynamic>;
	var inspectorRoot : hide.kit.KitRoot;
	var cameraController : h3d.scene.CameraController;
	public var lastFocusObjects : Array<h3d.scene.Object> = [];

	var renderProps : hrt.prefab.RenderProps;

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

		var ctrlClass = h3d.scene.CameraController.getCameraControllersClass()[hide.Ide.inst.currentConfig.get(hrt.ui.HuiSceneEditor.CAM_CTRL_CONFIG_KEY, 0)];
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

	public static function getMaterialLibraries(path : String) {
		var config = hide.Config.loadForFile(hide.Ide.inst, path);

		var matLibs : Array<Dynamic> = config.get("materialLibraries");
		if( matLibs == null ) matLibs = [];

		if (matLibs.length > 0) {
			for (idx in 0...matLibs.length) {
				var m = Std.isOfType(matLibs[idx], String) ? cast (matLibs[idx]) : null;
				if (m == null)
					continue;
				matLibs[idx] = { name : m.substring(m.lastIndexOf("/") + 1), path : m };
			}
		}

		return matLibs;
	}

	public static function getMaterialsFromLibrary(path : String, library : String) : Array<{ path: String, mat: hrt.prefab.Material }> {
		var libraries = getMaterialLibraries(path);
		var lPath = "";
		for (l in libraries) {
			if (l.name == library) {
				lPath = l.path;
				break;
			}
		}

		if (lPath == "")
			return [];

		var materials = [];
		function pathRec(p : String) {
			try {
				var prefab = hxd.res.Loader.currentInstance.load(p).toPrefab().load();
				var mats = prefab.findAll(hrt.prefab.Material);
				for ( m in mats )
					materials.push({ path : p, mat : m});
			} catch ( e : hxd.res.NotFound ) {
				hide.Ide.showError('Material library ${p} not found, please update props.json');
			}
		}

		pathRec(lPath);

		materials.sort((m1, m2) -> { return (m1.mat.name > m2.mat.name ? 1 : -1); });
		return materials;
	}

	public function setCriticalError(title: String, exception: haxe.Exception) {
		dom.addClass("critical-error");
		criticalError.setError(title, exception);
	}

	public function getObjectsAt(sx : Int, sy : Int, ?root : h3d.scene.Object, ?f : h3d.scene.Object -> Bool) {
		var hits : Array<{ o : h3d.scene.Object, d : Float }> = [];
		var r = root ?? scene.s3d;
		var ray = scene.s3d.camera.rayFromScreen(sx, sy, scene.sceneWidth, scene.sceneHeight);
		for (o in r.findAll((o) -> o)) {
			var c = try o.getCollider() ?? o.getBounds()  catch(e) null;
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

	public function projectToGround(ray: h3d.col.Ray, ?paintOn : hrt.prefab.Prefab, ignoreTerrain: Bool = false) : Float {
		var minDist = -1.;
		// if (!ignoreTerrain) {
		// 	var arr = (paintOn == null ? getGroundPrefabs() : [paintOn]);
		// 	for( elt in arr ) {
		// 		var obj = Std.downcast(elt, Object3D);
		// 		if( obj == null ) continue;

		// 		var local3d = obj.findFirstLocal3d();
		// 		if (local3d == null) continue;
		// 		var lray = ray.clone();
		// 		lray.transform(local3d.getInvPos());
		// 		var dist = obj.localRayIntersection(lray);
		// 		if( dist > 0 ) {
		// 			var pt = lray.getPoint(dist);
		// 			pt.transform(local3d.getAbsPos());
		// 			var dist = pt.sub(ray.getPos()).length();
		// 			if( minDist < 0 || dist < minDist )
		// 				minDist = dist;
		// 		}
		// 	}
		// 	if( minDist >= 0 )
		// 		return minDist;
		// }

		var zPlane = if (ray.lz > 0) {
			h3d.col.Plane.Z(ray.pz <= 0 ? 0 : ray.pz + 10);
		}
		else {
			h3d.col.Plane.Z(ray.pz >= 0 ? 0 : ray.pz - 10);
		}
		var pt = ray.intersect(zPlane);
		if( pt != null ) {
			minDist = pt.sub(ray.getPos()).length();
			var dirToPt = pt.sub(ray.getPos());
			if( dirToPt.dot(ray.getDir()) < 0 )
				return -1.0;
		}

		return minDist;
	}

	public function screenToGround(sx: Float, sy: Float, ?paintOn : hrt.prefab.Prefab, ignoreTerrain: Bool = false) {
		var camera = scene.s3d.camera;
		var ray = camera.rayFromScreen(sx, sy, scene.sceneWidth, scene.sceneHeight);
		var dist = projectToGround(ray, paintOn, ignoreTerrain);
		if(dist >= 0) {
			return ray.getPoint(dist);
		}
		return null;
	}

	public function updateDebugOverlayVisibility() {
		var visibility = hide.Ide.inst.currentConfig.get(VISIBILITY_OVERLAY_CONFIG_KEY, true);

		grid.visible = visibility && hide.Ide.inst.currentConfig.get(VISIBILITY_GRID_CONFIG_KEY, true);
		setJointsDebugVisibility(visibility && hide.Ide.inst.currentConfig.get(VISIBILITY_JOINTS_CONFIG_KEY, true));
		setColliderDebugVisibility(visibility && hide.Ide.inst.currentConfig.get(VISIBILITY_COLLIDERS_CONFIG_KEY, true));
		setMiscDebugVisibility(visibility && hide.Ide.inst.currentConfig.get(VISIBILITY_COLLIDERS_CONFIG_KEY, true));
		setOutlineVisibility(visibility && hide.Ide.inst.currentConfig.get(VISIBILITY_OUTLINE_CONFIG_KEY, true));
		setSceneInfoVisibility(visibility && hide.Ide.inst.currentConfig.get(VISIBILITY_SCENE_INFOS_CONFIG_KEY, true));
		setWireframeVisibility(visibility && hide.Ide.inst.currentConfig.get(VISIBILITY_WIREFRAME_CONFIG_KEY, true));
		setSceneVisibility(!hide.Ide.inst.currentConfig.get(VISIBILITY_DISABLE_SCENE_RENDER_CONFIG_KEY, false));
	}

	@:access(h3d.scene.Skin)
	public dynamic function setJointsDebugVisibility(visible : Bool) {
		for (m in scene.s3d.getMeshes()) {
			var sk = Std.downcast(m,h3d.scene.Skin);
			if (sk != null)
				sk.showJoints = visible;
		}
	}

	public dynamic function setColliderDebugVisibility(visible : Bool) {
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

	public dynamic function setMiscDebugVisibility(visible : Bool) {
		if (scene?.s3d?.renderer == null)
			return;
		scene.s3d.renderer.showEditorGuides = visible;
	}

	public dynamic function setOutlineVisibility(visible : Bool) {
		if (scene?.s3d?.renderer == null)
			return;
		for (e in scene.s3d.renderer.effects)
			if (e == outline)
				e.enabled = visible;
	}

	public dynamic function setSceneInfoVisibility(visible : Bool) {
		#if editor_hl
		scene?.showSceneInfos = visible;
		#end
	}

	public dynamic function setWireframeVisibility(visible : Bool) {
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

	public dynamic function setSceneVisibility(visible : Bool) {
		scene.disableSceneRender = !visible;
	}


	public function setRenderProps(path : String) {
		if (renderProps != null && renderProps.shared.prefabSource == path)
			return;

		if (renderProps != null) {
			this.renderProps.local3d.remove();
			this.renderProps.remove();
		}

		var p = hxd.res.Loader.currentInstance.load(path).toPrefab().load().clone();
		renderProps = p.getOpt(hrt.prefab.RenderProps);
		if (renderProps == null)
			throw "This prefab has no render props";

		renderProps.make();
		scene.s3d.addChild(renderProps.local3d);
		renderProps.applyProps(scene.s3d.renderer);
	}

	public function getRenderPropsObj() {
		return scene.s3d.find((o) -> Std.downcast(o, hrt.prefab.RenderProps.RenderPropsObject));
	}

	public function updateRenderProps() {
		// Clear previous render props
		if (renderProps != null) {
			this.renderProps.local3d.remove();
			this.renderProps.remove();
			this.renderProps = null;
		}

		// If there is already a render props in the scene, just skip
		var sceneRenderProps = getRenderPropsObj();
		if (sceneRenderProps != null) {
			sceneRenderProps.prefab.applyProps(scene.s3d.renderer);
			return;
		}

		// If there is a config set for that prefab, just use it
 		var path = getView().getDisplayState(RENDER_PROPS_SAVE_KEY, null);
		if (path != null) {
			setRenderProps(path);
			return;
		}

		// If there is configs but none of it is set for that prefab, juste take the first
		var configs = getRenderPropsConfigs();
		if (configs != null && configs.length >= 1)
			setRenderProps(configs[0].value);
	}

	public function getRenderPropsConfigs() : Array<{ name: String, value: String }> {
		var renderProps = [];
		var renderPropsConfig = hide.Ide.inst.currentConfig.getLocal(RENDER_PROPS_KEY);
		if (renderPropsConfig is String) {
			renderProps.push({ name: cast (renderPropsConfig, String), value: cast (renderPropsConfig, String) });
		}

		if (renderPropsConfig is Array) {
			for (rpc in cast (renderPropsConfig, Array<Dynamic>)) {
				renderProps.push({ name: rpc.name, value: rpc.value });
			}
		}

		return renderProps;
	}


	public function focusSelection() {
		focusObjects(getSelectedObjects());
	}

	/**
		forceFocusChanged allow to control if the camera distance from the focus point should also change to
		see the whole bound of the object. If left null, the value will be determined using the last objs passed to
		this function
	**/
	public function focusObjects(objs : Array<h3d.scene.Object>, ?forceMoveCameraDistance: Bool) {
		if (objs == null || objs.length < 0)
			return;

		var focusChanged = false;
		if (forceMoveCameraDistance == null) {
			for (o in objs) {
				if (!lastFocusObjects.contains(o)) {
					focusChanged = true;
					break;
				}
			}
		} else {
			focusChanged = !forceMoveCameraDistance;
		}

		var bnds = new h3d.col.Bounds();
		var centroid = new h3d.Vector();
		for(obj in objs) {
			centroid = centroid.add(obj.getAbsPos().getPosition());
			bnds.add(obj.getBounds());
		}
		if (!bnds.isEmpty()) {
			var s = bnds.toSphere();
			var r = focusChanged ? null : s.r * 4.0;
			cameraController.set(r, null, null, s.getCenter());
		} else {
			centroid.scale(1.0 / objs.length);
			cameraController.set(centroid.toPoint());
		}
		lastFocusObjects = objs;
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
		cameraController.set(20.0, null, null, null, 25.);
		var objs = [for (o in @:privateAccess scene.s3d.children) o];
		focusObjects(objs, false);
		cameraController.toTarget();
	}

	public function gizmoSnap(v: Float, mode: hrt.tools.Gizmo.EditMode) {
		return hxd.Math.round(v / this.gizmoSnapStep) * this.gizmoSnapStep;
	}

	function onSceneEvents(e: hxd.Event) : Void {
		var oldX = e.relX;
		var oldY = e.relY;

		e.relX -= @:privateAccess scene.s3d.scenePosition?.offsetX;
		e.relY -= @:privateAccess scene.s3d.scenePosition?.offsetY;

		switch (e.kind) {
			case EMove:
				onSceneMove(e);
			case EPush:
				onScenePush(e);
			default:
		}

		e.relX = oldX;
		e.relY = oldY;
	}

	public dynamic function onScenePush(e: hxd.Event) {}
	public dynamic function onSceneMove(e: hxd.Event) {}
	public dynamic function getSelectedObjects() : Array<h3d.scene.Object> { return []; }
	public dynamic function load() {}
	public dynamic function getConfig() : hide.Config { return null; }
}
#end
package hrt.ui;

#if hui

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
					<hui-text("inspector")/>
				</hui-element>
			</hui-split-container>
		</hui-prefab-editor>

	var prefab: hrt.prefab.Prefab;
	var errorMessage : h2d.Text;
	var cameraController : h3d.scene.CameraController;
	var treePrefab: hrt.ui.HuiTree<hrt.prefab.Prefab>;

	var config : hide.Config;

	override function new(?parent) {
		super(parent);
		initComponent();

		errorMessage = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
		cameraController = new h3d.scene.CameraController(scene.s3d);

		treePrefab = new hrt.ui.HuiTree<hrt.prefab.Prefab>(panelTree);
		treePrefab.getItemChildren = treePrefabGetItemChildren;
		treePrefab.getItemName = (p: hrt.prefab.Prefab) -> p.name;
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
			prefab.shared.root2d.remove();
			prefab.shared.root3d.remove();
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
		scene.s3d.renderer = new hide.Renderer.PbrRenderer(env);
		scene.s3d.lightSystem = new h3d.scene.pbr.LightSystem();

		tryMake(prefab);
		makeRenderProps();

		focusObjects([for (i in 0...scene.s3d.numChildren) scene.s3d.getChildAt(i)]);
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
		if (prefab != null) {
			prefab.shared.root2d?.remove();
			prefab.shared.root3d?.remove();
		}
		errorMessage.text = "";

		@:privateAccess prefab.shared.root2d = prefab.shared.current2d = new h2d.Object(scene.s2d);
		@:privateAccess prefab.shared.root3d = prefab.shared.current3d = new h3d.scene.Object(scene.s3d);

		try {
			prefab.make();
		} catch (e) {
			prefab.shared.root2d?.remove();
			prefab.shared.root3d?.remove();

			errorMessage.text = "Error loading prefab : " + e;

			trace("Error loading prefab " + e);
			return false;
		}

		treePrefab.rebuild();
		return true;
	}

	public function makeRenderProps() {
		var paths = getRenderPropsPaths();
		for (path in paths) {
			var renderProp = hxd.res.Loader.currentInstance.load(path.value).toPrefab().load().clone();
			if (tryMake(renderProp))
				break;
		}
	}
}

#end
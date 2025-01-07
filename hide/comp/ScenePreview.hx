package hide.comp;

class ScenePreviewSettings {
    public var modelPath: String = null;

    public function new() {};
}

/**
	A Scene that is specialised to load one prefab or mesh for preview.
	Stores
**/
class ScenePreview extends Scene {
	var cameraController : hide.comp.Scene.PreviewCamController;
	var previewSettings : ScenePreviewSettings;

	public var prefab(default, null) : hrt.prefab.Prefab; // The root prefab of the preview.

	public function new(config, parent, el, save: String) {
		this.saveDisplayKey = save;
		super(config, parent, el);
	}

	/**
		Called whenever prefab is loaded. Prefab can be null if the loading failed
	**/
	public dynamic function onObjectLoaded() {

	}

	override function preOnReady() {
		super.preOnReady();

		loadSettings();

		cameraController = new hide.comp.Scene.PreviewCamController(s3d);

		reloadObject();
	}

	function saveSettings() {
		saveDisplayState("previewSettings", haxe.Json.stringify(previewSettings));
	}

	function loadSettings() {
		var save = haxe.Json.parse(getDisplayState("previewSettings") ?? "{}");
		previewSettings = new ScenePreviewSettings();
		for (f in Reflect.fields(previewSettings)) {
			var v = Reflect.field(save, f);
			if (v != null) {
				Reflect.setField(previewSettings, f, v);
			}
		}
	}

	public function resetPreviewCamera() {
		if (prefab == null)
			return;

		var bounds = prefab.findFirstLocal3d().getBounds();
		var sp = bounds.toSphere();
		cameraController.set(sp.r * 3.0, Math.PI / 4, Math.PI * 5 / 13, sp.getCenter());
	}

	/**
		Set the preview object path and reload the scene.
		If path is a .prefab, `this.prefab` will be the loaded prefab
		If path is a .fbx, `this.prefab` will be a hrt.prefab.Model with it's source = path
	**/
	public function setObjectPath(path: String) {
		previewSettings.modelPath = path;
		reloadObject();
	}

	public function getObjectPath() : String {
		return previewSettings.modelPath;
	}

	public function reloadObject() {
		if (prefab != null) {
			prefab.dispose();
			prefab.shared?.root3d.remove();
			prefab.shared?.root2d.remove();
			prefab = null;
		}

		if (previewSettings.modelPath == null || !hxd.res.Loader.currentInstance.exists(previewSettings.modelPath)) {
			previewSettings.modelPath = null;
			saveSettings();
			onObjectLoaded();
			return;
		}

		try {
			if (StringTools.endsWith(previewSettings.modelPath, ".prefab")) {
				try {
					prefab = Ide.inst.loadPrefab(previewSettings.modelPath);
				} catch (e) {
					throw 'Could not load mesh ${previewSettings.modelPath}, error : $e';
				}
			} else if (StringTools.endsWith(previewSettings.modelPath, ".fbx")) {
				var model = new hrt.prefab.Model(null, null);
				model.source = previewSettings.modelPath;
				prefab = model;
			}
			else {
				throw "Unsupported model format";
			}

			var previewObject = new h3d.scene.Object(s3d);
			var ctx = new hide.prefab.ContextShared(null, previewObject);
			ctx.scene = this;
			prefab = prefab.make(ctx);

		} catch (e) {
			previewSettings.modelPath = null;
			ide.quickError("Couldn't load preview : " + e);
			saveSettings();
			reloadObject(); // cleanup
			return;
		}

		onObjectLoaded();
	}
}
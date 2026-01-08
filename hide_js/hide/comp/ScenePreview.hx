package hide.comp;

class ScenePreviewSettings {
    public var modelPath: String = null;
	public var renderPropsPath: String = null;

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

	public function addToolbar() {
		var toolbar = new Element('
		<div class="hide-toolbar2">
			<div class="tb-group">
				<div class="button2 transparent" title="More options">
					<div class="ico ico-navicon"></div>
				</div>
			</div>
		</div>').appendTo(element);
		var menu = toolbar.find(".button2");

		menu.get(0).onclick = (e: js.html.MouseEvent) -> {
			var items : Array<hide.comp.ContextMenu.MenuItem> = [];

			var loadableMeshes = listLoadableMeshes();
			if (loadableMeshes.length > 0) {
				var loadableMeshesMenu : Array<hide.comp.ContextMenu.MenuItem> = [];
				for (mesh in loadableMeshes) {
					loadableMeshesMenu.push(
						{
							label: mesh.label,
							click: setObjectPath.bind(mesh.path),
							radio: ()-> mesh.path == previewSettings.modelPath,
							stayOpen: true,
						}
					);
				}
				items.push({label: "Preview Mesh", menu: loadableMeshesMenu});
			}

			var renderProps = listRenderProps();
			if (renderProps.length > 0) {
				var renderPropsMenu : Array<hide.comp.ContextMenu.MenuItem> = [];
				for (prop in renderProps) {
					renderPropsMenu.push({label: prop.name, click: () -> {
						previewSettings.renderPropsPath = prop.value;
						loadSavedRenderProps();
					}, radio: () -> prop.value == previewSettings.renderPropsPath, stayOpen: true});
				}
				items.push({label: "Render Props", menu: renderPropsMenu});
			}

			hide.comp.ContextMenu.createDropdown(menu.get(0), items);
		}
	}

	/**
		Called whenever prefab is loaded. Prefab can be null if the loading failed
	**/
	public dynamic function onObjectLoaded() {

	}

	public dynamic function listLoadableMeshes() : Array<{label: String, path: String}> {
		return [];
	}

	override function preOnReady() {
		super.preOnReady();

		loadSettings();
		loadSavedRenderProps();

		cameraController = new hide.comp.Scene.PreviewCamController(s3d);

		reloadObject();

		if (prefab == null) {
			var loadableMeshes = listLoadableMeshes();
			if (loadableMeshes.length > 0) {
				previewSettings.modelPath = loadableMeshes[0].path;
				reloadObject();
			}
		}
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

	function listRenderProps() : Array<{name: String, value: String}> {
		return listRenderPropsStatic(config);
	}

	static public function listRenderPropsStatic(config: hide.Config) : Array<{name: String, value: String}> {
		var renderProps = config.getLocal("scene.renderProps");
		var ret : Array<{name: String, value: String}> = [];

		if (renderProps is String) {
			ret.push({name: "default", value: renderProps});
		} else if (renderProps is Array) {
			var renderProps : Array<Dynamic> = cast renderProps;
			for (renderProp in renderProps) {
				ret.push({name: renderProp.name, value: renderProp.value});
			}
		}
		return ret;
	}

	function loadSavedRenderProps() {
		var path = null;
		var renderProps = listRenderProps();
		var rp = renderProps[0];
		for (prop in renderProps) {
			if (prop.value == previewSettings.renderPropsPath) {
				rp = prop;
			}
		}
		setRenderProps(rp?.value);
		previewSettings.renderPropsPath = rp?.value;
		saveSettings();
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
		saveSettings();
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
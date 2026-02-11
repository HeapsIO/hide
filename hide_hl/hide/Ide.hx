package hide;

class Ide extends hide.tools.IdeData {
	public static var inst : Ide;
	public var app : hide.App;

	static final localUserDataSave = "hidehl.json";

	public override function new() {
		super();
		inst = this;

		var cwd = Sys.getCwd();
		initConfig(cwd);

		loadLocalStorage();
	}

	var localStorage: Dynamic = {};
	var localStorageSaveQueued: Bool = false;

	public function saveLocalStorage(key: String, data: Dynamic) {
		Reflect.setField(localStorage, key, data);

		queueStorageSave();
	}

	function queueStorageSave() {
		if (!localStorageSaveQueued) {
		localStorageSaveQueued = true;
		hide.App.defer(() -> {
				sys.io.File.saveContent(appPath + "/" + localUserDataSave, haxe.Json.stringify(localStorage, "\t"));
				localStorageSaveQueued = false;
			});
		}
	}

	function loadLocalStorage() {
		try {
			var data = sys.io.File.getContent(appPath + "/" + localUserDataSave);
			localStorage = haxe.Json.parse(data);
		} catch(e) {
			trace("Error loading localUserSave", e);
			localStorage = {};
		}
	}

	public function chooseProject() {
		hxd.File.browse((select) -> {
			var path = select.fileName.split("\\");
			path.pop();
			var dir = path.join("\\");
			setProject(dir);
		}, {fileTypes: [{name: "hxml", extensions: ["hxml"]}]});
	}

	override function setProject(dir:String) {
		super.setProject(dir);
		trace("set project " + dir);
		hxd.res.Loader.currentInstance?.dispose();
		hxd.res.Loader.currentInstance = new hxd.res.Loader(new hxd.fs.LocalFileSystem(resourceDir, null));
		app.ui.mainLayout.onSetProject();

		h3d.mat.MaterialSetup.current = new h3d.mat.PbrMaterialSetup();

	}

	public function getLocalStorage(key: String) : Null<Dynamic> {
		return Reflect.field(localStorage,key);

	}

	public function clearLocalStorage(key: String) {
		Reflect.deleteField(localStorage, key);
		queueStorageSave();
	}

	public function openFile(filePath: String) {
		if (filePath.split(".").pop() == "prefab") {
			var tab = new hide.view.Prefab({path: filePath});
			app.ui.uiBase.mainLayout.projectLayout.mainPanel.addTab(tab);
			app.ui.uiBase.mainLayout.projectLayout.mainPanel.setTab(tab);
			return;
		}

		throw "No handler for file " + filePath;
	}


}
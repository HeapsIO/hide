package hide;

class Ide extends hide.tools.IdeData {
	public static var inst : Ide;
	public var app : hide.App;

	// Keep a small delay between saves to avoid spamming the disk with writes
	var localStorageSaveDelay: Float = 0.0;

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

	public function deleteLocalStorage(key: String) {
		Reflect.deleteField(localStorage, key);

		queueStorageSave();
	}

	function queueStorageSave() {
		localStorageSaveQueued = true;
	}

	function saveLocalStorageToDisk() {
		sys.io.File.saveContent(appPath + "/" + localUserDataSave, haxe.Json.stringify(localStorage, "\t"));
	}

	public function update(dt: Float) {
		localStorageSaveDelay -= dt;
		if (localStorageSaveQueued) {
			if (localStorageSaveDelay < 0) {
				saveLocalStorageToDisk();
				localStorageSaveDelay = 5.0;
				localStorageSaveQueued = false;
			}
		}
	}

	public function dispose() {
		if (localStorageSaveQueued) {
			saveLocalStorageToDisk();
			localStorageSaveQueued = false;
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
		loadDatabase(true);

		// var pluginPath = getPath("../hide-plugin.hl");
		// if (sys.FileSystem.exists(pluginPath)) {
		// 	if (!hl.Api.loadPlugin(pluginPath)) {
		// 		throw "Plugin failed to load";
		// 	} else {
		// 		trace("Plugin loaded");
		// 	}
		// } else {
		// 	trace('No plugin found for project (searched $pluginPath )');
		// }

		@:privateAccess app.ui.mainLayout.rebuild();

		hxd.Window.getInstance().title = "HideHL - " + new haxe.io.Path(dir).file;

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
		var path = new haxe.io.Path(filePath);

		try {
			switch (path.ext) {
				case "prefab", "fx":
					openView(new hide.view.Prefab({path: filePath}));
			}
		} catch (e) {
			showError('Could not open file ${getRelPath(filePath)} :<br/>$e');
		}
	}

	public function openView(view: hrt.ui.HuiView<Dynamic>) {
		app.ui.uiBase.mainLayout.projectLayout.mainPanel.addTab(view);
		app.ui.uiBase.mainLayout.projectLayout.mainPanel.setTab(view);
	}

	public function getCDBContent<T>( sheetName : String ) : Array<T> {
		for( s in database.sheets )
			if( s.name == sheetName ) {
				var s = Reflect.copy(@:privateAccess s.realSheet.sheet);
				s.lines = [for( l in s.lines ) Reflect.copy(l)];
				@:privateAccess cdb.Types.Index.initLines(s);
				return cast s.lines;
			}
		return null;
	}


	static public function showError(message: String) {
		Sys.stdout().writeString('[Err ] $message\n');
		inst.app.ui.uiBase.mainLayout.addToast(message, Error);
	}

	static public function showWarning(message: String) {
		Sys.stdout().writeString('[Warn] $message\n');
		inst.app.ui.uiBase.mainLayout.addToast(message, Warning);
	}

	static public function showInfo(message: String) {
		Sys.stdout().writeString('[Info] $message\n');
		inst.app.ui.uiBase.mainLayout.addToast(message, Info);
	}
}
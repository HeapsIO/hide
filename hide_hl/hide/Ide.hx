package hide;

class Ide extends hide.tools.IdeData {
	public static var inst : Ide;

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

	public function getLocalStorage(key: String) : Null<Dynamic> {
		return Reflect.field(localStorage,key);

	}

	public function clearLocalStorage(key: String) {
		Reflect.deleteField(localStorage, key);
		queueStorageSave();
	}


}
package hide.view.settings;

typedef LocalSettings = {
	var file : String;
	var content : Dynamic;
	var children : Array<LocalSettings>;
}

class ProjectSettings extends Settings {
	public static var SETTINGS_FILE = "props.json";

	var settings : Array<LocalSettings>;

	public function new( ?state ) {
		super(state);

		var localSettings = getPropsFiles(ide.projectDir);

		var general = new hide.view.settings.Settings.Categorie("General");
		categories.push(general);

		for (f in Reflect.fields(localSettings[0].content)) {
			var cat = general;
			if (f.split('.').length > 1) {
				var catName = sublimeName(f.split('.')[0]);
				cat = getCategorie(catName);
				if (cat == null) {
					cat = new hide.view.settings.Settings.Categorie(catName);
					categories.push(cat);
				}
			}

			var settingName = sublimeName(f.split('.')[f.split('.').length - 1]);
			var type = Type.typeof(Reflect.field(localSettings[0].content, f));
			var settingElement = switch (type) {
				case TClass(String):
					new Element('<input/>');
				case TBool:
					new Element('<input type="checkbox"/>');
				case TInt, TFloat:
					new Element('<input type="number"/>');
				default:
					new Element('<p>EDITION NOT SUPPORTED</p>');
			}

			cat.add(settingName, settingElement, null);
		}

		categories.sort(function(p1, p2) return (p1.name > p2.name) ? 1 : -1);
	}

	override function getTitle() {
		return "Project Settings";
	}

	function getPropsFiles(path: String) : Array<LocalSettings> {
		var res : Array<LocalSettings> = [];

		var settingsPath = '${path}/${ProjectSettings.SETTINGS_FILE}';

		var localSettings : LocalSettings = null;
		if (sys.FileSystem.exists(settingsPath)) {
			var content = sys.io.File.getContent(settingsPath);
			var obj = try haxe.Json.parse(content) catch( e : Dynamic ) throw "Failed to parse " + settingsPath + "("+e+")";
			localSettings = { file: settingsPath, content: obj, children: null };
		}

		for (f in sys.FileSystem.readDirectory(path)) {
			if (!sys.FileSystem.isDirectory('${path}/${f}'))
				continue;

			var children = getPropsFiles('${path}/${f}');
			if (children == null)
				continue;

			res = res.concat(children);
		}

		if (localSettings == null)
			return res;

		localSettings.children = res;
		return [localSettings];
	}

	function sublimeName(string : String) {
		var res = "";
		for (cIdx in 0...string.length) {
			var c = string.charAt(cIdx);

			if (cIdx == 0) {
				res += c.toUpperCase();
				continue;
			}

			if (c == c.toUpperCase()) {
				res += " " + c;
				continue;
			}

			res += c;
		}

		return res;
	}

	static var _ = hide.ui.View.register(ProjectSettings);
}

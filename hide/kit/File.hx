package hide.kit;

#if domkit

class File extends Widget<String> {

	public var type : String = "file";

	#if js
	var file: hide.comp.FileSelect2;
	var element: hide.Element;
	#end

	function makeInput():NativeElement {
		#if js
		file = new hide.comp.FileSelect2(types.get(type), element, null, true);

		file.onChange = () -> {
			value = file.path;
			broadcastValueChange(false);
		}
		file.onView = () -> onView();

		return file.element[0];
		#else
		throw "implment";
		#end
	}

	override function syncValueUI() {
		#if js
		if (file != null)
			file.path = value ?? '-- Choose ${type.toUpperCase()} --';
		#end
	}

	function getDefaultFallback() : String {
		return null;
	}

	function stringToValue(obj: String) : String {
		var ext = obj.split(".").pop();
		if (types.get(type).contains(ext)) {
			return obj;
		}
		return null;
	}

	public dynamic function onView() {}

	static var types : Map<String, Array<String>> = [
		"file" => ["*"],
		"prefab" => ["prefab", "l3d", "fx"],
		"fx" => ["fx"],
		"texture" => ["png", "dds", "jpeg", "jpg"],
		"model" => ["fbx", "hmd"],
		"atlas" => ["atlas"],
		"font" => ["fnt"],
	];
}

#end
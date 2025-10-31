package hide.kit;

class File extends Widget<String> {

	public var type : String = "file";

	#if js
	var file: hide.comp.FileSelect;
	#end

	function makeInput():NativeElement {
		#if js
		file = new hide.comp.FileSelect(types.get(type), null, null, true);
		file.onChange = () -> {
			value = file.path;
			broadcastValueChange(false);
		}

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

	static var types : Map<String, Array<String>> = [
		"file" => ["*"],
		"prefab" => ["prefab", "l3d", "fx"],
		"texture" => ["png", "dds", "jpeg", "jpg"],
		"model" => ["fbx", "hmd"],
	];
}
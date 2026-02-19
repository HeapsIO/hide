package hide.kit;

#if domkit

class File extends Widget<String> {

	public var type : String = "file";

	/**
		Override type with a custom list of extensions (without the ".")
	**/
	public var exts : Array<String> = null;

	#if js
	var file: hide.comp.FileSelect2;
	var element: hide.Element;
	#end

	function makeInput():NativeElement {
		#if js
		file = new hide.comp.FileSelect2(exts ?? types.get(type), element, null, true);

		file.onChange = () -> {
			value = file.path;
			broadcastValueChange(false);
		}
		file.onView = () -> onView();

		return file.element[0];
		#elseif hui
		var f = new hrt.ui.HuiFilePicker();
		f.value = value;
		f.onValueChanged = () -> {
			value = f.value;
			broadcastValueChange(false);
		}
		return f;
		#else
		return null;
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

	public dynamic function onView() {
		#if js
		hide.Ide.inst.openFile(file.getFullPath());
		#end
	}

	static var types : Map<String, Array<String>> = [
		"file" => ["*"],
		"prefab" => ["prefab", "l3d", "fx"],
		"fx" => ["fx"],
		"texture" => ["png", "dds", "jpeg", "jpg", "hdr"],
		"model" => ["fbx", "hmd"],
		"atlas" => ["atlas"],
		"font" => ["fnt"],
	];
}

#end
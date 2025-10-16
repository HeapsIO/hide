package hide.kit;

class File extends Widget<String> {

	public var type : String;

	#if js
	var text: js.html.ParagraphElement;
	#end

	function makeInput():NativeElement {
		#if js
		input = js.Browser.document.createElement("kit-file");
		text = js.Browser.document.createParagraphElement();
		input.appendChild(text);

		input.addEventListener("mousedown", (e: js.html.MouseEvent) -> {
			if (e.button != 0)
				return;
			Ide.inst.chooseFile(types.get(type), (v: String) -> {
				value = v;
				broadcastValueChange(false);
			}, true);
		});

		return input;
		#else
		throw "implment";
		#end
	}

	override function syncValueUI() {
		#if js
		if (text != null)
			text.innerText = value ?? "-- Choose Texture --";
		#end
	}

	function getDefaultFallback() : String {
		return null;
	}

	static var types : Map<String, Array<String>> = [
		"texture" => ["png", "dds", "jpeg", "jpg"],
		"model" => ["fbx", "hmd"],
	];

	function stringToValue(obj: String) : String {
		var ext = obj.split(".").pop();
		if (types.get(type).contains(ext)) {
			return obj;
		}
		return null;
	}
}
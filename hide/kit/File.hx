package hide.kit;

class File extends Widget<String> {

	public var type(default, set) : String;

	#if js
	var text: js.html.ParagraphElement;
	#end

	function set_type(v: String) : String {
		type = v;
		#if js
		if (native != null) {
			var exts = types.get(type);
			var accept = null;
			if (exts != null) {
				accept = "";
				for (i => ext in exts) {
					accept += "." + "ext";
					if (i < exts.length)
						accept += ",";
				}
			}
			(cast native:js.html.InputElement).accept = accept;
		}
		#else
		throw "aaa";
		#end
		return v;
	}

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
		#end
	}

	override function syncValueUI() {
		#if js
		if (text != null)
			text.innerText = value ?? "-- Choose Texture --";
		#end
	}

	static var types : Map<String, Array<String>> = [
		"texture" => ["png", "dds", "jpeg", "jpg"],
		"model" => ["fbx", "hmd"],
	];
}
package hide.kit;

#if domkit

class File extends Widget<String> {

	public var type : String = "file";

	#if js
	var file: hide.comp.FileSelect;
	var element: hide.Element;
	#end

	function makeInput():NativeElement {
		#if js
		element = new hide.Element("<kit-file></kit-file>");
		file = new hide.comp.FileSelect(types.get(type), element, null, true);

		file.onChange = () -> {
			value = file.path;
			broadcastValueChange(false);
		}
		file.onView = () -> onView();

		return element[0];
		#else
		throw "implment";
		#end
	}

	#if js
	function bindTooltip(element: hide.Element, fileEntry: hide.tools.FileManager.FileEntry) {
		var element = element[0];
		var tooltip = null;
		element.onmouseenter = () -> {
			tooltip?.remove();

			if (value == null)
				return;

			if (fileEntry == null)
				return;
			tooltip = new hide.comp.FancyTooltip(new hide.Element(root.native));

			var refresh = (_) -> {
				tooltip.element.html(hide.view.FileBrowser.getThumbnail(fileEntry));
				tooltip.element.children()[0].style.width = "256px";
				tooltip.element.children()[0].style.height = "256px";
			};

			refresh(null);
			fileEntry.getIcon(refresh);

			var geom = element.getBoundingClientRect();
			tooltip.show();
			var tooltipGeom = tooltip.element[0].getBoundingClientRect();
			tooltip.x = Std.int(geom.right - tooltipGeom.width);
			tooltip.y = Std.int(geom.bottom);
		}

		element.onmouseleave = () -> {
			tooltip?.remove();
			tooltip = null;
		}
	}
	#end

	override function syncValueUI() {
		#if js
		if (file != null)
			file.path = value ?? '-- Choose ${type.toUpperCase()} --';
		if (element != null) {
			element.find("fancy-image").remove();
			if (value != null) {
				var fileEntry = hide.tools.FileManager.inst.getFileEntry(value);
				if (fileEntry != null) {
					var refresh = (_) -> {
						element.find("fancy-image").remove();
						element.append(hide.view.FileBrowser.getThumbnail(fileEntry));
						bindTooltip(element.find("fancy-image"), fileEntry);
					};

					refresh(null);
					fileEntry.getIcon(refresh);
				}
			}
		}
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
package hide.kit;

#if domkit

/**
	Allow the user to reference an object in the h3d scene
**/
class Object3dRef extends Widget<String> {

	/**
		Optional filter to remove certains object from the scene
	**/
	var filter: (h3d.scene.Object) -> Bool = null;

	/**
		Include joints in parts list
	**/
	var joints: Bool = true;


	#if js
	var select: NativeElement;
	var text: NativeElement;
	var dropdown = null;
	#end

	function makeInput():NativeElement {
		#if js
		function valueChanged(newValue: String) {
			value = newValue;
			broadcastValueChange(false);
		}

		select = js.Browser.document.createElement("kit-select");
		text = js.Browser.document.createSpanElement();
		select.appendChild(text);

		var entries = getNamedObjects();

		select.onclick = (e: js.html.MouseEvent) -> {
			var selectEntries: Array<hide.comp.ContextMenu.MenuItem> = [for (i => entry in entries) {label: entry.label, click: valueChanged.bind(entry.value)}];
			if (dropdown == null) {
				dropdown = hide.comp.ContextMenu.createDropdown(select, selectEntries);
				dropdown.onClose = () -> {
					dropdown = null;
				}
			} else {
				dropdown.close();
			}
		}
		return select;
		#else
		return null;
		#end
	}

	function stringToValue(str: String) : Null<String> {return value;};

	function getDefaultFallback() : String {return null;};

	override function syncValueUI() {
		#if js
		if (text == null)
			return;
		var label = "--- Select ---";
		if (value != null)
			label = value.split(".").pop();
		text.innerText = label;
		#end
	}

	function getNamedObjects() {
		var out = [];

		function formatName(path: Array<String>) {
			var name = "";
			for (p in 0...path.length-1) {
				name += "&nbsp;&nbsp;";
			}
			name += path[path.length-1];
			return name;
		}

		function getJoint(path:Array<String>,j:h3d.anim.Skin.Joint) {
			path.push(j.name);
			out.push({label: formatName(path), value: path.join(".")});
			for( j in j.subs )
				getJoint(path, j);
			path.pop();
		}

		function getRec(path:Array<String>,o:h3d.scene.Object) {
			if (o.name == null) return;
			if (filter != null && !filter(o)) return;
			path.push(o.name);
			out.push({label: formatName(path), value: path.join(".")});
			for( c in o )
				getRec(path, c);
			var sk = Std.downcast(o, h3d.scene.Skin);
			if( sk != null && joints) {
				var j = sk.getSkinData();
				for( j in j.rootJoints )
					getJoint(path, j);
			}
			path.pop();
		}

		for( o in root.editor.getRootObjects3d())
			getRec([], o);

		return out;
	}
}

#end
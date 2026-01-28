package hide.kit;

#if domkit

class Button extends Element {
	var label : String;
	public var highlight(default, set) : Bool = false;
	public var image : String;
	public var medium : Bool = false;
	public var big : Bool = false;
	public var huge : Bool = false;
	public var quiet : Bool = false;

	var button : NativeElement;

	function set_highlight(v:Bool) : Bool {
		highlight = v;
		syncHightlight();
		return v;
	}

	public function new(parent: Element, id: String, label: String) {
		super(parent, id);
		this.label = label;
	}

	public dynamic function onClick() {

	}

	function broadcastClick() {
		parent?.change(onClickChange, false);
	}

	/** Internal function passed to change() **/
	function onClickChange() {
		onClick();
		@:privateAccess root.prefab?.updateInstance();

		var idPath = getIdPath();
		for (childProperties in root.editedPrefabsProperties) {

			var childElement = childProperties.getElementByPath(idPath);
			var childButton = Std.downcast(childElement, Button);
			if (childButton != null) {
				childButton.onClick();
				@:privateAccess childProperties.prefab?.updateInstance();
			}
		}
	}

	override function makeSelf() {
		#if js

		button = js.Browser.document.createElement("kit-button");
		button.innerHTML = label;
		if (image != null) {
			var imageElement = js.Browser.document.createElement("kit-image");
			imageElement.style.backgroundImage = 'url(file://${hide.Ide.inst.getHideResPath(image)})';
			button.appendChild(imageElement);
		}
		if (medium) {
			button.classList.add("kit-medium");
		}
		if (big) {
			button.classList.add("kit-big");
		}

		if (quiet) {
			button.classList.add("kit-quiet");
		}

		button.addEventListener("click", (e:js.html.MouseEvent) -> {
			if (!disabled) {
				broadcastClick();
				e.preventDefault();
				e.stopPropagation();
			}
		});

		syncHightlight();
		#elseif hui
		#end
		setupPropLine(null, button);
	}

	function syncHightlight() {
		#if js
		if (button != null)
			button.classList.toggle("highlight", highlight);
		#end
	}
}

#end
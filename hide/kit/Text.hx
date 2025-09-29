package hide.kit;

class Text extends Element {
	var content(default, set) : String;

	function set_content(v: String) : String {
		content = v;
		#if js
		wrap.textContent = content;
		#else
		throw "HideKitHL Implement";
		#end
		return content;
	}

	public function new(ctx: hide.prefab.EditContext, parent: Element, id: String, content: String) : Void {
		super(ctx, parent, id);
		this.content = content;
	}

	override function makeObject() : WrappedElement {
		#if js
		return js.Browser.document.createParagraphElement();
		#else
		throw "HideKitHL Implement";
		#end
	}
}
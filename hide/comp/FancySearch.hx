package hide.comp;

class FancySearch extends hide.comp.Component {
	var open = false;

	var input : js.html.InputElement;

	public override function new(parent: Element = null, target: Element = null) {
		var el = new hide.Element('
			<fancy-search>
				<div class="fancy-search-box">
					<input type="text" class="search-field">
					<fancy-icon class="search-icon fi-search"></fancy-icon>
				</div>

				<fancy-button class="quieter close-btn"><fancy-icon class="medium fi-close"></fancy-icon></fancy-button>
			</fancy-search>
		');
		if (target != null) {
			target.replaceWith(el);
		}
		super(parent, el);

		/*if (keys != null) {
			keys.register("search", () -> toggleSearch(true, true));
		}*/

		input = cast element.get(0).querySelector(".search-field");

		input.oninput = (e) -> {
			onSearch(e.target.value, false);
		}

		input.onchange = (e) -> {
			onSearch(e.target.value, true);
		}

		var close = element.get(0).querySelector(".close-btn");
		close.onclick = (e) -> toggleSearch(false, false);
	}

	public dynamic function onSearch(search: String, enter: Bool) : Void {};

	public function toggleSearch(?force: Bool, focus: Bool = false) : Void {
		var want = force != null ? force : !open;
		if (open != want) {
			open = want;
			//FancyTree.animateReveal(element.get(0), open);
		}

		if (open && focus) {
			input.focus();
		} else if (!open) {
			input.blur();
		}
	}

	public function isOpen() : Bool {
		return open;
	}

	public function hasFocus() : Bool {
		return js.Browser.document.activeElement ==  input;
	}

	public function blur() : Void {
		input.blur();
	}

	public function focus() : Void {
		input.focus();
	}
}
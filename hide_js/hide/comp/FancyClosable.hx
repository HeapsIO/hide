package hide.comp;

/**
	A container that is hidden by default and that can appear scrolling down from the top,
	like for a search bar
**/
class FancyClosable extends hide.comp.Component {
	var open = false;

	public override function new(parent: Element = null, target: Element = null) {
		var el = new hide.Element('
			<fancy-closable class="shadow">
				<fancy-toolbar class="fancy-small">
					<fancy-button class="quieter close-btn"><fancy-icon class="medium fi-close"></fancy-icon></fancy-button>
				</fancy-toolbar>
			</fancy-closable>
		');
		if (target != null) {
			var children = target.children();
			target.replaceWith(el);
			children.insertBefore(el.find("fancy-toolbar").children().first());
		}
		super(parent, el);

		var close = element.get(0).querySelector(".close-btn");
		close.onclick = (e) -> toggleOpen(false);
	}

	public dynamic function onOpen() : Void {};
	public dynamic function onClose() : Void {};

	public function toggleOpen(?force: Bool) : Void {
		var want = force != null ? force : !open;
		if (open != want) {
			open = want;
			FancyTree.animateReveal(element.get(0), open);
		}

		if (open) {
			onOpen();
		} else {
			onClose();
		}
	}

	public function isOpen() : Bool {
		return open;
	}
}
package hide.view;

typedef FileBrowserState = {

}

typedef DummyFile = {
	name: String,
	?children: Array<DummyFile>,
	?parent: DummyFile,
};

class FileBrowser extends hide.ui.View<FileBrowserState> {

	var fileTree: Element;
	var fileIcons: Element;

	override function new(state) {
		super(state);
	}

	override function onDragDrop(items:Array<String>, isDrop:Bool, event:js.html.DragEvent):Bool {
		return false;
	}
	override function onDisplay() {
		var data : Array<DummyFile> = [
			{
				name: "Alice", children: [
					{name: "In"},
					{name: "Wonderland"}
				]
			},
			{
				name: "Bob", children: [
					{name: "Blob"},
					{name: "Dylan", children: [
						{name: "Mdr"},
						{name: "Lorem ipsum sit dolor amet eun egrissor ave caesar morituri te salutant"},
					]}
				]
			},{name: "damage"},
			{name: "anger"},
			{name: "square"},
			{name: "program"},
			{name: "stomach"},
			{name: "capricious"},
			{name: "purring"},
			{name: "agreeable"},
			{name: "longing"},
			{name: "festive"},
			{name: "signal"},
			{name: "gainful"},
			{name: "experience"},
			{name: "tangy"},
			{name: "agreeable"},
			{name: "icky"},
			{name: "uninterested"},
			{name: "abiding"},
			{name: "fire"},
			{name: "fang"},
			{name: "burly"},
			{name: "page"},
			{name: "flowers"},
			{name: "trade"},
			{name: "arrive"},
			{name: "authority"},
			{name: "forgetful"},
			{name: "present"},
			{name: "bawdy"},
			{name: "pathetic"},
			{name: "nonstop"},
			{name: "furry"},
			{name: "woman"},
			{name: "tangy"},
			{name: "trace"},
			{name: "detect"},
			{name: "wound"},
			{name: "risk"},
			{name: "elbow"},
			{name: "train"},
			{name: "tawdry"},
			{name: "feeling"},
			{name: "cheerful"},
			{name: "weak"},
			{name: "waves"},
			{name: "appliance"},
			{name: "womanly"},
			{name: "stone"},
			{name: "store"},
			{name: "known"},
			{name: "angle"},
			{name: "dashing"},
			{name: "group"},
			{name: "fearful"},
			{name: "hard-to-find"},
			{name: "vivacious"},
			{name: "secretive"},
			{name: "pail"},
			{name: "rightful"},
			{name: "slap"},
			{name: "disagree"},
			{name: "arrogant"},
			{name: "billowy"},
			{name: "hair"},
			{name: "literate"},
			{name: "panoramic"},
			{name: "spurious"},
			{name: "sweltering"},
			{name: "cherries"},
			{name: "special"},
			{name: "playground"},
			{name: "neck"},
			{name: "obnoxious"},
			{name: "comparison"},
			{name: "hateful"},
			{name: "tub"},
			{name: "courageous"},
			{name: "breath"},
			{name: "bloody"},
			{name: "irritate"},
			{name: "broad"},
			{name: "tow"},
			{name: "river"},
			{name: "snakes"},
			{name: "threatening"},
			{name: "abaft"},
			{name: "spotted"},
			{name: "hateful"},
			{name: "resolute"},
			{name: "meeting"},
			{name: "statuesque"},
			{name: "sniff"},
			{name: "resolute"},
			{name: "year"},
			{name: "letter"},
			{name: "superb"},
			{name: "bedroom"},
			{name: "dock"},
			{name: "receipt"},
			{name: "unable"},
			{name: "lamp"},
			{name: "obsequious"},
			{name: "kill"},
			{name: "join"},
			{name: "stupendous"},
			{name: "thinkable"},
			{name: "flimsy"},
			{name: "haunt"},
			{name: "ugly"},
			{name: "flippant"},
			{name: "quarrelsome"},
			{name: "shoes"},
			{name: "square"},
			{name: "queen"},
			{name: "glib"},
			{name: "fretful"},
			{name: "road"},
			{name: "ruddy"},
			{name: "scattered"},
			{name: "feeling"},
			{name: "wild"},
			{name: "yard"},
			{name: "arch"},
			{name: "wriggle"},
		];

		function setParentRec(current: DummyFile, parent: DummyFile) {
			current.parent = parent;
			if (current.children != null) {
				for (child in current.children) {
					setParentRec(child, current);
				}
			}
		}

		for (d in data) {
			setParentRec(d, null);
		}

		var layout = new Element('
			<file-browser>
				<div class="left"></div>
				<div class="right"><p>Selection: </p></div>
			</file-browser>
		').appendTo(element);

		var resize = new hide.comp.ResizablePanel(Horizontal, layout.find(".left"), After);

		var fancyTree = new hide.comp.FancyTree(resize.element);
		fancyTree.saveDisplayKey = "fileBrowserTree";
		fancyTree.getChildren = (file: DummyFile) -> return file != null ? file.children : data;
		fancyTree.getName = (file: DummyFile) -> return file?.name;
		fancyTree.getIcon = (file: DummyFile) -> return new Element('<div class="ico ico-folder"></div>').get(0);
		fancyTree.onSelectionChanged = () -> {
			var selection = fancyTree.getSelectedItems();
			var p = layout.find(".right p");
			var txt = "Selection: ";

			for (s in selection) {
				txt += s.name;
			}
			p.text(txt);
		}
		fancyTree.onNameChange = (item: DummyFile, newName: String) -> {
			item.name = newName;
		}
		fancyTree.moveFlags.set(Reparent);
		fancyTree.moveFlags.set(Reorder);

		fancyTree.canReparentTo = (items, newParent) -> {
			for (item in items) {
				var cur = newParent;
				while(cur != null) {
					if (cur == item)
						return false;
					cur = cur.parent;
				}
			}
			return true;
		}

		fancyTree.onMove = (items, newParent, newIndex) -> {
			for (item in items) {
				(item?.parent?.children ?? data).remove(item);
			}

			if (newParent != null) {
				newParent.children ??= [];
			}

			for (i => item in items) {
				(newParent?.children ?? data).insert(newIndex + i, item);
				item.parent = newParent;
			}

			fancyTree.rebuildTree();
		}

		fancyTree.rebuildTree();
	}

	static var _ = hide.ui.View.register(FileBrowser, { width : 350, position : Bottom });
}
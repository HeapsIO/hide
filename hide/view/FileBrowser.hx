package hide.view;

typedef FileBrowserState = {

}

typedef DummyFile = {
	name: String,
	?children: Array<DummyFile>,
};

class FileBrowser extends hide.ui.View<FileBrowserState> {

	var fileTree: Element;
	var fileIcons: Element;

	override function new(state) {
		super(state);
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
			}
		];

		var layout = new Element('
			<file-browser>
				<div class="left"></div>
				<div class="right"><p>Selection: </p></div>
			</file-browser>
		').appendTo(element);

		var resize = new hide.comp.ResizablePanel(Horizontal, layout.find(".left"), After);

		var fancyTree = new hide.comp.FancyTree(resize.element);
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

		fancyTree.rebuildTree();
	}

	static var _ = hide.ui.View.register(FileBrowser, { width : 350, position : Bottom });
}
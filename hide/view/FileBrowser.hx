package hide.view;

typedef FileBrowserState = {

}

enum FileKind {
	Dir;
	File;
}

typedef FileEntry = {
	name: String,
	children: Array<FileEntry>,
	kind: FileKind,
	parent: FileEntry,
}

class FileBrowser extends hide.ui.View<FileBrowserState> {

	var fileTree: Element;
	var fileIcons: Element;

	var root : FileEntry;

	override function new(state) {
		super(state);
	}

	override function onDragDrop(items:Array<String>, isDrop:Bool, event:js.html.DragEvent):Bool {
		return false;
	}

	function getFilePath(file: FileEntry) {
		if (file.parent != null)
			return getFilePath(file.parent) + "/" + file.name;
		return file.name;
	}

	function populateChildren(file: FileEntry) {
		trace("populate", file.name);
		var fullPath = getFilePath(file);
		var paths = js.node.Fs.readdirSync(fullPath);
		file.children = [];
		for (path in paths) {
			if (StringTools.startsWith(path, "."))
				continue;
			var info = js.node.Fs.statSync(fullPath + "/" + path);
			file.children.push({
				name: path,
				kind: info.isDirectory() ? Dir : File,
				parent: file,
				children: null,
			});
		}
	}

	override function onDisplay() {
		root = {
			name: ide.resourceDir,
			kind: Dir,
			children: null,
			parent: null
		};

		populateChildren(root);

		var layout = new Element('
			<file-browser>
				<div class="left"></div>
				<div class="right"><p>Selection: </p></div>
			</file-browser>
		').appendTo(element);

		var resize = new hide.comp.ResizablePanel(Horizontal, layout.find(".left"), After);

		var fancyTree = new hide.comp.FancyTree2<FileEntry>(resize.element);
		fancyTree.saveDisplayKey = "fileBrowserTree";
		fancyTree.getChildren = (file: FileEntry) -> {
			if (file == null)
				return root.children;
			if (file.kind == File)
				return null;
			if (file.children == null)
				populateChildren(file);
			return file.children;
		};
		//fancyTree.hasChildren = (file: FileEntry) -> return file.kind == Dir;
		fancyTree.getName = (file: FileEntry) -> return file?.name;
		fancyTree.getIcon = (file: FileEntry) -> return '<div class="ico ico-folder"></div>';
		fancyTree.onSelectionChanged = () -> {
			var selection = fancyTree.getSelectedItems();
			var p = layout.find(".right p");
			var txt = "Selection: ";

			for (s in selection) {
				txt += s.name;
			}
			p.text(txt);
		}
		fancyTree.onNameChange = (item: FileEntry, newName: String) -> {
			item.name = newName;
		}
		// fancyTree.moveFlags.set(Reparent);
		// fancyTree.moveFlags.set(Reorder);

		// fancyTree.canReparentTo = (items, newParent) -> {
		// 	for (item in items) {
		// 		var cur = newParent;
		// 		while(cur != null) {
		// 			if (cur == item)
		// 				return false;
		// 			cur = cur.parent;
		// 		}
		// 	}
		// 	return true;
		// }

		// fancyTree.onMove = (items, newParent, newIndex) -> {
		// 	for (item in items) {
		// 		(item?.parent?.children ?? data).remove(item);
		// 	}

		// 	if (newParent != null) {
		// 		newParent.children ??= [];
		// 	}

		// 	for (i => item in items) {
		// 		(newParent?.children ?? data).insert(newIndex + i, item);
		// 		item.parent = newParent;
		// 	}

		// 	fancyTree.rebuildTree();
		// }

		fancyTree.rebuildTree();
		trace("tree rebuild");
	}

	static var _ = hide.ui.View.register(FileBrowser, { width : 350, position : Bottom });
}
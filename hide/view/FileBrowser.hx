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
	iconPath: String,
}

class FileBrowser extends hide.ui.View<FileBrowserState> {

	var fileTree: Element;
	var fileIcons: Element;

	var root : FileEntry;
	var breadcrumbs : Element;

	override function new(state) {
		super(state);
	}

	override function onDragDrop(items:Array<String>, isDrop:Bool, event:js.html.DragEvent):Bool {
		return false;
	}

	function populateChildren(file: FileEntry) {
		var fullPath = getFileEntryPath(file);
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
				iconPath: null,
			});
		}

		file.children.sort(compareFile);
	}

	// sort directories before files, and then dirs and files alphabetically
	function compareFile(a: FileEntry, b: FileEntry) {
		if (a.kind != b.kind) {
			if (a.kind == Dir) {
				return -1;
			}
			return 1;
		}
		return Reflect.compare(a.name, b.name);
	}

	function getFileEntryPath(file: FileEntry) {
		if (file.parent == null) return ide.resourceDir;
		return getFileEntryPath(file.parent) + "/" + file.name;
	}

	public static final dragKey = "application/x.filemove";

	var currentFolder : FileEntry;
	var currentSearch = [];
	var searchString: String = "";
	var fancyGallery : hide.comp.FancyGallery<FileEntry>;
	var fancyTree: hide.comp.FancyTree<FileEntry>;


	function onSearch() {
		hide.tools.FileManager.inst.clearRenderQueue();
		currentSearch = [];
		if (searchString.length == 0) {
			currentSearch = currentFolder.children;
		} else {
			function rec(files: Array<FileEntry>) {
				for (file in files) {
					if (file.kind == Dir) {
						rec(file.children);
					}
					else {
						var range = hide.comp.FancySearch.computeSearchRanges(file.name, searchString);
						if (range != null) {
							currentSearch.push(file);
						}
					}
				}
			}

			rec(currentFolder.children);
		}

		for (i => _ in currentSearch) {
			var child = currentSearch[currentSearch.length - i - 1];
			if ((child.iconPath == null || child.iconPath == "loading") && child.kind == File) {
				child.iconPath = "loading";
				hide.tools.FileManager.inst.renderMiniature(getFileEntryPath(child), (path: String) -> {child.iconPath = path; fancyGallery.queueRefresh();} );
			}
		}

		fancyGallery.queueRefresh(Items);
		fancyGallery.queueRefresh(RegenHeader);
	}

	override function onDisplay() {
		root = {
			name: "res",
			kind: Dir,
			children: null,
			parent: null,
			iconPath: null,
		};

		populateChildren(root);

		var layout = new Element('
			<file-browser>
				<div class="left"></div>
				<div class="right" tabindex="-1">
					<fancy-toolbar class="fancy-small shadow">
						<fancy-button class="btn-parent quiet" title="Go to parent folder">
							<fancy-image style="background-image:url(\'res/icons/svg/file_parent.svg\')"></fancy-image>
						</fancy-button>
						<fancy-breadcrumbs></fancy-breadcrumbs>
						<fancy-flex-fill></fancy-flex-fill>
						<fancy-search class="fb-search"></fancy-search>
					</fancy-toolbar>
					<fancy-gallery></fancy-gallery>
				</div>
			</file-browser>
		').appendTo(element);

		breadcrumbs = layout.find("fancy-breadcrumbs");

		var resize = new hide.comp.ResizablePanel(Horizontal, layout.find(".left"), After);

		var search = new hide.comp.FancySearch(null, layout.find(".fb-search"));
		search.onSearch = (string, _) -> {
			searchString = string;
			onSearch();
		};

		var btnParent = layout.find(".btn-parent");
		btnParent.get(0).onclick = (e: js.html.MouseEvent) -> {
			if (currentFolder.parent != null) {
				openDir(currentFolder.parent, true);
			}
		}

		fancyTree = new hide.comp.FancyTree<FileEntry>(resize.element);
		fancyTree.saveDisplayKey = "fileBrowserTree";
		fancyTree.getChildren = (file: FileEntry) -> {
			if (file == null)
				return [root];
			if (file.kind == File)
				return null;
			if (file.children == null)
				populateChildren(file);
			return file.children.filter((file) -> file.kind == Dir);
		};
		//fancyTree.hasChildren = (file: FileEntry) -> return file.kind == Dir;
		fancyTree.getName = (file: FileEntry) -> return file?.name;
		fancyTree.getIcon = (file: FileEntry) -> return '<div class="ico ico-folder"></div>';

		fancyTree.onNameChange = (item: FileEntry, newName: String) -> {
			item.name = newName;
		}

		fancyTree.dragAndDropInterface =
		{
			onDragStart: function(file: FileEntry, dataTransfer: js.html.DataTransfer) : Bool {
				var selection = fancyTree.getSelectedItems();
				if (selection.length <= 0)
					return false;
				var ser = [];
				for (item in selection) {
					ser.push(getFileEntryPath(file));
				}
				dataTransfer.setData(dragKey, haxe.Json.stringify(ser));
				return true;
			},
			getItemDropFlags: function(target: FileEntry, dataTransfer: js.html.DataTransfer) : hide.comp.FancyTree.DropFlags {
				var containsFiles = false;
				if (dataTransfer.types.contains("Files")) {
					containsFiles = true;
				}
				if (dataTransfer.types.contains(dragKey)) {
					containsFiles = true;
				}

				if (!containsFiles) {
					return hide.comp.FancyTree.DropFlags.ofInt(0);
				}

				if (target.kind == Dir) {
					return (Reorder:hide.comp.FancyTree.DropFlags) | Reparent;
				}
				return Reorder;
			},
			onDrop: function(target: FileEntry, operation: hide.comp.FancyTree.DropOperation, dataTransfer: js.html.DataTransfer) : Bool {
				var files : Array<String> = [];
				for (file in dataTransfer.files) {
					var path : String = untyped file.path; //file.path is an extension from nwjs or node
					path = StringTools.replace(path, "\\", "/");
					files.push(path);
				}

				var fileMoveData = dataTransfer.getData(dragKey);
				if (fileMoveData.length > 0) {
					try {
						var unser = haxe.Json.parse(fileMoveData);
						for (file in (unser:Array<String>)) {
							files.push(file);
						}
					} catch (e) {
						trace("Invalid data " + e);
					}
				}

				return true;
			}
		}

		fancyTree.rebuildTree();

		fancyTree.openItem(root);

		var right = layout.find(".right");
		right.get(0).onkeydown = (e: js.html.KeyboardEvent) -> {
			if (hide.ui.Keys.matchJsEvent("search", e, ide.currentConfig)) {
				e.stopPropagation();
				e.preventDefault();

				search.focus();
				return;
			}
		}

		fancyGallery = new hide.comp.FancyGallery<FileEntry>(null, layout.find(".right fancy-gallery"));
		fancyGallery.getItems = () -> {
			return currentSearch;
		}

		fancyGallery.getName = (item : FileEntry) -> item.name;

		fancyGallery.getIcon = (item : FileEntry) -> {
			if (item.kind == Dir) {
				return '<fancy-image style="background-image:url(\'res/icons/svg/big_folder.svg\')"></fancy-image>';

			}
			else if (item.iconPath == "loading") {
				return '<fancy-image class="loading" style="background-image:url(\'res/icons/svg/loading.svg\')"></fancy-image>';
			}
			else if (item.iconPath != null) {
				var url = "file://" + item.iconPath;
				return '<fancy-image class="thumb" style="background-image:url(\'${url}\')"></fancy-image>';
			}
			else {
				return '<fancy-image style="background-image:url(\'res/icons/svg/file.svg\')"></fancy-image>';
			}
		};

		fancyGallery.onDoubleClick = (item: FileEntry) -> {
			if (item.kind == File) {
				ide.openFile(getFileEntryPath(item));
			} else {
				openDir(item, true);
			}
		}

		fancyGallery.visibilityChanged = (item: FileEntry, visible: Bool) -> {
			var path = getFileEntryPath(item);
			hide.tools.FileManager.inst.setPriority(path, visible ? 1 : 0);
		}

		fancyGallery.dragAndDropInterface = {
			onDragStart: (item: FileEntry, dataTransfer: js.html.DataTransfer) -> {
				dataTransfer.setData(dragKey, haxe.Json.stringify([getFileEntryPath(item)]));
				return true;
			}
		}

		fancyGallery.rebuild();

		openDir(root, false);


		fancyTree.onSelectionChanged = () -> {
			var selection = fancyTree.getSelectedItems();

			if (selection.length > 0) {
				openDir(selection[0], false);
			}
		}

		onSearch();
	}

	function refreshBreadcrumbs() {
		breadcrumbs.empty();
		var path = [];
		var current = currentFolder;
		while (current != null) {
			path.push(current);
			current = current.parent;
		}

		for (i => _ in path) {
			var current = path[path.length-i-1];
			var button = new Element('<fancy-button class="quiet">${current.name}</fancy-button>');
			breadcrumbs.append(new Element(button));

			button.get(0).onclick = (e: js.html.MouseEvent) -> {
				openDir(current, true);
			}

			if (i < path.length - 1) {
				breadcrumbs.append(new Element('<fancy-breadcrumbs-separator>/</fancy-breadcrumbs-separator>'));
			}

		}
	}

	function openDir(item: FileEntry, syncTree: Bool) {
		if (item.kind == Dir) {
			currentFolder = item;
			onSearch();
		}

		if (syncTree) {
			fancyTree.selectItem(item, true);
		}

		refreshBreadcrumbs();
	}

	static var _ = hide.ui.View.register(FileBrowser, { width : 350, position : Bottom });
}
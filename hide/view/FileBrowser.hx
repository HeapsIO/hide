package hide.view;

typedef FileBrowserState = {

}

enum FileKind {
	Dir;
	File;
}

class FileEntry {
	public var name: String;
	public var children: Array<FileEntry>;
	public var kind: FileKind;
	public var parent: FileEntry;
	public var iconPath: String;

	public var onChange : (file: FileEntry) -> Void;

	var registeredWatcher : hide.tools.FileWatcher.FileWatchEvent = null;

	public function new(name: String, parent: FileEntry, kind: FileKind, onChange: (file: FileEntry) -> Void) {
		this.name = name;
		this.parent = parent;
		this.kind = kind;
		this.onChange = onChange;

		watch();
	}

	public function dispose() {
		if (children != null) {
			for (child in children) {
				child.dispose();
			}
		}
		children = null;
		if (registeredWatcher != null) {
			hide.Ide.inst.fileWatcher.unregister(this.getPath(), registeredWatcher.fun);
			registeredWatcher = null;
		}
	}

	public function refreshChildren() {
		var fullPath = getPath();

		if (children == null)
			children = [];
		else
			children.resize(0);

		if (!js.node.Fs.existsSync(fullPath)) {
			return;
		}

		var paths = js.node.Fs.readdirSync(fullPath);

		var oldChildren : Map<String, FileEntry> = [for (file in (children ?? [])) file.name => file];



		for (path in paths) {
			if (StringTools.startsWith(path, "."))
				continue;
			var prev = oldChildren.get(path);
			if (prev != null) {
				children.push(prev);
				oldChildren.remove(path);
			} else {
				var info = js.node.Fs.statSync(fullPath + "/" + path);
				children.push(
					new FileEntry(path, this, info.isDirectory() ? Dir : File, onChange)
				);
			}
		}

		for (child in oldChildren) {
			child.dispose();
		}

		children.sort(compareFile);
	}

	function watch() {
		if (registeredWatcher != null)
			throw "already watching";

		var rel = this.getRelPath();
		if (this.kind == Dir) {
			registeredWatcher = hide.Ide.inst.fileWatcher.register(rel, onChangeDirInternal, true);
		} else if (onChange != null) {
			registeredWatcher = hide.Ide.inst.fileWatcher.register(rel, onChange.bind(this), true);
		}
	}

	function onChangeDirInternal() {
		refreshChildren();

		if (onChange != null) {
			onChange(this);
		}
	}

	public function getPath() {
		if (this.parent == null) return hide.Ide.inst.resourceDir;
		return this.parent.getPath() + "/" + this.name;
	}

	public function getRelPath() {
		if (this.parent == null) return "";
		if (this.parent.parent == null) return this.name;
		return this.parent.getRelPath() + "/" + this.name;
	}

	// sort directories before files, and then dirs and files alphabetically
	static public function compareFile(a: FileEntry, b: FileEntry) {
		if (a.kind != b.kind) {
			if (a.kind == Dir) {
				return -1;
			}
			return 1;
		}
		return Reflect.compare(a.name, b.name);
	}
}

class FileBrowser extends hide.ui.View<FileBrowserState> {

	var fileTree: Element;
	var fileIcons: Element;

	var root : FileEntry;
	var breadcrumbs : Element;

	override function new(state) {
		super(state);
		saveDisplayKey = "fileBrowser";
	}

	override function onDragDrop(items:Array<String>, isDrop:Bool, event:js.html.DragEvent):Bool {
		return false;
	}

	function queueRebuildChildren(path: String) {

	}

	public static final dragKey = "application/x.filemove";

	var currentFolder : FileEntry;
	var currentSearch = [];
	var searchString: String = "";
	var fancyGallery : hide.comp.FancyGallery<FileEntry>;
	var fancyTree: hide.comp.FancyTree<FileEntry>;
	var collapseSubfolders : Bool;
	var collapseSubfoldersButton : js.html.Element;
	var filterButton : js.html.Element;
	var filterEnabled(default, set) : Bool;
	var filters : Map<String, {exts: Array<String>, icon: String}> = [];
	var filterState : Map<String, Bool> = [];
	function set_filterEnabled(v : Bool) {
		var anySet = false;
		for (key => value in filterState) {
			if (value == true) {
				anySet = true;
				break;
			}
		}

		filterEnabled = anySet && v;

		filterButton.classList.toggle("selected", filterEnabled);
		saveDisplayState("filterEnabled", filterEnabled);
		queueGalleryRefresh();
		return v;
	}

	function saveFilterState() {
		saveDisplayState("filterState", [for(k in filterState.keys()) k]);
	}

	function syncCollapseSubfolders() {
		collapseSubfoldersButton.classList.toggle("selected", collapseSubfolders);
		saveDisplayState("collapseSubfolders", collapseSubfolders);
		queueGalleryRefresh();
	}

	var galleryRefreshQueued = false;
	function queueGalleryRefresh() {
		if (!galleryRefreshQueued) {
			galleryRefreshQueued = true;
			js.Browser.window.requestAnimationFrame((_) -> onGalleryRefreshInternal());
		}
	}


	function onGalleryRefreshInternal() {
		galleryRefreshQueued = false;
		hide.tools.FileManager.inst.clearRenderQueue();
		currentSearch = [];

		var validFolder = currentFolder;
		while(validFolder != null && !sys.FileSystem.exists(validFolder.getPath())) {
			validFolder = validFolder.parent;
		}
		if (validFolder == null) {
			validFolder = root;
		}
		if (validFolder != currentFolder) {
			currentFolder = validFolder;
			fancyTree.clearSelection();
			fancyTree.selectItem(currentFolder);
		}

		if (searchString.length == 0 && !collapseSubfolders && !filterEnabled) {
			currentSearch = currentFolder.children;
		} else {
			var exts = [];
			if (filterEnabled) {
				for (name => active in filterState) {
					if (active) {
						for (ext in filters.get(name).exts) {
							exts.push(ext);
						}
					}
				}
			}

			function rec(files: Array<FileEntry>) {
				for (file in files) {
					if (file.kind == Dir && (collapseSubfolders || searchString.length > 0)) {
						if (file.children == null) {
							file.refreshChildren();
						}
						rec(file.children);
					}
					else {
						if (filterEnabled && file.kind == File) {
							var ext = file.name.split(".").pop().toLowerCase();

							if (!exts.contains(ext)) {
								continue;
							}
						}

						if (searchString.length > 0) {
							var range = hide.comp.FancySearch.computeSearchRanges(file.name, searchString);
							if (range == null) {
								continue;
							}
						}

						currentSearch.push(file);
					}
				}
			}


			rec(currentFolder.children);

			currentSearch.sort(FileEntry.compareFile);
		}

		for (i => _ in currentSearch) {
			var child = currentSearch[currentSearch.length - i - 1];
			if ((child.iconPath == null || child.iconPath == "loading") && child.kind == File) {
				child.iconPath = "loading";
				hide.tools.FileManager.inst.renderMiniature(child.getPath(), (path: String) -> {child.iconPath = path; fancyGallery.queueRefresh();} );
			}
		}

		fancyGallery.queueRefresh(Items);
	}

	function onFileChange(file: FileEntry) {
		fancyTree.refreshItem(file);
		queueGalleryRefresh();
	}

	override function onDisplay() {

		keys.register("undo", function() undo.undo());
		keys.register("redo", function() undo.redo());

		root = new FileEntry("res", null, Dir, onFileChange);

		root.refreshChildren();

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


						<fancy-button class="btn-collapse-folders">
							<span class="ico ico-folder-open-o" title="Display all files in subfolders"></span>
						</fancy-button>
						<fancy-separator></fancy-separator>

						<fancy-button class="btn-filter" title="Filter file by type">
							<span class="ico ico-filter"></span>
						</fancy-button>

						<fancy-button class="compact bnt-filter-dropdown" title="Choose filters">
							<span class="ico ico-chevron-down"></span>
						</fancy-button>

						<fancy-separator></fancy-separator>

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
			queueGalleryRefresh();
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
				file.refreshChildren();
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
				ser.push(file.getPath());
				for (item in selection) {
					if (item == file)
						continue;
					ser.push(item.getPath());
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
					files.push(ide.getRelPath(path));
				}

				var fileMoveData = dataTransfer.getData(dragKey);
				if (fileMoveData.length > 0) {
					try {
						var unser = haxe.Json.parse(fileMoveData);
						for (file in (unser:Array<String>)) {
							files.push(ide.getRelPath(file));
						}
					} catch (e) {
						trace("Invalid data " + e);
					}
				}

				var roots = getRoots(files);
				var outerFiles: Array<{from: String, to: String}> = [];
				var targetPath = target.getPath();
				for (root in roots) {
					var movePath = targetPath + "/" + root.split("/").pop();
					outerFiles.push({from: root, to: movePath});
				}

				function exec(isUndo: Bool) {
					if (!isUndo) {
						for (file in outerFiles) {
							// File could have been removed by the system in between our undo/redo operations
							if (sys.FileSystem.exists(ide.getPath(file.from)))
								FileTree.doRename(file.from, "/" + file.to);
						}
					} else {
						for (file in outerFiles) {
							// File could have been removed by the system in between our undo/redo operations
							if (sys.FileSystem.exists(ide.getPath(file.to)))
								FileTree.doRename(file.to, "/" + file.from);
						}
					}
				}

				undo.change(Custom(exec));
				exec(false);

				return true;
			}
		}

		fancyTree.onContextMenu = contextMenu.bind(false);

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

		fancyGallery.getThumbnail = (item : FileEntry) -> {
			if (item.kind == Dir) {
				return '<fancy-image style="background-image:url(\'res/icons/svg/big_folder.svg\')"></fancy-image>';

			}
			else if (item.iconPath == "loading") {
				return '<fancy-image class="loading" style="background-image:url(\'res/icons/loading.gif\')"></fancy-image>';
			}
			else if (item.iconPath != null) {
				var url = "file://" + item.iconPath;
				return '<fancy-image class="thumb" style="background-image:url(\'${url}\')"></fancy-image>';
			}
			else {
				return '<fancy-image style="background-image:url(\'res/icons/svg/file.svg\')"></fancy-image>';
			}
		};

		fancyGallery.getIcon = (item : FileEntry) -> {
			var ext = @:privateAccess hide.view.FileTree.getExtension(item.name);
			if (ext != null) {
				if (ext?.options.icon != null) {
					return '<div class="ico ico-${ext.options.icon}" title="${ext.options.name ?? "Unknown"}"></div>';
				}
			}
			return null;
		}

		fancyGallery.onDoubleClick = (item: FileEntry) -> {
			if (item.kind == File) {
				ide.openFile(item.getPath());
			} else {
				openDir(item, true);
			}
		}

		fancyGallery.visibilityChanged = (item: FileEntry, visible: Bool) -> {
			var path = item.getPath();
			hide.tools.FileManager.inst.setPriority(path, visible ? 1 : 0);
		}

		fancyGallery.dragAndDropInterface = {
			onDragStart: (item: FileEntry, dataTransfer: js.html.DataTransfer) -> {
				dataTransfer.setData(dragKey, haxe.Json.stringify([item.getPath()]));
				return true;
			}
		}

		fancyGallery.onContextMenu = contextMenu.bind(true);


		if (Ide.inst.ideConfig.filebrowserDebugShowMenu) {
			layout.find(".btn-collapse-folders").after(new Element('<fancy-button class="btn-debug"><span class="ico ico-bug"></span></fancy-button>'));
			var button = layout.find(".btn-debug").get(0);
			button.onclick = (e) -> {
				hide.comp.ContextMenu.createDropdown(button, [
					{
						label: "Kill render thread",
						click: () -> {
							@:privateAccess hide.tools.FileManager.inst.cleanupGenerator();
						}
					}
				]);
			};
		}

		fancyGallery.rebuild();

		openDir(root, false);


		fancyTree.onSelectionChanged = () -> {
			var selection = fancyTree.getSelectedItems();

			if (selection.length > 0) {
				openDir(selection[0], false);
			}
		}

		generateFilters();

		var savedFilters : Array<Dynamic> = getDisplayState("filterState") ?? [];
		for (filter in savedFilters) {
			if (filters.get(filter) != null) {
				filterState.set(filter, true);
			}
		}

		filterButton = layout.find(".btn-filter").get(0);
		filterButton.onclick = (e: js.html.MouseEvent) -> {
			filterEnabled = !filterEnabled;
		}
		filterEnabled = getDisplayState("filterEnabled") ?? false;


		var filterMoreButton = layout.find(".bnt-filter-dropdown").get(0);
		filterMoreButton.onclick = (e: js.html.MouseEvent) -> {
			var options : Array<hide.comp.ContextMenu.MenuItem> = [];

			for (name => info in filters) {
				options.push({
					label: name,
					checked: filterState.get(name) == true,
					click: () -> {
						if (filterState.get(name) == true) {
							filterState.remove(name);
						} else {
							filterState.set(name, true);
						}

						filterEnabled = true;
						saveFilterState();
						queueGalleryRefresh();
					},
					stayOpen: true,
				});
			}
			hide.comp.ContextMenu.createDropdown(filterMoreButton, options);
		}


		collapseSubfolders = getDisplayState("collapseSubfolders") ?? false;
		collapseSubfoldersButton = layout.find(".btn-collapse-folders").get(0);
		collapseSubfoldersButton.onclick = (e: js.html.MouseEvent) -> {
			collapseSubfolders = !collapseSubfolders;
			syncCollapseSubfolders();
		}
		syncCollapseSubfolders();

	}

	function createNew( directoryFullPath : String, ext : hide.view.FileTree.ExtensionDesc ) {

		var file = ide.ask(ext.options.createNew + " name:");
		if( file == null ) return;
		if( file.indexOf(".") < 0 && ext.extensions != null )
			file += "." + ext.extensions[0].split(".").shift();

		var newFilePath = directoryFullPath + "/" + file;

		if( sys.FileSystem.exists(newFilePath) ) {
			ide.error("File '" + file+"' already exists");
			createNew(directoryFullPath, ext);
			return;
		}

		// directory
		if( ext.component == null ) {
			sys.FileSystem.createDirectory(newFilePath);
			return;
		}

		var view : hide.view.FileView = Type.createEmptyInstance(Type.resolveClass(ext.component));
		view.ide = ide;
		view.state = { path : ide.getRelPath(newFilePath)};
		sys.io.File.saveBytes(newFilePath, view.getDefaultContent());

		ide.openFile(newFilePath);
	}

	function deleteFiles(fullPaths : Array<String>) {
		//trace(fullPaths);
		var roots = getRoots(fullPaths);
		for (fullPath in roots) {
			if( sys.FileSystem.isDirectory(fullPath) ) {
				var filesInDir = [];
				for (f in sys.FileSystem.readDirectory(fullPath)) {
					trace("files in dir :", f);
					filesInDir.push(fullPath + "/" + f);
				}
				if (filesInDir.length > 0)
					deleteFiles(filesInDir);
				sys.FileSystem.deleteDirectory(fullPath);
			} else
				sys.FileSystem.deleteFile(fullPath);
		}
	}

	function getItemAndSelection(baseItem: FileEntry, isGallery: Bool) : Array<FileEntry> {
		var items = [];
		if (baseItem != null) {
			items.push(baseItem);
		}
		if (!isGallery) {
			return items.concat(fancyTree.getSelectedItems());
		}
		return items;
	}

	// Deduplicate paths if they are contained in a directory
	// also present in paths, to simplify bulk operations
	function getRoots(fullPaths: Array<String>) {
		var dirs : Array<String> = [];

		for (file in fullPaths) {
			if(sys.FileSystem.isDirectory(ide.getPath(file))) {
				dirs.push(file);
			}
		}

		// Find the minimum ammount of files that need to be moved
		var roots: Array<String> = [];
		for (file in fullPaths) {
			var isContainedInAnotherDir = false;
			for (dir2 in dirs) {
				if (file == dir2)
					continue;
				if (StringTools.contains(file, dir2)) {
					isContainedInAnotherDir = true;
					continue;
				}
			}
			if (!isContainedInAnotherDir) {
				roots.push(file);
			}
		}

		return roots;
	}

	function contextMenu(isGallery: Bool, item: FileEntry, event: js.html.MouseEvent) {
		event.stopPropagation();
		event.preventDefault();

		if (item == null && !isGallery)
			item = root;
		if (item == null)
			item = currentFolder;

		/*currentFolder = item;
		fancyTree.selectItem(currentFolder);
		queueGalleryRefresh();*/

		var newMenu = [];
		for (e in @:privateAccess hide.view.FileTree.EXTENSIONS) {
			if (e.options.createNew != null) {
				newMenu.push({
				label: e.options.createNew,
				click : createNew.bind(item.getPath(), e),
				icon : e.options.icon,
				});
			}
		}

		var options : Array<hide.comp.ContextMenu.MenuItem> = [];

		if (item.kind == Dir) {
			options.push({
				label: "New ...",
				menu: newMenu,
			});

			options.push({
				isSeparator: true,
			});
		}

		options.push({
			label: "Delete", click: () -> {
				deleteFiles([for (file in getItemAndSelection(item, isGallery)) file.getPath()]);
			}
		});

		hide.comp.ContextMenu.createFromEvent(event, options);
	}

	function generateFilters() {
		for (ext => desc in @:privateAccess FileTree.EXTENSIONS) {
			var name = desc?.options.name;
			if (name == null)
				name = "unknown";
			var arr = hrt.tools.MapUtils.getOrPut(filters, name, {exts: [], icon: desc.options.icon});
			arr.exts.push(ext);
		}
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
			queueGalleryRefresh();
		}

		if (syncTree) {
			fancyTree.selectItem(item, true);
		}

		refreshBreadcrumbs();
	}

	static var _ = hide.ui.View.register(FileBrowser, { width : 350, position : Bottom });
}
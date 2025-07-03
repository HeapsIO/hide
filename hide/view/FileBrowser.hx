package hide.view;

import hide.tools.FileManager;
import hide.tools.FileManager.FileEntry;
typedef FileBrowserState = {
	savedLayout: Layout,
}

enum abstract Layout(String) {
	var SingleTree;
	var SingleMiniature;
	var Vertical;
	var Horizontal;
}

class FileBrowser extends hide.ui.View<FileBrowserState> {

	var fileTree: Element;
	var fileIcons: Element;

	var root : FileEntry;
	var breadcrumbs : Element;

	var layout(default, set): Layout;

	function set_layout(newLayout: Layout) : Layout {
		layout = newLayout;
		state.savedLayout = layout;
		saveState();

		element.find("file-browser").toggleClass("vertical", layout == Vertical);
		element.find("file-browser").toggleClass("single", layout == SingleTree);

		element.find(".left").width(layout == Horizontal ? "300px" : "auto");  // reset splitter width
		element.find(".left").height(layout == Vertical ? "300px" : "");  // reset splitter height
		element.find(".left").toggle(layout != SingleMiniature);
		element.find(".right").toggle(layout != SingleTree);
		element.find(".splitter").toggle(layout != SingleTree && layout != SingleMiniature);
		resize.layoutDirection = layout == Horizontal ? Horizontal : Vertical;

		fullRefresh();

		return newLayout;
	}


	override function new(state) {
		super(state);
		saveDisplayKey = "fileBrowser";
	}

	override function onDragDrop(items:Array<String>, isDrop:Bool, event:js.html.DragEvent):Bool {
		return false;
	}

	override function buildTabMenu():Array<hide.comp.ContextMenu.MenuItem> {
		var menu = super.buildTabMenu();

		menu.push({isSeparator: true});
		menu.push({
			label: "Display",
			menu: [
				{
					label: "File Tree",
					radio: () -> layout == SingleTree,
					click: () -> layout = SingleTree,
					stayOpen: true,
				},
				{
					label: "Gallery",
					radio: () -> layout == SingleMiniature,
					click: () -> layout = SingleMiniature,
					stayOpen: true,
				},
						{
					label: "Horizontal",
					radio: () -> layout == Horizontal,
					click: () -> layout = Horizontal,
					stayOpen: true,
				},
				{
					label: "Vertical",
					radio: () -> layout == Vertical,
					click: () -> layout = Vertical,
					stayOpen: true,
				},
			]
		});

		menu.push({
			label: "Dock",
			menu: [{
				label: "Left",
				click: () -> {
					saveState();
					var newState : FileBrowserState = haxe.Json.parse(haxe.Json.stringify(state));
					newState.savedLayout = Vertical;
					close();
					ide.open("hide.view.FileBrowser", newState, Left);
				}
			},
			{
				label: "Bottom",
				click: () -> {
					saveState();
					var newState : FileBrowserState = haxe.Json.parse(haxe.Json.stringify(state));
					newState.savedLayout = Horizontal;
					close();
					ide.open("hide.view.FileBrowser", newState, Bottom);
				}
			},
			]
		});

		return menu;
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
	var ignorePatterns: Array<EReg> = [];

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
							throw "null children";
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

		currentSearch = currentSearch.filter(filterFiles);

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
		fancyTree.invalidateChildren(file);
		queueGalleryRefresh();
	}

	function fullRefresh() {
		fancyTree.rebuildTree();
		queueGalleryRefresh();
	}

	var resize : hide.comp.ResizablePanel;

	function filterFiles(entry: FileEntry) {
		for (excl in ignorePatterns) {
			if (excl.match(entry.name))
				return false;
		}
		return return true;
	}


	override function onDisplay() {

		var exclPatterns : Array<String> = ide.currentConfig.get("filetree.excludes", []);
		ignorePatterns = [];
		for(pat in exclPatterns)
			ignorePatterns.push(new EReg(pat, "i"));

		keys.register("undo", function() undo.undo());
		keys.register("redo", function() undo.redo());

		root = FileManager.inst.fileRoot;

		var browserLayout = new Element('
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

		resize = new hide.comp.ResizablePanel(Horizontal, element.find(".left"), After);

		breadcrumbs = browserLayout.find("fancy-breadcrumbs");

		var search = new hide.comp.FancySearch(null, browserLayout.find(".fb-search"));
		search.onSearch = (string, _) -> {
			searchString = string;
			queueGalleryRefresh();
		};

		var btnParent = browserLayout.find(".btn-parent");
		btnParent.get(0).onclick = (e: js.html.MouseEvent) -> {
			if (currentFolder.parent != null) {
				openDir(currentFolder.parent, true);
			}
		}

		fancyTree = new hide.comp.FancyTree<FileEntry>(browserLayout.find(".left"), "fileBrowserTree");
		fancyTree.getChildren = (file: FileEntry) -> {
			if (file == null)
				return [root];
			if (file.kind == File)
				return null;
			if (file.disposed)
				throw "disposed file";
			if (file.children == null)
				throw "null children";

			if (layout == SingleTree) {
				return file.children.filter(filterFiles);
			}
			return file.children.filter((file) -> file.kind == Dir && filterFiles(file));
		};
		//fancyTree.hasChildren = (file: FileEntry) -> return file.kind == Dir;
		fancyTree.getName = (file: FileEntry) -> return file?.name;
		fancyTree.getUniqueName = (file: FileEntry) -> file?.getRelPath();

		fancyTree.getIcon = (item : FileEntry) -> {
			if (item.kind == Dir)
				return '<div class="ico ico-folder"></div>';
			var ext = @:privateAccess hide.view.FileTree.getExtension(item.name);
			if (ext != null) {
				if (ext?.options.icon != null) {
					return '<div class="ico ico-${ext.options.icon}" title="${ext.options.name ?? "Unknown"}"></div>';
				}
			}
			return null;
		}

		fancyTree.onNameChange = renameHandler;

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
				if (target.kind != Dir)
					target = target.parent;

				var files : Array<String> = [];
				for (file in dataTransfer.files) {
					var path : String = untyped file.path; //file.path is an extension from nwjs or node
					path = StringTools.replace(path, "\\", "/");
					var rel = ide.getRelPath(path);
					files.push(rel);
				}

				var fileMoveData = dataTransfer.getData(dragKey);
				if (fileMoveData.length > 0) {
					try {
						var unser = haxe.Json.parse(fileMoveData);
						for (file in (unser:Array<String>)) {
							var rel = ide.getRelPath(file);
							files.push(rel);
						}
					} catch (e) {
						trace("Invalid data " + e);
					}
				}

				if (files.length == 0)
					return false;

				moveFiles(target.getRelPath(), files);

				return true;
			}
		}

		fancyTree.onContextMenu = contextMenu.bind(false);

		fancyTree.rebuildTree();
		fancyTree.openItem(root, true);

		fancyTree.onDoubleClick = (item: FileEntry) -> {
			if (item.kind == File) {
				ide.openFile(item.getPath());
			}
		}

		var right = browserLayout.find(".right");
		right.get(0).onkeydown = (e: js.html.KeyboardEvent) -> {
			if (hide.ui.Keys.matchJsEvent("search", e, ide.currentConfig)) {
				e.stopPropagation();
				e.preventDefault();

				search.focus();
				return;
			}
		}

		fancyGallery = new hide.comp.FancyGallery<FileEntry>(null, browserLayout.find(".right fancy-gallery"));
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
			browserLayout.find(".btn-collapse-folders").after(new Element('<fancy-button class="btn-debug"><span class="ico ico-bug"></span></fancy-button>'));
			var button = browserLayout.find(".btn-debug").get(0);
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

		openDir(root, false);


		fancyTree.onSelectionChanged = () -> {
			var selection = fancyTree.getSelectedItems();

			// Sinc folder view with other filebrowser in SingleMiniature mode
			if (selection.length > 0) {
				openDir(selection[0], false);
				var views = ide.getViews(hide.view.FileBrowser);
				for (view in views) {
					if (view == this)
						continue;
					if (view.layout == SingleMiniature) {
						view.openDir(selection[0], false);
					}
				}
			}
		}

		generateFilters();

		var savedFilters : Array<Dynamic> = getDisplayState("filterState") ?? [];
		for (filter in savedFilters) {
			if (filters.get(filter) != null) {
				filterState.set(filter, true);
			}
		}

		filterButton = browserLayout.find(".btn-filter").get(0);
		filterButton.onclick = (e: js.html.MouseEvent) -> {
			filterEnabled = !filterEnabled;
		}
		filterEnabled = getDisplayState("filterEnabled") ?? false;


		var filterMoreButton = browserLayout.find(".bnt-filter-dropdown").get(0);
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
		collapseSubfoldersButton = browserLayout.find(".btn-collapse-folders").get(0);
		collapseSubfoldersButton.onclick = (e: js.html.MouseEvent) -> {
			collapseSubfolders = !collapseSubfolders;
			syncCollapseSubfolders();
		}
		syncCollapseSubfolders();

		FileManager.inst.onFileChangeHandlers.push(onFileChange);

		layout = state.savedLayout ?? Horizontal;
	}

	function renameHandler(item: FileEntry, newName: String) {
		if (newName.indexOf(".") == -1 && item.name.indexOf(".") >= 0) {
			newName += "." + item.name.split(".").pop();
		}

		var newPath = item.getRelPath().split("/");
		newPath.pop();
		newPath.push(newName);
		renameFile(item.getRelPath(), newPath.join("/"));
	}

	/**
		Path is relative to res folder
	**/
	function moveFiles(targetFolder: String, files: Array<String>) {
		var roots = getRoots(files);
		var outerFiles: Array<{from: String, to: String}> = [];
		for (root in roots) {
			var movePath = targetFolder + "/" + root.split("/").pop();
			outerFiles.push({from: root, to: movePath});
		}

		var exec = execMoveFiles.bind(outerFiles);

		undo.change(Custom(exec));
		exec(false);
	}

	static function execMoveFiles(operations: Array<{from: String, to: String}>, isUndo: Bool) : Void {
		if (!isUndo) {
			for (file in operations) {
				// File could have been removed by the system in between our undo/redo operations
				if (sys.FileSystem.exists(hide.Ide.inst.getPath(file.from))) {
					try {
						FileTree.doRename(file.from, "/" + file.to);
					} catch (e) {
						hide.Ide.inst.quickError('move file ${file.from} -> ${file.to} failed : $e');
					}
				}
			}
		} else {
			for (file in operations) {
				// File could have been removed by the system in between our undo/redo operations
				if (sys.FileSystem.exists(hide.Ide.inst.getPath(file.to))) {
					try {
						FileTree.doRename(file.to, "/" + file.from);
					} catch (e) {
						hide.Ide.inst.quickError('move file ${file.from} -> ${file.to} failed : $e');
					}
				}
			}
		}
	}

	function renameFile(oldPath: String, newPath: String) {
		var exec = execMoveFiles.bind([{from: oldPath, to: newPath}]);
		undo.change(Custom(exec));
		exec(false);
	}

	override function destroy() {
		super.destroy();
		FileManager.inst.onFileChangeHandlers.remove(onFileChange);
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

	function getItemAndSelection(baseItem: FileEntry, isGallery: Bool) : Array<FileEntry> {
		var items = [];
		if (baseItem != null) {
			items.push(baseItem);
		}
		if (!isGallery) {
			for (item in fancyTree.getSelectedItems()) {
				hide.tools.Extensions.ArrayExtensions.pushUnique(items, item);
			}
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

		// if the user clicked on the background of the file tree, don't display anything
		if (item == null && !isGallery)
			return;

		// if the user selected the "current" folder in the gallery
		// prevent move/delete ... operations on it to avoid confusion and wrong operations
		var implicitFolder = false;
		if (item == null) {
			implicitFolder = true;
			item = currentFolder;
		}

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

			if (!isGallery) {
				options.push({
					label: "Collapse",
					click: fancyTree.collapseItem.bind(item),
				});

				options.push({
					label: "Collapse All",
					click: () -> {
						for (child in root.children) {
							fancyTree.collapseItem(child);
						}
					}
				});
			}
		}

		if (!implicitFolder) {
			if (options[options.length-1] != null && !options[options.length-1].isSeparator) {
				options.push({
					isSeparator: true,
					menu: newMenu,
				});
			}

			options.push({
				label: "Copy Path",
				click: () -> ide.setClipboard(item.getRelPath())
			});

			options.push({
				label: "Copy Absolute Path",
				click: () -> ide.setClipboard(item.getPath())
			});

			options.push({
				label : "Open in Explorer",
				click : () -> Ide.showFileInExplorer(item.getPath())
			});

			options.push({ label : "Find References", click : onFindPathRef.bind(item.getRelPath())});

			options.push({
				isSeparator: true,
				menu: newMenu,
			});

			options.push({
				label: "Clone", click: () -> {
					hide.tools.FileManager.inst.cloneFile(item);
				}
			});

			options.push({
				label: "Rename", click: () -> {
					if (!isGallery) {
						fancyTree.rename(item);
					} else {
						fancyGallery.rename(item, (newName:String) -> renameHandler(item, newName));
					}
				}, keys: config.get("key.rename"),
			});

			options.push({
				label: "Move", click: () -> {
					ide.chooseDirectory(function(dir) {
						var selection = getItemAndSelection(item, isGallery);
						var roots = FileManager.inst.getRoots(selection);
						moveFiles(dir, [for (file in roots) file.getRelPath()]);
					});
				}
			});


			options.push({
				label: "Delete", click: () -> {
					var selection = getItemAndSelection(item, isGallery);
					var roots = FileManager.inst.getRoots(selection);
					if(ide.confirm("Confirm deleting files : " + [for (r in roots) r.getRelPath()].join("\n") + '\n(Cannot be undone)'))
						FileManager.inst.deleteFiles(getItemAndSelection(item, isGallery));
				}
			});

			options.push({ label: "Replace Refs With", click : function() {
				ide.chooseFile(["*"], (newPath: String) -> {
					var selection = [for (file in getItemAndSelection(item, isGallery)) file.getRelPath()];
					if(ide.confirm('Replace all refs of $selection with $newPath ? This action can not be undone')) {
						for (oldPath in selection) {
							FileTree.replacePathInFiles(oldPath, newPath, false);
						}
						ide.message("Done");
					}
				});
			}});

		}


		hide.comp.ContextMenu.createFromEvent(event, options);
	}

	function onFindPathRef(path: String) {
		var refs = ide.search(path, ["hx", "prefab", "fx", "cdb", "json", "props", "ddt"], ["bin"]);
		ide.open("hide.view.RefViewer", null, null, function(view) {
			var refViewer : hide.view.RefViewer = cast view;
			refViewer.showRefs(refs, path, function() {
				ide.openFile(path);
			});
		});
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
package hrt.ui;

#if hui

import hrt.tools.FileManager;

typedef File = FileEntry;

enum abstract BrowserMode(String) {
	var FileTree;
	var Gallery;
	var Horizontal;
	var Vertical;
}

class HuiFileBrowser extends HuiElement {
	var rootFile: File;

	var mainToolbar: HuiElement;
	var mainToolbarWidget: HuiFileBrowserMainToolbarWidget;
	var galleryToolbar: HuiElement;
	var secondToolbarWidget: HuiFileBrowserSecondToolbarWidget;
	var tree: HuiTree<File>;
	var splitter: HuiSplitContainer;
	var galleryWidget: HuiFileBrowserGalleryWidget;
	var gallery(get, never): HuiVirtualGrid<File>;
	function get_gallery() {return cast galleryWidget.gallery;};
	var noResults : HuiFileBrowserNoResultWidget;
	var rootPath: String;
	var needRefresh: Bool = false;
	var galleryList: Array<File> = null;
	var gallerySearchRanges: Array<hide.Search.SearchRanges> = null;
	var gallerySelection: Map<File, Bool> = [];
	var galleryLastClick: File = null;
	var galleryDelayRename: {file: File, callback : String -> Void, range: HuiTree.SelectionRange} = null;

	var navigationHistory: Array<File> = [];
	var navigationHistoryPos: Int = 0;

	var currentHover: File = null;
	var fullThumbnailPopup: HuiPopup;
	var fullThumbnailItem: HuiFileBrowserGalleryItem;

	/**
		Never update this direcly, it's only an alias for tree.selectedItems or gallerySelection depending on
		which one is focused, but it needs to be cached in case the focus has changed in the middle of the frame
	**/
	var currentSelectedFiles : Array<File> = [];

	@:p public var mode(default, set): BrowserMode = FileTree;

	var zoom : Int = 5;
	static final zoomLevels = [32, 64, 96, 128,192, 256, 384, 512];

	function set_mode(v: BrowserMode) {
		mode = v;
		refreshLayout();
		return mode;
	}

	var fileManager = FileManager.inst;

	/**
		Wait for this path to become available in the FileManager, and then
		do a rename action in the filebrowser. This is needed because we rely on
		the filemanager filewatch to refresh the browser (in order to not have to manually
		update the Filemanager internal filesystem manually when we add files).
	**/
	var delayRename: {path: String, isTree: Bool} = null;
	var delaySelect: {paths: Array<String>, isTree: Bool} = null;
	var delayTargetTree: Bool;

	static public final fileDragOp = "fileDrag";

	public dynamic function onModeChange() {

	}

	public function new(rootPath: String, ?parent) {
		super(parent);
		initComponent();
		saveDisplayKey = "filebrowser";

		this.rootPath = rootPath;

		registerCommand(HuiCommands.delete, View, () -> deleteFiles(getSelectedFiles()));
		registerCommand(HuiCommands.rename, View, () -> renameFiles(getSelectedFiles(), tree.focused));
		registerCommand(HuiCommands.duplicate, View, () -> duplicateFiles(getSelectedFiles(), tree.focused));
		registerCommand(HuiCommands.copy, View, () -> copyFiles(getSelectedFiles()));
		registerCommand(HuiCommands.paste, View, () -> pasteInFiles(getSelectedFiles(), tree.focused));

		tree = new HuiTree<File>();
		tree.getItemChildren = getItemChild;
		tree.getItemName = getItemName;
		tree.getItemIcon = getItemIcon;
		tree.onUserSelectionChanged = treeSelectionChanged;
		tree.onItemDoubleClick = (e, file) -> onOpen(file);

		tree.dragAndDropInterface = {
			onDragStart: (item) -> {
				itemStartDrag();
			},
			getItemDropFlags: function(item, op) : hrt.ui.HuiTree.DropFlags {
				if (op.type == fileDragOp) {
					if (isDragValid(item, op)) {
						if (item.kind == Dir) {
							return hrt.ui.HuiTree.DropFlag.Reorder | hrt.ui.HuiTree.DropFlag.Reparent;
						}
						return hrt.ui.HuiTree.DropFlag.Reorder;
					}
				}
				return hrt.ui.HuiTree.DropFlags.ofInt(0);
			},
			onDrop: (target: hrt.tools.FileManager.FileEntry, where, op:HuiDragOp) -> {
				if (where != Inside) {
					target = target.parent;
				}
				fileOnDrop(target, op, true);
			}
		};

		tree.onItemContextMenu = itemContextMenu;

		tree.onAfterLineCreation = (item, element) -> {
			element.onOver = (e) -> {
				currentHover = item;
			}

			element.onOut = (e) -> {
				currentHover = null;
			}
		};

		tree.unregisterCommand(hrt.ui.HuiCommands.search);

		registerCommand(hrt.ui.HuiCommands.search, ElementAndChildren, () -> {
			secondToolbarWidget.searchBar.focus();
		});

		galleryWidget = new HuiFileBrowserGalleryWidget();
		galleryWidget.noResults.clearSearchBtn.onClick = (e) -> {
			secondToolbarWidget.searchBar.text = "";
			secondToolbarWidget.searchBar.onChange(false);
		}

		galleryWidget.noResults.searchAllBtn.onClick = (e) -> {
			navigateTo(rootFile, true);
		}

		// gallery setup

		@:privateAccess {
			var oldScroll = gallery.virtualList.onWheel;
			gallery.virtualList.onWheel = (e) -> {
				if (hxd.Key.isDown(hxd.Key.CTRL)) {
					e.cancel = true;
					e.propagate = false;

					zoom += e.wheelDelta < 0 ? 1 : -1;
					zoom = hxd.Math.iclamp(zoom, 0, zoomLevels.length-1);
					refreshZoom();
				} else {
					oldScroll(e);
				}
			}
		}

		gallery.onClick = (e) -> {
			if (e.button == hxd.Key.MOUSE_LEFT || e.button == hxd.Key.MOUSE_RIGHT) {
				if (!hxd.Key.isDown(hxd.Key.CTRL)) {
					gallerySelection.clear();
					galleryLastClick = null;
					updateSelectedFiles();
					refreshGalleryItems();
				}

				if (e.button == hxd.Key.MOUSE_RIGHT) {
					itemContextMenu(currentDir());
				}
			}
		}

		gallery.onDragOver = (e) -> {
			fileOnDragOver(currentDir(), e);
			if (e.acceptDrop) {
				gallery.dom.addClass("can-drop-file");
			}
		}

		gallery.onDragOut = (e) -> {
			gallery.dom.removeClass("can-drop-file");
		}

		gallery.onDragOver = (e) -> {
			fileOnDragOver(currentDir(), e);
		}

		gallery.generateItem = generateGalleryItem;

		zoom = getDisplayState("zoom", 4);
		refreshZoom();

		noResults = new HuiFileBrowserNoResultWidget();

		// Splitter setup
		splitter = new HuiSplitContainer();

		mainToolbar = new HuiToolbar();
		mainToolbar.dom.setId("main-toolbar");
		mainToolbarWidget = new HuiFileBrowserMainToolbarWidget(mainToolbar);

		mainToolbarWidget.splitButton.onClick = (e) -> {
			uiBase.openMenu([
				{label: "File tree", radio: () -> mode == FileTree, stayOpen: true, click: () -> {mode = FileTree; onModeChange();}},
				{label: "Gallery", radio: () -> mode == Gallery, stayOpen: true,  click: () -> {mode = Gallery; onModeChange();}},
				{label: "Horizontal", radio: () -> mode == Horizontal, stayOpen: true,  click: () -> {mode = Horizontal; onModeChange();}},
				{label: "Vertical", radio: () -> mode == Vertical, stayOpen: true,  click: () -> {mode = Vertical; onModeChange();}},
			], {}, {object: Element(mainToolbarWidget.splitButton), directionX: StartInside, directionY: EndOutside});
		}

		mainToolbarWidget.prevBtn.onClick = (e) -> {
			navigateBack();
		}

		mainToolbarWidget.forwardBtn.onClick = (e) -> {
			navigateForward();
		}

		mainToolbarWidget.parentBtn.onClick = (e) -> {
			var parent = currentDir().parent;
			if (parent != null)
				navigateTo(parent, true);
		}


		galleryToolbar = new HuiToolbar();
		secondToolbarWidget = new HuiFileBrowserSecondToolbarWidget(galleryToolbar);

		secondToolbarWidget.searchBar.onChange = (e) -> {
			galleryList = null;
			markRefresh();
		}

		secondToolbarWidget.searchBar.onBeforeKeyDown = (e) -> {
			if (mode == FileTree) {
				tree.keyDownHandler(true, e);
			}
		}

		refreshLayout();

		markRefresh();

		fileManager.watchFileChange(onFileChange);

		onAfterReflow = () -> {
			updateToolbarCompactMode();
		}
		updateToolbarCompactMode();
	}

	function isDragValid(item: File, op: HuiDragOp) {
		var item = item.kind == Dir ? item : item.parent;
		var paths: Array<String> = cast op.data;
		var files = [for (path in paths) hrt.tools.FileManager.inst.getFileEntry(path)];
		if (files.contains(item))
			return false;
		for (file in files) {
			if (item.children?.contains(file))
				return false;
			if (file.contains(item))
				return false;
		}
		return true;
	}

	function fileOnDragOver(item: File, op: HuiDragOp) {
		op.acceptDrop = false;
		if (op.type == fileDragOp) {
			op.acceptDrop = isDragValid(item, op);
		}
	}

	function fileOnDrop(target: File, op: HuiDragOp, isTree: Bool) {
		if (op.type == fileDragOp) {
			var folder = target.kind == Dir ? target : target.parent;

			var paths: Array<String> = cast op.data;
			var files = [for (path in paths) hrt.tools.FileManager.inst.getFileEntry(path)];
			files = files.filter((f) -> f != null);
			var roots = hrt.tools.FileManager.inst.getRoots(files);

			var operations = [];
			var operationsRev = [];
			for (root in roots) {
				if (!root.contains(folder)) {
					operations.push({from: root.getPath(), to: folder.getPath() + "/" + root.name});
				}
			}

			operations = operations.filter((f) -> f.from != f.to);
			if (operations.length == 0)
				return;

			getView().undo.run(actionMoveFilesAbs(operations), false);
			delaySelect = {paths: [for (op in operations) op.to], isTree: isTree};
		}
	}

	function updateToolbarCompactMode() {
		mainToolbar.dom.toggleClass("vertical", innerWidth < 600);
	}

	function refreshZoom() {
		var zoomPx = zoomLevels[zoom];
		gallery.itemBaseHeight = zoomPx + 36;
		gallery.itemBaseWidth = zoomPx + 8;
		@:privateAccess gallery.virtualList.clear();

		saveDisplayState("zoom", zoom);
	}

	function treeSelectionChanged() {
		updateSelectedFiles();
		navigateTo(tree.getSelectedItems()[0] ?? rootFile, false);
	}

	function generateGalleryItem(file: File) : HuiElement {
		return new HuiFileBrowserGalleryItem(file, this);
	}

	function refreshLayout() {
		removeChildElements();
		splitter.removeChildElements();

		mainToolbar.removeChildElements();
		galleryToolbar.removeChildElements();
		mainToolbar.addChild(mainToolbarWidget);

		switch(mode) {
			case FileTree:
				addChild(mainToolbar);
				mainToolbar.addChild(secondToolbarWidget);
				addChild(tree);
				mainToolbarWidget.splitButtonIcon.setIcon("split_tree");
			case Gallery:
				addChild(mainToolbar);
				mainToolbar.addChild(secondToolbarWidget);
				addChild(galleryWidget);
				addChild(noResults);
				mainToolbarWidget.splitButtonIcon.setIcon("split_gallery");
			case Horizontal | Vertical:
				addChild(mainToolbar);
				addChild(splitter);

				var first = new HuiElement(splitter);
				var second = new HuiElement(splitter);
				first.addChild(tree);
				first.dom.setId("tree-container");
				galleryToolbar.addChild(secondToolbarWidget);
				second.addChild(galleryToolbar);
				second.addChild(galleryWidget);
				second.addChild(noResults);

				second.dom.setId("gallery-container");

				splitter.addChild(first);
				splitter.addChild(second);

				if (mode == Horizontal) {
					@:privateAccess splitter.direction = Horizontal;
					mainToolbarWidget.splitButtonIcon.setIcon("split_horizontal");
				}
				else {
					mainToolbarWidget.splitButtonIcon.setIcon("split_vertical");
					@:privateAccess splitter.direction = Vertical;
				}
		}
		markRefresh();
	}

	function actionMoveFilesAbs(operations: Array<{from: String, to: String}>) : hrt.tools.Undo.Action {
		var operationsRev = [];
		for (op in operations) {
			operationsRev.push({to: op.from, from: op.to});
		}

		return (isUndo) -> FileManager.doRenameAbs(isUndo ? operationsRev : operations);
	}

	override function onRemove() {
		fileManager.unwatchFileChange(onFileChange);
		super.onRemove();
	}

	public function onFileChange(file: File) {
		tree.rebuild(file == rootFile ? null : file);
		var cur = currentDir();
		if (file == cur || file.parent == cur) {
			galleryList = null;
			for (k => _ in gallerySelection.copy()) {
				if (k.disposed) {
					gallerySelection.remove(k);
				}
			}
			markRefresh();
		}
	}

	public function markRefresh() {
		needRefresh = true;
	}

	public function refreshGalleryItems() {
		@:privateAccess
		var elems = gallery.virtualList.findAll((f) -> Std.downcast(f, HuiFileBrowserGalleryItem));
		for (elem in elems) {
			elem.refresh();
		}
	}

	function itemContextMenu(file: File) {
		if (file == null)
			file = rootFile;

		var selection = getSelectedFiles();

		/*var allExts = @:privateAccess Lambda.filter(hrt.prefab.Prefab.registry, (inf) -> inf.extension != null);*/

		var isTree = tree.focused;

		var createMenu : Array<hrt.ui.HuiMenu.MenuItem> = [{
			label: "Directory",
			click: () -> createNewDirectory(file, isTree),
		},{
			label: "Prefab",
			click: () -> createNewFile(file, "New Prefab", "prefab", hide.Ide.inst.toJSON(@:privateAccess new hrt.prefab.Prefab(null, null).serialize()), isTree)
		},{
			label: "Material Library",
			click: () -> createNewFile(file, "New Material Library", "matlib", hide.Ide.inst.toJSON(@:privateAccess new hrt.prefab.MaterialLibrary(null, null).serialize()), isTree)
		}];

		var items : Array<hrt.ui.HuiMenu.MenuItem> = [{label: "New ...", menu: createMenu}];

		items.push({isSeparator: true});

		items.push({label: "Copy Path", click: () -> hide.Ide.inst.setClipboard(file.getRelPath(), null)});
		items.push({label: "Copy Absolute Path", click: () -> hide.Ide.inst.setClipboard(file.getPath(), null)});
		items.push({label: "Open In Explorer", click: () -> hide.tools.IdeData.showFileInExplorer(file.getPath())});

		items.push({isSeparator: true});

		var duplicate = HuiMenu.itemFromCommand(HuiCommands.duplicate, this);
		duplicate.enabled = selection.length > 0;
		duplicate.click = duplicateFiles.bind(selection, isTree);
		items.push(duplicate);

		var copy = HuiMenu.itemFromCommand(HuiCommands.copy, this);
		copy.enabled = selection.length > 0;
		copy.click = copyFiles.bind(selection);
		items.push(copy);

		var paste = HuiMenu.itemFromCommand(HuiCommands.paste, this);
		paste.enabled = hide.Ide.inst.getClipboardData()?.type == "file";
		paste.click = pasteInFiles.bind(selection, isTree);
		items.push(paste);

		var rename = HuiMenu.itemFromCommand(HuiCommands.rename, this);
		rename.enabled = selection.length > 0 && !selection.contains(rootFile);
		rename.click = renameFiles.bind(selection, isTree);
		items.push(rename);

		var delete = HuiMenu.itemFromCommand(HuiCommands.delete, this);
		delete.enabled = selection.length > 0 && !selection.contains(rootFile);
		delete.click = deleteFiles.bind(selection);
		items.push(delete);

		items.push({label: "Trigger thumbnail", click: () -> @:privateAccess FileManager.inst.renderMiniature(file, (p) -> trace("Miniature renderer : " + p))});

		uiBase.contextMenu(items);
	}

	function copyFiles(files: Array<File>) {
		hide.Ide.inst.setClipboard(null, {
			type: "file",
			files: [for (file in files) file.getPath()],
		});
	}

	function pasteInFiles(files: Array<File>, isTree: Bool) {
		var data = hide.Ide.inst.getClipboardData();
		if (data == null || data.type != "file")
			return;

		var target = files[0] ?? rootFile;
		if (target.kind != Dir) {
			target = target.parent;
		}

		copyFilesToFolder(cast data.files, target.getPath(), isTree);
	}

	function duplicateFiles(files: Array<File>, isTree) {
		var sources = [for (file in files) file.getPath()];
		var destinations = ensureUniquePaths(sources);

		var operations = [for (i in 0...sources.length) {source: sources[i], destination: destinations[i]}];

		getView().undo.run(actionCopyFiles(operations, isTree), false);
	}

	function createNewDirectory(parent: File, isTree: Bool) {
		var dir = parent;
		if (dir.kind != Dir) {
			dir = parent.parent;
		}
		var basePath = dir.path + '/' + "New directory";
		var pathToCreate = basePath;
		var tries = 0;
		while(sys.FileSystem.exists(pathToCreate)) {
			tries ++;
			pathToCreate = basePath + ' ($tries)';
		}

		try {
			sys.FileSystem.createDirectory(pathToCreate);
		} catch(e) {
			hide.Ide.showError('Couldn\'t create directory : $e');
			return;
		}

		getView().undo.record((isUndo) -> {
			if (isUndo) {
				try {
					deletePathInternal(pathToCreate);
				} catch(e) {
					hide.Ide.showError('Couldn\'t create directory : $e');
					return;
				}
			} else {
				try {
					sys.FileSystem.createDirectory(pathToCreate);
				} catch(e) {
					hide.Ide.showError('Couldn\'t create directory : $e');
					return;
				}
			}
			markRefresh();
		}, false);

		delayRename = {path: pathToCreate, isTree: isTree};
	}

	public function createNewFile(parent: File, baseName: String, extension: String, baseContent: String, isTree: Bool) {
		var dir = parent;
		if (dir.kind != Dir) {
			dir = parent.parent;
		}
		var basePath = dir.path + '/' + baseName + '.' + extension;
		var pathToCreate = basePath;
		var tries = 0;
		while(sys.FileSystem.exists(pathToCreate)) {
			tries ++;
			pathToCreate = dir.path + '/' + baseName + ' ($tries).' + extension;
		}

		try {
			sys.io.File.saveContent(pathToCreate, baseContent);
		} catch(e) {
			hide.Ide.showError('Couldn\'t create directory : $e');
			return;
		}

		getView().undo.record((isUndo) -> {
			if (isUndo) {
				try {
					deletePathInternal(pathToCreate);
				} catch(e) {
					hide.Ide.showError('Couldn\'t create directory : $e');
					return;
				}
			} else {
				try {
					sys.io.File.saveContent(pathToCreate, baseContent);
				} catch(e) {
					hide.Ide.showError('Couldn\'t create directory : $e');
					return;
				}
			}
			markRefresh();
		}, false);

		delayRename = {path: pathToCreate, isTree: isTree};
	}


	function getSelectedFiles() : Array<File> {
		return currentSelectedFiles;
	}

	function updateSelectedFiles() {
		if (tree.focused) {
			currentSelectedFiles = tree.getSelectedItems();
		}
		else if (gallery.focused) {
			currentSelectedFiles = [for (k in gallerySelection.keys()) k];
		}
		else {
			currentSelectedFiles = [];
		}
	}

	function deleteFiles(files: Array<File>) {
		var message = if (files.length == 1) files[0].name else '${files.length} files';
		uiBase.confirm('Really delete $message ? (Cannot be undone)', Cancel | Ok, (button) -> {
			if (button == Ok) {
				try {
					hrt.tools.FileManager.deleteFilesPaths([for(file in files) file.getPath()]);
				} catch (e) {
					hide.Ide.showError("" + e);
				}
				markRefresh();
			}
		});
	}

	function renameFiles(files: Array<File>, isTree: Bool) {
		if (files.length > 0) {
			promptRenameFile(files[0], isTree);
		}
	}

	function actionMoveFiles(targetPath: String, paths: Array<String>) {
		for (path in paths) {
			if (StringTools.startsWith(targetPath, path)) {
				hide.Ide.showError('Cannot move $path as it contains destination folder ($targetPath)');
				return;
			}
		}
	}

	/**
		Path in absolute form
	**/
	function actionRenameFile(oldPath: String, newPath: String, isTree: Bool) : hrt.tools.Undo.Action {
		return (isUndo) -> {
			var from = isUndo ? newPath : oldPath;
			var to = isUndo ? oldPath : newPath;
			var entry = fileManager.getFileEntry(from);
			var wasSelected = false;
			if (entry != null) {
				if (isTree) {
					wasSelected = tree.isItemSelected(entry);
				} else {
					wasSelected = gallerySelection.exists(entry);
				}
			} else {
				wasSelected = delaySelect?.paths.contains(from);
			}

			try {
				FileManager.doRenameAbs([{from: from, to: to}]);
			} catch(e) {
				hide.Ide.showError('Couldn\'t rename $from -> $to : $e');
				return;
			}

			if (wasSelected) {
				delaySelect ??= {paths: [], isTree: isTree};
				delaySelect.paths.push(to);
			}
		}
	}

	static var simpleFilenameRegex = ~/(.*) \(\d+\)/;

	function copyFilesToFolder(filePaths: Array<String>, folderPath: String, isTree: Bool) {

		var destinations = [];
		for (path in filePaths) {
			var dest = new haxe.io.Path(path);
			dest.dir = folderPath;
			destinations.push(dest.toString());
		}

		destinations = ensureUniquePaths(destinations);

		var operations = [for (i in 0...filePaths.length) {source: filePaths[i], destination: destinations[i]}];

		getView().undo.run(actionCopyFiles(operations, isTree), false);
	}

	/**
		Ensure that all the paths in the given array are unique between themselves and files on disk
	**/
	function ensureUniquePaths(paths: Array<String>) : Array<String> {
		var newPaths = [];

		for (i => path in paths) {
			var dest = new haxe.io.Path(path);
			var destPathBase = dest.toString();

			// return name to base
			if (simpleFilenameRegex.match(dest.file)) {
				dest.file = simpleFilenameRegex.matched(1);
			}

			var baseFile = dest.file;

			var tries = 0;
			// deduplicate paths
			var newPath = dest.toString();
			while(sys.FileSystem.exists(newPath) || newPaths.contains(newPath)) {
				tries += 1;
				dest.file = baseFile + ' ($tries)';
				newPath = dest.toString();
			}
			newPaths.push(newPath);
		}

		return newPaths;
	}

	function actionCopyFiles(operations: Array<{source: String, destination: String}>, isTree: Bool) {
		var operations = operations.copy();
		var selection = [for (file in getSelectedFiles()) file.getPath()];

		if (operations.length == 1)
			delayRename = {path: operations[0].destination, isTree: isTree};

		return (isUndo) -> {
			if (isUndo) {
				hrt.tools.FileManager.deleteFilesPaths([for (op in operations) op.destination]);
				delaySelect = {paths: selection, isTree: isTree};
			} else {
				hrt.tools.FileManager.copyFilesPaths(operations);
				delaySelect = {paths: [for (op in operations) op.destination], isTree: isTree};
			}
			markRefresh();
		}
	}

	function promptRenameFile(file: File, isTree: Bool) {
		var path = new haxe.io.Path(file.path);
		var callback = (newName) -> {
			if (path.file + "." + path.ext != newName) {
				var newPath = haxe.io.Path.join([path.dir, newName]);
				getView().undo.run(actionRenameFile(file.path, newPath, isTree), false);
			}
		};
		var range = {start: 0, length: path.file.length}; /* Select before the . of the file*/

		if (isTree) {
			tree.rename(file, callback, range);
		} else {
			galleryRename(file, callback, range);
		}
	}

	function galleryRename(file, callback: String -> Void, ?range: HuiTree.SelectionRange) {
		galleryList = null;
		galleryDelayRename = {callback: callback, file: file, range: range}
		markRefresh();
	}

	function itemStartDrag() {
		var filePaths = [for (file in getSelectedFiles()) file.path];
		var op = startDrag(fileDragOp, filePaths);
		op.setPreviewText(filePaths.join("<br/>"));
	}

	override function update(dt: Float) {
		updateSelectedFiles();

		if (needRefresh) {
			refreshInternal();
		}

		if (delayRename != null) {
			var file = fileManager.getFileEntry(delayRename.path);
			if (file != null) {
				if (delayRename.isTree) {
					tree.setSelection([file]);
					updateSelectedFiles();

					promptRenameFile(file, true);
				} else {
					gallerySelection.clear();
					gallerySelection.set(file, true);
					updateSelectedFiles();

					promptRenameFile(file, false);
				}

				delayRename = null;
			}
		}

		if (delaySelect != null) {
			var files = [for (file in delaySelect.paths) fileManager.getFileEntry(file)];
			if (!files.contains(null)) {
				if (delaySelect.isTree) {
					tree.setSelection(files);
				} else {
					gallerySelection.clear();
					for (f in files) {
						gallerySelection.set(f, true);
					}
				}
				updateSelectedFiles();

				delaySelect = null;
			}
		}

		if (galleryDelayRename != null) {
			gallery.scrollTo(galleryDelayRename.file);
			refreshGalleryItems();
		}

		if (queueRefreshSlugs) {
			queueRefreshSlugs = false;

			mainToolbarWidget.slugs.removeChildElements();
			var path : Array<File> = [];
			var curr = currentDir();
			while(curr != null) {
				path.unshift(curr);
				curr = curr.parent;
			}

			for (i => part in path) {
				if (i > 0) {
					new HuiText("/", mainToolbarWidget.slugs);
				}

				var slugButton = new HuiFileBrowserSlug(part.name, mainToolbarWidget.slugs);
				slugButton.onClick = (e) -> {
					if (e.button == 0) {
						navigateTo(part, true);
					} else if (e.button == 1) {
						uiBase.contextMenu([
							{"label": "Copy Path", click: () -> {hide.Ide.inst.setClipboard(currentDir().getRelPath(), {});}},
							{"label": "Copy Absolute Path", click: () -> {hide.Ide.inst.setClipboard(currentDir().getPath(), {});}},
							{"label": "Paste Path", click: () -> {
								var path = hide.Ide.inst.getClipboardText();
								if (path == null || path == "")
									return;
								var file = FileManager.inst.getFileEntry(path);
								if (file == null)
									return;
								if (file.kind == File)
									file = file.parent;
								navigateTo(file, true);
							}},
						]);
					}
				}
			}
		}

		var s2d = this.getScene();
		if (hxd.Key.isDown(hxd.Key.ALT)) {
			if (fullThumbnailPopup == null) {
				fullThumbnailPopup = new HuiPopup(true);
			}
			if (currentHover != null) {
				if (fullThumbnailItem == null) {
					fullThumbnailItem = new HuiFileBrowserGalleryItem(currentHover, null, fullThumbnailPopup);
				}

				fullThumbnailItem.file = currentHover;
				fullThumbnailItem.refresh();

				uiBase.addTooltip(fullThumbnailPopup, {object: Point(s2d.mouseX + 8, s2d.mouseY + 8), directionX: StartOutside, directionY: StartOutside});
			} else {
				fullThumbnailPopup.remove();
			}
		} else {
			fullThumbnailPopup.remove();
		}

		super.update(dt);
	}


	public function refreshInternal() {
		rootFile = fileManager.fileRoot;
		if (navigationHistory.length == 0) {
			tree.toggleItemOpen(rootFile, true);
			navigateTo(rootFile, true);
		}

		mainToolbarWidget.prevBtn.enable = navigationHistoryPos > 0;
		mainToolbarWidget.forwardBtn.enable = navigationHistoryPos < navigationHistory.length - 1;
		mainToolbarWidget.parentBtn.enable = currentDir() != rootFile;

		if (mode == FileTree) {
			tree.customSearch = secondToolbarWidget.searchBar.text?.length > 0 ? secondToolbarWidget.searchBar.text : null;
		} else {
			tree.customSearch = null;
		}

		tree.rebuild();

		refreshGallery();

		needRefresh = false;
	}

	/**
		Current selected dir in the navigation history
	**/
	function currentDir() {
		return navigationHistory[navigationHistoryPos] ?? rootFile;
	}

	function navigateTo(folder: File, updateFileTree: Bool) {
		if (folder == null)
			return;
		if (folder.kind == File)
			folder = folder.parent;

		navigationHistoryPos++;
		navigationHistory.resize(navigationHistoryPos);
		navigationHistory.push(folder);

		if (updateFileTree) {
			tree.setSelection([folder]);
		}

		gallerySelection = [];
		galleryList = null;
		markRefresh();
	}

	function navigateBack() {
		navigationHistoryPos --;
		if (navigationHistoryPos < 0)
			navigationHistoryPos = 0;

		tree.setSelection([currentDir()]);
		galleryList = null;
		markRefresh();
	}

	function navigateForward() {
		navigationHistoryPos ++;
		if (navigationHistoryPos >= navigationHistory.length)
			navigationHistoryPos = navigationHistory.length - 1;

		tree.setSelection([currentDir()]);
		galleryList = null;
		markRefresh();
	}

	var queueRefreshSlugs = false;

	function refreshGallery() {
		if (galleryList == null) {
			var galleryFolder = currentDir();

			queueRefreshSlugs = true;

			if (secondToolbarWidget.searchBar.text?.length > 0) {
				gallerySearchRanges = [];
				galleryList = galleryFolder.searchAll(secondToolbarWidget.searchBar.text, gallerySearchRanges);
				trace(gallerySearchRanges);
			} else {
				gallerySearchRanges = null;
				galleryList = galleryFolder.children ?? [];
			}
			galleryList = galleryList.filter((f) -> !f.ignored);
			gallery.setItems(galleryList);
			galleryWidget.dom.toggleClass("no-results", galleryList.length == 0);
			galleryWidget.dom.toggleClass("no-results-search", secondToolbarWidget.searchBar.text?.length > 0);
		}
	}

	/**
		Force an instant update of the filebrowser, use this only
		if you need instant access to the new tree, for example to select a
		new element or rename it right after you created it
	**/
	function refreshSync() {
		refreshInternal();
		@:privateAccess tree.refreshSync();
	}

	function deletePathInternal(absPath: String) : Void {
		hrt.tools.FileManager.deleteFilePath(absPath);
		markRefresh();
	}

	function getItemChild(child: File) : Array<File> {
		var path : String = "";

		if (child == null) {
			return [rootFile];
		}

		if (child.kind != Dir)
			return null;

		var children = child?.children.filter((f) -> !f.ignored && (mode == FileTree || f.kind == Dir) );
		if (children?.length == 0)
			return null;
		return children;
	}

	public dynamic function onOpen(file: File) {

	}

	function getItemName(res: File) : String {
		return res.name;
	}

	static function getItemIcon(res: File) : hxd.res.Image {
		return switch(res.kind) {
			case Dir: HuiRes.ui.icons.folder_filled;
			case File: {
				var ext = res.name.split(".").pop();
				switch (ext) {
					default:
						HuiRes.ui.icons.file.unknown;
					case "shgraph":
						HuiRes.ui.icons.file.shader_graph;
					case "prefab":
						HuiRes.ui.icons.file.prefab;
					case "json", "props":
						HuiRes.ui.icons.file.props;
					case "txt":
						HuiRes.ui.icons.file.text;
					case "fbx":
						HuiRes.ui.icons.file.mesh;
					case "dds", "jpg", "jpeg", "png", "hdr":
						HuiRes.ui.icons.prefab.bitmap;
				}
			}
		}
	}
}

@:allow(hrt.ui.HuiFileBrowser)
@:access(hrt.ui.HuiFileBrowser)
class HuiFileBrowserGalleryItem extends HuiElement {
	var file: File;
	var fileBrowser: HuiFileBrowser;

	static var SRC = <hui-file-browser-gallery-item>
		<hui-element id="border">
			<hui-element id="icon" public/>
			<hui-element id="name-container">
				<hui-text id="name-text" public/>
				<hui-input-box id="title-edit" public/>
			</hui-element>
		</hui-element>
	</hui-file-browser-gallery-item>

	public function new(file: File, fileBrowser: HuiFileBrowser, ?parent) {
		super(parent);
		initComponent();

		this.file = file;
		this.fileBrowser = fileBrowser;
		if (fileBrowser != null)
			this.tip = file.name;
		refresh();

		// filebrowser == null means we want to display a big thumbnail in a popup
		if (fileBrowser != null) {
			onPush = (e) -> {
				if (e.button == hxd.Key.MOUSE_LEFT || e.button == hxd.Key.MOUSE_RIGHT) {
					if (!hxd.Key.isDown(hxd.Key.CTRL)) {
						fileBrowser.gallerySelection.clear();
					}

					if (!hxd.Key.isDown(hxd.Key.SHIFT) || fileBrowser.galleryLastClick == null) {
						fileBrowser.gallerySelection.set(file, true);
					} else {
						var start = fileBrowser.galleryList.indexOf(file);
						var end = fileBrowser.galleryList.indexOf(fileBrowser.galleryLastClick);
						if (end == -1 || start == -1) {
							fileBrowser.gallerySelection.set(file, true);
						} else {
							if (end < start) {
								var swap = end;
								end = start;
								start = swap;
							}

							for (i in start...end+1) {
								fileBrowser.gallerySelection.set(fileBrowser.galleryList[i], true);
							}
						}
					}

					fileBrowser.galleryLastClick = file;

					fileBrowser.updateSelectedFiles();
					fileBrowser.refreshGalleryItems();


					if (e.button == hxd.Key.MOUSE_RIGHT) {
						fileBrowser.itemContextMenu(file);
					}
				}
			}

			onDoubleClick = (e) -> {
				if (file.kind == Dir) {
					fileBrowser.navigateTo(file, true);
				} else {
					fileBrowser.onOpen(file);
				}
			}

			onOver = (e) -> {
				fileBrowser.currentHover = file;
			}

			onOut = (e) -> {
				fileBrowser.currentHover = null;
			}

			onDragStart = () -> {
				fileBrowser.itemStartDrag();
			}

			onDragOver = (op) -> {
				fileBrowser.fileOnDragOver(file, op);
				if (op.acceptDrop) {
					if (file.kind == Dir) {
						dom.addClass("can-drop-file");
					} else {
						fileBrowser.gallery.dom.addClass("can-drop-file");
					}
				}
			}

			onDragMove = (op) -> {
				fileBrowser.fileOnDragOver(file, op);
			}

			onDragOut = (op) -> {
				if (file.kind == Dir) {
					dom.removeClass("can-drop-file");
				} else {
					fileBrowser.gallery.dom.removeClass("can-drop-file");
				}
			}

			onDrop = (op) -> {
				fileBrowser.fileOnDrop(file, op, false);
			}
		}

	}

	public function refresh() {
		if (fileBrowser?.gallerySearchRanges == null) {
			nameText.text = file.name;
		} else {
			var index = fileBrowser.galleryList.indexOf(file);
			var range = fileBrowser.gallerySearchRanges[index];
			nameText.text = hide.Search.splitSearchRanges(file.name, range, "<h>", "</h>");
		}

		var zoomPx = fileBrowser != null ? HuiFileBrowser.zoomLevels[fileBrowser.zoom] : 512;
		icon.setWidth(zoomPx);
		icon.setHeight(zoomPx);

		icon.backgroundType = "hui";

		icon.huiBg.setTexture(HuiFileBrowser.getItemIcon(file).toTexture());
		icon.huiBg.imageMode = Fit;
		icon.huiBg.imageIsSdf = true;

		if (fileBrowser != null) {
			dom.toggleClass("selected", fileBrowser.gallerySelection.get(file) != null);
		} else {
			dom.removeClass("selected");
		}

		if (file.kind != Dir) {
			var retries = 0;
			function cb(miniaturePath) {
				if (miniaturePath == null)
					return;
				miniaturePath = StringTools.replace(miniaturePath, hide.Ide.inst.projectDir + "/res/", "");
				var res = try hxd.res.Loader.currentInstance.load(miniaturePath) catch(e) null;
				if (res == null) {
					if (retries < 3) {
						retries++;
						hide.App.defer(cb.bind(miniaturePath));
					}
					return;
				}

				var tex = res?.toTexture() ?? h3d.mat.Texture.fromColor(0xFF00FF);
				icon.huiBg.setTexture(tex);
				icon.huiBg.imageMode = Fit;
				icon.huiBg.imageIsSdf = false;
			};
			file.getIcon(cb);
		}

		if (fileBrowser?.galleryDelayRename?.file == file && allocated) {
			var renameStruct = fileBrowser.galleryDelayRename;
			rename(renameStruct.callback, renameStruct.range);
			fileBrowser.galleryDelayRename = null;
		}
	}

	public function rename(callback: String -> Void, ?selectionRange: HuiTree.SelectionRange) {
		dom.addClass("edit");
		titleEdit.text = file.name;
		titleEdit.focus(false);

		if (selectionRange != null) {
			titleEdit.textInput.setSelectionRange(selectionRange);
		}


		titleEdit.onInputFocusLost = (e) -> {
			dom.removeClass("edit");
		}

		titleEdit.onChange = (temp) -> {
			if (!temp) {
				callback(titleEdit.text);
			}
		}
	}
}

class HuiFileBrowserMainToolbarWidget extends HuiElement {
	static var SRC =
		<hui-file-browser-main-toolbar-widget>
			<hui-button  class="group-start" id="prev-btn" tip={"Go back to previous folder"} public>
				<hui-icon("back")/>
			</hui-button>
			<hui-button  class="group-end" id="forward-btn" tip={"Go forwards to folder"} public>
				<hui-icon("forward")/>
			</hui-button>
			<hui-button  id="parent-btn" tip={"Go to parent folder"} public>
				<hui-icon("back_one_level")/>
			</hui-button>
			<hui-element id="slugs" public/>
			<hui-button id="split-button" public>
				<hui-icon("split-tree") id="split-button-icon" public/>
			</hui-button>
		</hui-file-browser-main-toolbar-widget>
}

class HuiFileBrowserSecondToolbarWidget extends HuiElement {
	static var SRC =
		<hui-file-browser-second-toolbar-widget>
			<hui-input-box class="search" id="search-bar" public/>
		</hui-file-browser-second-toolbar-widget>
}

class HuiFileBrowserNoResultWidget extends HuiElement {
	static var SRC =
		<hui-file-browser-no-result-widget>
			<hui-element id="for-search">
				<hui-text("No results founds for this folder") id="no-results-text"/>
				<hui-element id="buttons">
					<hui-button public id="search-all-btn"><hui-text("Search All")/></hui-button>
					<hui-button public id="clear-search-btn"><hui-text("Clear search")/></hui-button>
				</hui-element>
			</hui-element>
			<hui-element id="for-empty">
				<hui-text("Empty Folder")/>
			</hui-element>

		</hui-file-browser-no-result-widget>
}

class HuiFileBrowserGalleryWidget extends HuiElement {
	static var SRC =
		<hui-file-browser-gallery-widget>
			<hui-virtual-grid id="gallery" public/>
			<hui-file-browser-no-result-widget id="no-results" public/>
		</hui-file-browser-gallery-widget>
}

class HuiFileBrowserSlug extends HuiElement {
	static var SRC =
		<hui-file-browser-slug>
			<hui-text() id="text"/>
		</hui-file-browser-slug>

	public function new(text: String, ?parent) {
		super(parent);
		initComponent();

		this.text.text = text;
	}
}

#end
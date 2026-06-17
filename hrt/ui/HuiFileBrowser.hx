package hrt.ui;

#if hui

import hrt.tools.FileManager;

typedef File = FileEntry;

class HuiFileBrowser extends HuiElement {
	var rootFile: File;

	var tree: HuiTree<File>;
	var rootPath: String;
	var needRefresh: Bool = false;

	var fileManager = FileManager.inst;

	/**
		Wait for this path to become available in the FileManager, and then
		do a rename action in the filebrowser. This is needed because we rely on
		the filemanager filewatch to refresh the browser (in order to not have to manually
		update the Filemanager internal filesystem manually when we add files).
	**/
	var delayRename: String = null;
	var delaySelect: Array<String> = null;

	static public final fileDragOp = "fileDrag";

	public function new(rootPath: String, ?parent) {
		super(parent);
		initComponent();

		this.rootPath = rootPath;

		registerCommand(HuiCommands.delete, View, deleteSelection);
		registerCommand(HuiCommands.rename, View, renameSelection);
		registerCommand(HuiCommands.duplicate, View, duplicateSelection);
		registerCommand(HuiCommands.copy, View, copySelection);
		registerCommand(HuiCommands.paste, View, pasteSelection);

		tree = new HuiTree<File>(this);
		tree.getItemChildren = getItemChild;
		tree.getItemName = getItemName;
		tree.getItemIcon = getItemIcon;
		tree.onItemDoubleClick = (e, file) -> onOpen(file);

		tree.dragAndDropInterface = {
			onDragStart: (item) -> {
				var filePaths = [for (file in tree.getSelectedItems()) file.path];
				var op = tree.startDrag(fileDragOp, filePaths);
				op.setPreviewText(filePaths.join("<br/>"));
			},
			getItemDropFlags: function(item, op) : hrt.ui.HuiTree.DropFlags {
				if (op.type == fileDragOp) {
					if (item.kind == Dir) {
						return hrt.ui.HuiTree.DropFlag.Reorder | hrt.ui.HuiTree.DropFlag.Reparent;
					}
					return hrt.ui.HuiTree.DropFlag.Reorder;
				}
				return hrt.ui.HuiTree.DropFlags.ofInt(0);
			},
			onDrop: (target: hrt.tools.FileManager.FileEntry, where, op:HuiDragOp) -> {
				if (op.type == fileDragOp) {
					var folder = target.kind == Dir ? target : target.parent;

					var paths: Array<String> = cast op.data;
					var files = [for (path in paths) hrt.tools.FileManager.inst.getFileEntry(path)];
					files = files.filter((f) -> f != null);
					var roots = hrt.tools.FileManager.inst.getRoots(files);

					var operations = [];
					var operationsRev = [];
					for (root in roots) {
						operations.push({from: root.getPath(), to: folder.getPath() + "/" + root.name});
					}

					getView().undo.run(actionMoveFilesAbs(operations), false);
				}
			}
		};


		tree.onItemContextMenu = itemContextMenu;

		markRefresh();

		fileManager.watchFileChange(onFileChange);
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
	}

	public function markRefresh() {
		needRefresh = true;
	}

	function itemContextMenu(file: File) {
		if (file == null)
			file = rootFile;

		var allExts = @:privateAccess Lambda.filter(hrt.prefab.Prefab.registry, (inf) -> inf.extension != null);

		var createMenu : Array<hrt.ui.HuiMenu.MenuItem> = [{
			label: "Directory",
			click: () -> createNewDirectory(file),
		},{
			label: "Prefab",
			click: () -> createNewFile(file, "New Prefab", "prefab", hide.Ide.inst.toJSON(@:privateAccess new hrt.prefab.Prefab(null, null).serialize()))
		}];

		var items : Array<hrt.ui.HuiMenu.MenuItem> = [{label: "New ...", menu: createMenu}];

		items.push({isSeparator: true});

		items.push({label: "Copy Path", click: () -> hide.Ide.inst.setClipboard(file.getRelPath(), null)});
		items.push({label: "Copy Absolute Path", click: () -> hide.Ide.inst.setClipboard(file.getPath(), null)});
		items.push({label: "Open In Explorer", click: () -> hide.tools.IdeData.showFileInExplorer(file.getPath())});

		items.push({isSeparator: true});

		var duplicate = HuiMenu.itemFromCommand(HuiCommands.duplicate, this);
		duplicate.enabled = tree.getSelectedItems().length > 0;
		items.push(duplicate);

		var copy = HuiMenu.itemFromCommand(HuiCommands.copy, this);
		copy.enabled = tree.getSelectedItems().length > 0;
		items.push(copy);

		var paste = HuiMenu.itemFromCommand(HuiCommands.paste, this);
		paste.enabled = hide.Ide.inst.getClipboardData()?.type == "file";
		items.push(paste);

		var rename = HuiMenu.itemFromCommand(HuiCommands.rename, this);
		rename.enabled = file != rootFile;
		items.push(rename);

		var delete = HuiMenu.itemFromCommand(HuiCommands.delete, this);
		delete.enabled = file != rootFile;
		items.push(delete);

		uiBase.contextMenu(items);
	}

	function copySelection() {
		hide.Ide.inst.setClipboard(null, {
			type: "file",
			files: [for (file in tree.getSelectedItems()) file.getPath()],
		});
	}

	function pasteSelection() {
		var data = hide.Ide.inst.getClipboardData();
		if (data == null || data.type != "file")
			return;

		var target = tree.getSelectedItems()[0] ?? rootFile;
		if (target.kind != Dir || !tree.isItemOpen(target)) {
			target = target.parent;
		}

		copyFilesToFolder(cast data.files, target.getPath());
	}

	function duplicateSelection() {
		var sources = [for (file in tree.getSelectedItems()) file.getPath()];
		var destinations = ensureUniquePaths(sources);

		var operations = [for (i in 0...sources.length) {source: sources[i], destination: destinations[i]}];

		getView().undo.run(actionCopyFiles(operations), false);
	}

	function createNewDirectory(parent: File) {
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

		delayRename = pathToCreate;
	}

	public function createNewFile(parent: File, baseName: String, extension: String, baseContent: String) {
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

		delayRename = pathToCreate;
	}


	function deleteSelection() {
		var selectedFiles = tree.getSelectedItems();

		var message = if (selectedFiles.length == 1) selectedFiles[0].name else '${selectedFiles.length} files';
		uiBase.confirm('Really delete $message ? (Cannot be undone)', Cancel | Ok, (button) -> {
			if (button == Ok) {
				try {
					hrt.tools.FileManager.deleteFilesPaths([for(file in selectedFiles) file.getPath()]);
				} catch (e) {
					hide.Ide.showError("" + e);
				}
				markRefresh();
			}
		});
	}

	function renameSelection() {
		var selectedFiles = tree.getSelectedItems();

		if (selectedFiles.length > 0) {
			promptRenameFile(selectedFiles[0]);
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
	function actionRenameFile(oldPath: String, newPath: String) : hrt.tools.Undo.Action {
		return (isUndo) -> {
			var from = isUndo ? newPath : oldPath;
			var to = isUndo ? oldPath : newPath;
			var entry = fileManager.getFileEntry(from);
			var wasSelected = false;
			if (entry != null) {
				wasSelected = tree.isItemSelected(entry);
			} else {
				wasSelected = delaySelect?.contains(from);
			}

			try {
				FileManager.doRenameAbs([{from: from, to: to}]);
			} catch(e) {
				hide.Ide.showError('Couldn\'t rename $from -> $to : $e');
				return;
			}

			if (wasSelected) {
				delaySelect ??= [];
				delaySelect.push(to);
			}
		}
	}

	static var simpleFilenameRegex = ~/(.*) \(\d+\)/;

	function copyFilesToFolder(filePaths: Array<String>, folderPath: String) {

		var destinations = [];
		for (path in filePaths) {
			var dest = new haxe.io.Path(path);
			dest.dir = folderPath;
			destinations.push(dest.toString());
		}

		destinations = ensureUniquePaths(destinations);

		var operations = [for (i in 0...filePaths.length) {source: filePaths[i], destination: destinations[i]}];

		getView().undo.run(actionCopyFiles(operations), false);
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

	function actionCopyFiles(operations: Array<{source: String, destination: String}>) {
		var operations = operations.copy();
		var selection = [for (file in tree.getSelectedItems()) file.getPath()];

		if (operations.length == 1)
			delayRename = operations[0].destination;

		return (isUndo) -> {
			if (isUndo) {
				hrt.tools.FileManager.deleteFilesPaths([for (op in operations) op.destination]);
				delaySelect = selection;
			} else {
				hrt.tools.FileManager.copyFilesPaths(operations);
				delaySelect = [for (op in operations) op.destination];
			}
			markRefresh();
		}
	}

	function promptRenameFile(file: File) {
		var path = new haxe.io.Path(file.path);
		tree.rename(file, (newName) -> {
			if (path.file + "." + path.ext != newName) {
				var newPath = haxe.io.Path.join([path.dir, newName]);
				getView().undo.run(actionRenameFile(file.path, newPath), false);
			}
		}, {start: 0, length: path.file.length} /* Select before the . of the file*/);
	}

	override function sync(ctx: h2d.RenderContext) {
		if (needRefresh) {
			refreshInternal();
		}

		if (delayRename != null) {
			var file = fileManager.getFileEntry(delayRename);
			if (file != null) {
				tree.setSelection([file]);
				promptRenameFile(file);
				delayRename = null;
			}
		}

		if (delaySelect != null) {
			var files = [for (file in delaySelect) fileManager.getFileEntry(file)];
			if (!files.contains(null)) {
				tree.setSelection(files);
				delaySelect = null;
			}
		}

		super.sync(ctx);
	}

	function refreshInternal() {
		rootFile = fileManager.fileRoot;

		tree.rebuild();
		needRefresh = false;
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
			child = rootFile;
		}

		if (child.kind != Dir)
			return null;

		return child.children.filter((f) -> !f.ignored);
	}

	public dynamic function onOpen(file: File) {

	}

	function getItemName(res: File) : String {
		return res.name;
	}

	function getItemIcon(res: File) : hxd.res.Image {
		return switch(res.kind) {
			case Dir: HuiRes.ui.icons.folder_filled;
			case File: HuiRes.ui.icons.file_blank_filled;
		}
	}
}

#end
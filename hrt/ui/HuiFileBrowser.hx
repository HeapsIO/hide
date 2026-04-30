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
			onDrop: (item, where, op) -> {
				if (op.type == fileDragOp) {
					trace("drop");
				}
			}
		};


		tree.onItemContextMenu = itemContextMenu;

		markRefresh();

		fileManager.watchFileChange(onFileChange);
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

		var rename = HuiMenu.itemFromCommand(HuiCommands.rename, this);
		rename.enabled = file != rootFile;
		items.push(rename);

		var delete = HuiMenu.itemFromCommand(HuiCommands.delete, this);
		delete.enabled = file != rootFile;
		items.push(delete);

		uiBase.contextMenu(items);
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
					sys.FileSystem.deleteDirectory(pathToCreate);
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
					sys.FileSystem.deleteFile(pathToCreate);
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
				for (file in selectedFiles) {
					if (sys.FileSystem.exists(file.path)) {
						try {
							if (file.kind == Dir) {
								deleteDir(file.path);
							} else {
								sys.FileSystem.deleteFile(file.path);
							}
						} catch(e) {
							hide.Ide.showError('Error while removing ${file.name} : $e');
						}
					}
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

	/**
		Delete a directory and its content
		Expect an absolute path
	**/
	function deleteDir(dirPath: String) : Void {
		var files = sys.FileSystem.readDirectory(dirPath);
		for (file in files) {
			var filePath = haxe.io.Path.join([dirPath, file]);
			if (sys.FileSystem.isDirectory(filePath)) {
				deleteDir(filePath);
			} else {
				deleteFile(filePath);
			}
		}
		sys.FileSystem.deleteDirectory(dirPath);
		markRefresh();
	}

	function deleteFile(absPath: String) : Void {
		sys.FileSystem.deleteFile(absPath);
		markRefresh();
	}

	function actionMoveFiles(targetPath: String, paths: Array<String>) {
		for (path in paths) {
			if (StringTools.startsWith(targetPath, path)) {
				hide.Ide.showError('Cannot move $path as it contains destination folder ($targetPath)');
				return;
			}
		}
	}


	function actionRenameFile(oldPath: String, newPath: String) : hrt.tools.Undo.Action {
		return (isUndo) -> {
			var from = isUndo ? newPath : oldPath;
			var to = isUndo ? oldPath : newPath;
			var wasSelected = tree.isItemSelected(fileManager.getFileAbs(from));

			try {
				sys.FileSystem.rename(from, to);
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

	function promptRenameFile(file: File) {
		var path = new haxe.io.Path(file.path);
		tree.rename(file, (newName) -> {
			if (path.file != newName) {
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
			var file = fileManager.getFileAbs(delayRename);
			if (file != null) {
				tree.setSelection([file]);
				promptRenameFile(file);
				delayRename = null;
			}
		}

		if (delaySelect != null) {
			var files = [for (file in delaySelect) fileManager.getFileAbs(file)];
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



	function getItemChild(child: File) : Array<File> {
		var path : String = "";

		if (child == null) {
			child = rootFile;
		}

		if (child.kind != Dir)
			return null;

		return child.children;
	}

	public dynamic function onOpen(file: File) {

	}

	function getItemName(res: File) : String {
		return res.name;
	}

	function getItemIcon(res: File) : String {
		return switch(res.kind) {
			case Dir: HuiRes.icons.folder_filled;
			case File: HuiRes.icons.file_blank_filled;
		}
	}
}

#end
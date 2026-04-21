package hrt.ui;

#if hui

typedef File = {
	var name: String;
	var nameSort: String;
	var fullPath: String;
	var parent: File;
	var children: Array<File>;
	var isDirectory: Bool;
}

class HuiFileBrowser extends HuiElement {
	var rootFile: File;

	var tree: HuiTree<File>;
	var rootPath: String;
	var needRefresh: Bool = false;

	public function new(rootPath: String, ?parent) {
		super(parent);
		initComponent();

		this.rootPath = rootPath;

		registerCommand(HuiCommands.delete, View, deleteSelection);

		tree = new HuiTree<File>(this);
		tree.getItemChildren = getItemChild;
		tree.getItemName = getItemName;
		tree.getItemIcon = getItemIcon;
		tree.onItemDoubleClick = (e, file) -> onOpen(file);

		tree.onItemContextMenu = itemContextMenu;

		markRefresh();
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
			click: () -> {
				var dir = file;
				if (!dir.isDirectory) {
					dir = file.parent;
				}
				var basePath = dir.fullPath + '/' + "New directory";
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

				refreshSync();

				var newFile = getItemByPath(pathToCreate);
				tree.setSelection([newFile]);
				tree.rename(newFile, (newName) -> {
					var oldPath = newFile.fullPath;
					var path = new haxe.io.Path(newFile.fullPath);
					var newPath = path.dir + "/" + newName;

					if (oldPath != newPath) {
						getView().undo.run(actionRenameFile(oldPath, newPath), false);
					}
				});
			}
		}];

		var items : Array<hrt.ui.HuiMenu.MenuItem> = [{label: "New ...", menu: createMenu}];
		items.push({label: "Delete",
				click: deleteSelection,
			enabled: file != rootFile,
		});

		uiBase.contextMenu(items);
	}

	function deleteSelection() {
		var selectedFiles = tree.getSelectedItems();

		var message = if (selectedFiles.length == 1) selectedFiles[0].name else '${selectedFiles.length} files';
		uiBase.confirm('Really delete $message ? (Cannot be undone)', Cancel | Ok, (button) -> {
			if (button == Ok) {
				for (file in selectedFiles) {
					if (sys.FileSystem.exists(file.fullPath)) {
						try {
							if (file.isDirectory) {
								deleteDir(file.fullPath);
							} else {
								sys.FileSystem.deleteFile(file.fullPath);
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

	function actionRenameFile(oldPath: String, newPath: String) : hrt.tools.Undo.Action {
		return (isUndo) -> {
			var from = isUndo ? newPath : oldPath;
			var to = isUndo ? oldPath : newPath;

			try {
				sys.FileSystem.rename(from, to);
			} catch(e) {
				hide.Ide.showError('Couldn\'t rename $from -> $to : $e');
				return;
			}

			markRefresh();
		}
	}

	override function sync(ctx: h2d.RenderContext) {
		if (needRefresh) {
			refreshInternal();
		}

		super.sync(ctx);
	}

	function refreshInternal() {
		rootFile = {
			name: new haxe.io.Path(rootPath).file,
			nameSort: new haxe.io.Path(rootPath).file,
			fullPath: rootPath,
			parent: null,
			children: null,
			isDirectory: true,
		};

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

		if (!child.isDirectory)
			return null;

		if (child.children == null) {
			var files = sys.FileSystem.readDirectory(child.fullPath);
			child.children = [];
			for (file in files) {
				if (file == ".tmp") continue;
				var fullPath = child.fullPath + "/" + file;
				child.children.push({
					name: file,
					nameSort: file.toLowerCase(),
					fullPath: fullPath,
					parent: child,
					children: null,
					isDirectory: sys.FileSystem.isDirectory(fullPath),
				});
			}

			child.children.sort(sortEntries);
		}

		return child.children;
	}

	function sortEntries(a: File, b: File) {
		if (a.isDirectory && !b.isDirectory) {
			return -1;
		} else if (!a.isDirectory && b.isDirectory) {
			return 1;
		}
		return Reflect.compare(a.nameSort, b.nameSort);
	}

	public dynamic function onOpen(file: File) {

	}

	function getItemName(res: File) : String {
		return res.name;
	}

	function getItemIcon(res: File) : String {
		if (res.isDirectory)
			return HuiRes.icons.folder_filled;
		else
			return HuiRes.icons.file_blank_filled;
	}

	function getItemByPath(path: String) : File {
		var relPath = StringTools.replace(path, rootPath + "/", "");
		relPath = StringTools.replace(relPath, "\\", "");
		var parts = relPath.split("/");
		var paths = new haxe.io.Path(relPath);
		var curFile = rootFile;
		for (part in parts) {
			curFile = Lambda.find(curFile.children, (f) -> f.name == part);
			if (curFile == null)
				return null;
		}
		return curFile;
	}
}

#end
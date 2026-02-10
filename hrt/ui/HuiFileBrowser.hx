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

	public function new(rootPath: String, ?parent) {
		super(parent);
		initComponent();

		rootFile = {
			name: new haxe.io.Path(rootPath).file,
			nameSort: new haxe.io.Path(rootPath).file,
			fullPath: rootPath,
			parent: null,
			children: null,
			isDirectory: true,
		};

		var tree = new HuiTree<File>(this);
		tree.getItemChildren = getItemChild;
		tree.getItemName = getItemName;
		tree.onItemDoubleClick = (e, file) -> onOpen(file);
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
}

#end
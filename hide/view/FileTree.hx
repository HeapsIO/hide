package hide.view;

typedef ExtensionOptions = {
	?icon : String,
	?createNew : String,
};

typedef ExtensionDesc = {
	var component : String;
	var extensions : Array<String>;
	var options : ExtensionOptions;
}

class FileTree extends FileView {

	var tree : hide.comp.IconTree<String>;
	var ignorePatterns : Array<EReg> = [];

	public function new(state) {
		super(state);

		var exclPatterns : Array<String> = ide.currentConfig.get("filetree.excludes", []);
		for(pat in exclPatterns)
			ignorePatterns.push(new EReg(pat, "i"));

		if( state.path == null ) {
			ide.chooseDirectory(function(dir) {
				if( dir == null ) {
					close();
					return;
				}
				state.path = dir.split("\\").join("/")+"/";
				saveState();
				rebuild();
			},true);
		}

		keys.register("search", function() tree.openFilter());
	}

	override function canSave() {
		return false;
	}

	static function getExtension( file : String ) {
		var ext = new haxe.io.Path(file).ext;
		if( ext == null ) return null;
		ext = ext.toLowerCase();
		if( ext == "json" ) {
			try {
				var obj : Dynamic = haxe.Json.parse(sys.io.File.getContent(file));
				if( obj.type != null && Std.isOfType(obj.type, String) ) {
					var e = EXTENSIONS.get("json." + obj.type);
					if( e != null ) return e;
				}
			} catch( e : Dynamic ) {
			}
		}
		return EXTENSIONS.get(ext);
	}

	override function getTitle() {
		if( state.path == "" )
			return "Resources";
		if( state.path == null )
			return "";
		return super.getTitle();
	}

	override function onFileChanged(wasDeleted:Bool, rebuildView:Bool = true) {
	}

	override function onDisplay() {

		if( state.path == null ) return;

		var panel = new Element("<div class='hide-scroll'>").appendTo(element);
		tree = new hide.comp.IconTree(null,panel);
		tree.async = true;
		tree.allowRename = true;
		tree.saveDisplayKey = saveDisplayKey;
		tree.element.addClass("small");
		tree.get = function(path) {
			if( path == null ) path = "";
			var basePath = getFilePath(path);
			var content = new Array<hide.comp.IconTree.IconTreeItem<String>>();
			for( c in sys.FileSystem.readDirectory(basePath) ) {
				var fullPath = basePath + "/" + c;
				if( isIgnored(fullPath) ) continue;
				var isDir = sys.FileSystem.isDirectory(fullPath);
				var ext = getExtension(fullPath);
				var id = ( path == "" ? c : path+"/"+c );
				content.push({
					value : id,
					text : c,
					icon : "ico ico-" + (isDir ? "folder" : (ext != null && ext.options.icon != null ? ext.options.icon : "file-text")),
					children : isDir,
				});
			}
			watch(basePath, function() rebuild(),{checkDelete:true});
			content.sort(function(a,b) { if( a.children != b.children ) return a.children?-1:1; return Reflect.compare(a.text,b.text); });
			return content;
		};

		tree.onRename = doRename;

		element.contextmenu(function(e) {
			var over = tree.getCurrentOver();
			if( over != null && !tree.getSelection().contains(over))
				tree.setSelection([over]);
			var selection = tree.getSelection();
			e.preventDefault();
			var allowedNew : Array<String> = config.get("filetree.allowednew");
			function allowed( ext : String ) return allowedNew.indexOf(ext) >= 0 || allowedNew.indexOf("*") >= 0;
			var newMenu = [for( e in EXTENSIONS ) if( e.options.createNew != null && Lambda.exists(e.extensions, allowed) ) {
				label : e.options.createNew,
				click : createNew.bind(selection[0], e),
				icon : e.options.icon,
			}];
			if( allowed("dir") )
				newMenu.unshift({
					label : "Directory",
					click : createNew.bind(selection[0], { options : { createNew : "Directory" }, extensions : null, component : null }),
					icon : "folder",
				});
			new hide.comp.ContextMenu([
				{ label : "New...", menu:newMenu },
				{ label : "Collapse", click : tree.collapseAll },
				{ label : "", isSeparator: true },
				{ label : "Copy Path", enabled : selection.length == 1, click : function() { ide.setClipboard(selection[0]); } },
				{ label : "Copy Absolute Path", enabled : selection.length == 1, click : function() { ide.setClipboard(Ide.inst.getPath(selection[0])); } },
				{ label : "Open in Explorer", enabled : selection.length == 1, click : function() { onExploreFile(selection[0]); } },
				{ label : "Find References", enabled : selection.length == 1, click : onFindPathRef.bind(selection[0])},
				{ label : "", isSeparator: true },
				{ label : "Clone", enabled : selection.length == 1, click : function() {
						try {
							if (onCloneFile(selection[0])) {
								tree.refresh();
							}
						} catch (e : Dynamic) {
							js.Browser.window.alert(e);
						}
					} },
				{ label : "Rename", enabled : selection.length == 1, click : function() {
					try {
						onRenameFile(selection[0]);
					} catch (e : Dynamic) {
						js.Browser.window.alert(e);
					}
					} },
				{ label : "Move", enabled : selection.length > 0, click : function() {
					ide.chooseDirectory(function(dir) {
						for (current in selection) {
							doRename(current, "/"+dir+"/"+current.split("/").pop());
						}
					});
				}},
				{ label : "Delete", enabled : selection.length > 0, click : function() {
					if( js.Browser.window.confirm("Delete " + selection.join(", ") + "?") ) {
						for (current in selection) {
							onDeleteFile(current);
						}
						tree.refresh();
					}
				}},
			]);
		});
		tree.onDblClick = onOpenFile;
		tree.onAllowMove = onAllowMove;
		tree.onMove = doMove;
		tree.init();
	}

	function onRenameFile( path : String ) {
		var newFilename = ide.ask("New name:", path.substring( path.lastIndexOf("/") + 1 ));

		while ( newFilename != null && sys.FileSystem.exists(ide.getPath(newFilename))) {
			newFilename = ide.ask("This file already exists. Another new name:");
		}
		if (newFilename == null) {
			return false;
		}

		doRename(path, newFilename);
		return true;
	}

	function doRename(path:String, name:String) {
		var isDir = sys.FileSystem.isDirectory(ide.getPath(path));
		if( isDir ) ide.fileWatcher.pause();
		var ret = onRenameRec(path, name);
		if( isDir ) ide.fileWatcher.resume();
		return ret;
	}

	function onFindPathRef(path: String) {
		ide.findPathRefs(path);
	}

	function onRenameRec(path:String, name:String) {

		var parts = path.split("/");
		parts.pop();
		for( n in name.split("/") ) {
			if( n == ".." )
				parts.pop();
			else
				parts.push(n);
		}
		var newPath = name.charAt(0) == "/" ? name.substr(1) : parts.join("/");

		if( newPath == path )
			return false;

		if( sys.FileSystem.exists(ide.getPath(newPath)) ) {
			function addPath(path:String,rand:String) {
				var p = path.split(".");
				if( p.length > 1 )
					p[p.length-2] += rand;
				else
					p[p.length-1] += rand;
				return p.join(".");
			}
			if( path.toLowerCase() == newPath.toLowerCase() ) {
				// case change
				var rand = "__tmp"+Std.random(10000);
				onRenameRec(path, "/"+addPath(path,rand));
				onRenameRec(addPath(path,rand), name);
			} else {
				if( !ide.confirm(newPath+" already exists, invert files?") )
					return false;
				var rand = "__tmp"+Std.random(10000);
				onRenameRec(path, "/"+addPath(path,rand));
				onRenameRec(newPath, "/"+path);
				onRenameRec(addPath(path,rand), name);
			}
			return false;
		}

		var isDir = sys.FileSystem.isDirectory(ide.getPath(path));
		var wasRenamed = false;
		var isSVNRepo = sys.FileSystem.exists(ide.projectDir+"/.svn") || js.node.ChildProcess.spawnSync("svn",["info"], { cwd : ide.resourceDir }).status == 0; // handle not root dirs
		if( isSVNRepo ) {
			if( js.node.ChildProcess.spawnSync("svn",["--version"]).status != 0 ) {
				if( isDir && !ide.confirm("Renaming a SVN directory, but 'svn' system command was not found. Continue ?") )
					return false;
			} else {
				// Check if file is versioned before using svn rename
				if (js.node.ChildProcess.spawnSync("svn",["info", ide.getPath(path)]).status == 0) {
					var cwd = Sys.getCwd();
					Sys.setCwd(ide.resourceDir);
					var code = Sys.command("svn",["rename",path,newPath]);
					Sys.setCwd(cwd);
					if( code == 0 )
						wasRenamed = true;
					else {
						if( !ide.confirm("SVN rename failure, perform file rename ?") )
							return false;
					}
				}
			}
		}

		if( !wasRenamed )
			sys.FileSystem.rename(ide.getPath(path), ide.getPath(newPath));

		var changed = false;
		function filter(ctx: hide.Ide.FilterPathContext) {
			var p = ctx.valueCurrent;
			if( p == null )
				return;
			if( p == path ) {
				ctx.change(newPath);
				return;
			}
			if( p == "/"+path ) {
				ctx.change(newPath);
				return;
			}
			if( isDir ) {
				if( StringTools.startsWith(p,path+"/") ) {
					ctx.change(newPath + p.substr(path.length));
					return;
				}
				if( StringTools.startsWith(p,"/"+path+"/") ) {
					ctx.change("/"+newPath + p.substr(path.length+1));
					return;
				}
			}
		}

		ide.filterPaths(filter);

		var dataDir = new haxe.io.Path(path);
		if( dataDir.ext != "dat" ) {
			dataDir.ext = "dat";
			var dataPath = dataDir.toString();
			if( sys.FileSystem.isDirectory(ide.getPath(dataPath)) ) {
				var destPath = new haxe.io.Path(name);
				destPath.ext = "dat";
				onRenameRec(dataPath, destPath.toString());
			}
		}

		// update Materials.props if an FBX is moved/renamed
		var newSysPath = new haxe.io.Path(name);
		var oldSysPath = new haxe.io.Path(path);
		if (newSysPath.dir == null) {
			newSysPath.dir = oldSysPath.dir;
		}
		if (newSysPath.ext.toLowerCase() == "fbx" && oldSysPath.ext.toLowerCase() == "fbx") {
			function remLeadingSlash(s:String) {
				if(StringTools.startsWith(s,"/")) {
					return s.length > 1 ? s.substr(1) : "";
				}
				return s;
			}

			var oldMatPropsPath = ide.getPath(remLeadingSlash((oldSysPath.dir ?? "") + "/materials.props"));

			if (sys.FileSystem.exists(oldMatPropsPath)) {
				var newMatPropsPath = ide.getPath(remLeadingSlash((newSysPath.dir ?? "") + "/materials.props"));

				var oldMatProps = haxe.Json.parse(sys.io.File.getContent(oldMatPropsPath));

				var newMatProps : Dynamic =
					if (sys.FileSystem.exists(newMatPropsPath))
						haxe.Json.parse(sys.io.File.getContent(newMatPropsPath))
					else {};

				var oldNameExt = oldSysPath.file + "." + oldSysPath.ext;
				var newNameExt = newSysPath.file + "." + newSysPath.ext;
				function moveRec(originalData: Dynamic, oldData:Dynamic, newData: Dynamic) {

					for (field in Reflect.fields(originalData)) {
						if (StringTools.endsWith(field, oldNameExt)) {
							var innerData = Reflect.getProperty(originalData, field);
							var newField = StringTools.replace(field, oldNameExt, newNameExt);
							Reflect.setProperty(newData, newField, innerData);
							Reflect.deleteField(oldData, field);
						}
						else {
							var originalInner = Reflect.getProperty(originalData, field);
							if (Type.typeof(originalInner) != TObject)
								continue;

							var oldInner = Reflect.getProperty(oldData, field);
							var newInner = Reflect.getProperty(newData, field) ?? {};
							moveRec(originalInner, oldInner, newInner);

							// Avoid creating empty fields
							if (Reflect.fields(newInner).length > 0) {
								Reflect.setProperty(newData, field, newInner);
							}

							// Cleanup removed fields in old props
							if (Reflect.fields(oldInner).length == 0) {
								Reflect.deleteField(oldData, field);
							}
						}
					}
				}

				var sourceData = oldMatProps;
				var oldDataToSave = oldMatPropsPath == newMatPropsPath ? newMatProps : haxe.Json.parse(haxe.Json.stringify(oldMatProps));

				moveRec(oldMatProps, oldDataToSave, newMatProps);
				sys.io.File.saveContent(newMatPropsPath, haxe.Json.stringify(newMatProps, null, "\t"));

				if (oldMatPropsPath != newMatPropsPath) {
					if (Reflect.fields(oldMatProps).length > 0) {
						sys.io.File.saveContent(oldMatPropsPath, haxe.Json.stringify(oldDataToSave, null, "\t"));
					} else {
						sys.FileSystem.deleteFile(oldMatPropsPath);
					}
				}

				// Clear caches
				@:privateAccess
				{
					if (h3d.mat.MaterialSetup.current != null) {
						h3d.mat.MaterialSetup.current.database.db.remove(ide.makeRelative(oldMatPropsPath));
						h3d.mat.MaterialSetup.current.database.db.remove(ide.makeRelative(newMatPropsPath));
					}
					hxd.res.Loader.currentInstance.cache.remove(ide.makeRelative(oldMatPropsPath));
					hxd.res.Loader.currentInstance.cache.remove(ide.makeRelative(newMatPropsPath));
				}
			}

		}

		return true;
	}

	function onAllowMove(e: String, to : String) {
		var destAbsPath = Ide.inst.getPath(to);
		return sys.FileSystem.isDirectory(destAbsPath);
	}

	function doMove(e : String, to : String, index : Int) {
		var dest = "/" + to + "/" + e.split("/").pop();
		doRename(e, dest);
	}

	function onExploreFile( path : String ) {
		Ide.showFileInExplorer(path);
	}

	function onCloneFile( path : String ) {
		var sourcePath = getFilePath(path);
		var nameNewFile = ide.ask("New filename:", new haxe.io.Path(sourcePath).file);
		if (nameNewFile == null || nameNewFile.length == 0) {
			return false;
		}

		var targetPath = new haxe.io.Path(sourcePath).dir + "/" + nameNewFile;
		if ( sys.FileSystem.exists(targetPath) ) {
			throw "File already exists";
		}

		if( sys.FileSystem.isDirectory(sourcePath) ) {
			sys.FileSystem.createDirectory(targetPath + "/");
			for( f in sys.FileSystem.readDirectory(sourcePath) ) {
				sys.io.File.saveBytes(targetPath + "/" + f, sys.io.File.getBytes(sourcePath + "/" + f));
			}
		} else {
			var extensionNewFile = getExtension(targetPath);

			if (extensionNewFile == null) {
				var extensionSourceFile = getExtension(sourcePath).extensions[0];
				if (extensionSourceFile != null) {
					targetPath =  targetPath + "." + extensionSourceFile;
				}
			}
			sys.io.File.saveBytes(targetPath, sys.io.File.getBytes(sourcePath));
		}
		return true;
	}

	function onDeleteFile( path : String ) {
		var fullPath = getFilePath(path);
		if( sys.FileSystem.isDirectory(fullPath) ) {
			for( f in sys.FileSystem.readDirectory(fullPath) )
				onDeleteFile(path + "/" + f);
			sys.FileSystem.deleteDirectory(fullPath);
		} else
			sys.FileSystem.deleteFile(fullPath);
	}

	function getFilePath(path:String) {
		if( path == "" )
			return ide.getPath(state.path).substr(0, -1);
		return ide.getPath(state.path) + path;
	}

	function onOpenFile( path : String ) {
		var fullPath = getFilePath(path);
		if( sys.FileSystem.isDirectory(fullPath) )
			return false;
		var ext = getExtension(fullPath);
		if( ext == null )
			return false;
		ide.openFile(fullPath);

		if (Ide.inst.ideConfig.closeSearchOnFileOpen)
			tree.closeFilter();

		return true;
	}

	public function revealNode( path : String ) {
		var folders = path.split("/");
		var currentFolder = "";
		function _revealNode() {
			if( folders.length == 0 ) {
				tree.setSelection([path]);
				tree.revealNode(currentFolder);
				return;
			}
			if( currentFolder.length > 0 ) currentFolder += "/";
			currentFolder += folders.shift();
			tree.openNodeAsync(currentFolder, _revealNode);
		}
		_revealNode();
	}

	function createNew( basePath : String, ext : ExtensionDesc ) {
		if( basePath == null )
			basePath = "";
		var fullPath = getFilePath(basePath);
		if( !sys.FileSystem.isDirectory(fullPath) ) {
			basePath = new haxe.io.Path(basePath).dir;
			if( basePath == null ) basePath = "";
			fullPath = getFilePath(basePath);
		}

		var file = ide.ask(ext.options.createNew + " name:");
		if( file == null ) return;
		if( file.indexOf(".") < 0 && ext.extensions != null )
			file += "." + ext.extensions[0].split(".").shift();

		if( sys.FileSystem.exists(fullPath + "/" + file) ) {
			ide.error("File '" + file+"' already exists");
			createNew(basePath, ext);
			return;
		}

		// directory
		if( ext.component == null ) {
			sys.FileSystem.createDirectory(fullPath + "/" + file);
			return;
		}

		var view : hide.view.FileView = Type.createEmptyInstance(Type.resolveClass(ext.component));
		view.ide = ide;
		view.state = { path : basePath+"/"+file };
		sys.io.File.saveBytes(fullPath + "/" + file, view.getDefaultContent());

		var fpath = basePath == "" ? file : basePath + "/" + file;
		tree.refresh(function() tree.setSelection([fpath]));
		onOpenFile(fpath);
	}

	function isIgnored( fullpath : String ) {
		for(pat in ignorePatterns) {
			if(pat.match(fullpath))
				return true;
		}
		return false;
	}

	static var EXTENSIONS = new Map<String,ExtensionDesc>();
	public static function registerExtension<T>( c : Class<hide.ui.View<T>>, extensions : Array<String>, ?options : ExtensionOptions ) {
		hide.ui.View.register(c);
		if( options == null ) options = {};
		var obj = { component : Type.getClassName(c), options : options, extensions : extensions };
		for( e in extensions )
			EXTENSIONS.set(e, obj);
		return null;
	}

	static var _ = hide.ui.View.register(FileTree, { width : 350, position : Left });

}
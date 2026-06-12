package hrt.tools;

// enum abstract GenToManagerCommand(String) {
// 	var success;
// }

// enum abstract ManagerToGenCommand(String) {
// 	var queue;
// 	var prio;
// 	var clear;
// }

// typedef GenToManagerSuccessMessage = {
// 	var originalPath : String;
// 	var thumbnailPath : String;
// }

#if hui

enum FileKind {
	Dir;
	File;
}

enum VCSStatus {
	/**
		Pending or no vsc available on system
	**/
	None;

	/**
		The file is up to date and not modified
	**/
	UpToDate;

	/**
		The file is modified locally
	**/
	Modified;
}

@:access(hrt.tools.FileManager)
@:allow(hrt.tools.FileManager)
class FileEntry {
	public var name: String;
	public var path: String;
	public var relPath: String;
	public var children: Array<FileEntry>;
	public var kind: FileKind;
	public var parent: FileEntry;
	public var iconPath: String; // can be null if the icon has not been loaded, call getIconPath to load it
	public var disposed: Bool = false;
	public var vcsStatus: VCSStatus = None;

	// Change this flag to true to watch each folder independently (causes issues on windows where watched
	// folders can't be removed in the explorer, but is needed on linux because libUV doesn't support recursive
	// filewatches on it)
	static final emulateRecursive = false;

	/**
		The file should not appear in the hierarchy, it's children are not computed, and is not watched
	**/
	public var ignored: Bool = false;

	#if hl
	var watcher : hl.uv.Fs = null;
	#end

	public function new(name: String, parent: FileEntry, kind: FileKind, absDir: String = null) {
		if (absDir != null && parent != null)
			throw "Parent and rootPath parameters are exclusive";
		this.name = name;
		this.parent = parent;
		this.kind = kind;
		this.relPath = parent == null ? "" : parent.getChildRelPath(name);
		if (absDir != null) {
			this.path = absDir + "/" + name;
		} else {
			this.path = parent.getChildPath(name);
		}
		this.ignored = computeIgnore();

		trace("added " + getRelPath());
		watch();

		if (FileManager.inst.fileIndex.get(this.getRelPath()) != null) {
			throw "Entry already exists";
		}

		FileManager.inst.fileIndex.set(this.getRelPath(), this);
		refreshChildren();
	}

	public final function toString() : String{
		return name;
	}

	public function dispose() {
		if (children != null) {
			for (child in children) {
				child.dispose();
			}
		}
		trace("removed " + getRelPath());

		disposed = true;
		children = null;
		#if hl
		if (watcher != null) {
			watcher.close();
		}
		#end
		FileManager.inst.fileIndex.remove(this.getRelPath());

	}

	// public function getIcon(onReady: MiniatureReadyCallback) {
	// 	if (iconPath != null && iconPath != "loading")
	// 		onReady(iconPath);
	// 	else {
	// 		@:privateAccess FileManager.inst.renderMiniature(this, onReady);
	// 	}
	// }

	function refreshChildren() {
		if (kind != Dir)
			return;
		if (ignored)
			return;

		var fullPath = getPath();

		var oldChildren : Map<String, FileEntry> = [for (file in (children ?? [])) file.name => file];

		if (children == null)
			children = [];
		else
			children.resize(0);

		if (sys.FileSystem.exists(fullPath)) {
			var paths = sys.FileSystem.readDirectory(fullPath);

			for (path in paths) {
				var prev = oldChildren.get(path);
				if (prev != null) {
					children.push(prev);
					oldChildren.remove(path);
				} else {
					var newEntry = new FileEntry(path, this, sys.FileSystem.isDirectory(fullPath + "/" + path) ? Dir : File);
					children.push(newEntry);
				}
			}
		}

		for (child in oldChildren) {
			child.dispose();
		}

		children.sort(compareFile);
	}

	function changed() {
		FileManager.inst.fileChangeInternal(this);
	}

	function watch() {
		#if hl
		if (watcher != null)
			throw "already watching";
		if (ignored)
			return;
		if (!emulateRecursive && parent != null)
			return;
		if (kind == Dir) {
			watcher = new hl.uv.Fs(null, this.getPath(), (event) -> {
				var name = watcher.contentChangedPath;
				if (!emulateRecursive && name != null) {
					name = StringTools.replace(name, "\\", "/");
				}
				onChildChange(name);
			} , !emulateRecursive);
			if (watcher.handle == null)
				throw "Couldn't watch directory " + this.getPath();
		}
		#end
	}

	function onChildChange(name: String) : FileEntry {
		if (ignored)
			return null;

		if (name == null) {
			refreshChildren();
			changed();
			return this;
		}

		if (!emulateRecursive) {
			var parts = name.split("/");
			if (parts.length >= 2) {
				var directChild = onChildChange(parts.shift());
				return directChild?.onChildChange(parts.join("/"));
			}
		}

		var childPath = getChildRelPath(name);
		var child = FileManager.inst.fileIndex.get(childPath);

		if (child != null) {
			child.changed();
			var current = child;
			if (!sys.FileSystem.exists(current.getPath())) {
				children.remove(child);
				child.dispose();
				changed();
			}
		} else {
			if (sys.FileSystem.exists(getChildPath(name))) {
				child = new FileEntry(name, this, sys.FileSystem.isDirectory(getChildPath(name)) ? Dir : File);
				if (children == null) {
					children = [];
				}
				children.push(child);
				children.sort(compareFile);
				changed();
			}
		}
		return child;
	}


	public inline function getRelPath() {
		return this.relPath;
	}

	public inline function getPath() {
		return this.path;
	}

	function getChildRelPath(name: String) {
		if (parent == null)
			return name;
		return relPath + "/" + name;
	}

	function getChildPath(name: String) {
		return path + "/" + name;
	}

	function computeIgnore() {
		return isIgnored(getRelPath());
	}

	public static function isIgnored(relPath: String) {
		for (excl in FileManager.inst.ignorePatterns) {
			if (excl.match(relPath))
				return true;
		}
		return false;
	}

	// sort directories before files, and then dirs and files alphabetically
	static public function compareFile(a: FileEntry, b: FileEntry) {
		if (a.kind != b.kind) {
			if (a.kind == Dir) {
				return -1;
			}
			return 1;
		}
		return Reflect.compare(a.name.toLowerCase(), b.name.toLowerCase());
	}
}

typedef MiniatureReadyCallback = (miniaturePath: String) -> Void;
typedef FileChangeCallback = (entry: FileEntry) -> Void;

/**
	Class that handle parsing and maintaining the state of the project files, and generate miniatures for them on demand
**/
class FileManager {

	public var fileRoot: FileEntry;
	var fileIndex : Map<String, FileEntry> = [];

	public static final thumbnailGeneratorPort = 9669;
	public static final thumbnailGeneratorUrl = "localhost";

	public static var inst(get, default) : FileManager;
	public var onFileChangeHandlers: Array<FileChangeCallback> = [];
	public var onVCSStatusUpdateHandlers: Array<() -> Void> = [];

	var ignorePatterns: Array<EReg> = [];

	var fileEntryRefreshDelay : Delayer<FileEntry>;


	static function get_inst() {
		if (inst == null) {
			inst = new FileManager();
			inst.init();
		}
		return inst;
	}

	function new() {

	}

	public static function onBeforeReload() {
		if (inst != null) {
			//inst.cleanupGenerator();
			//inst.cleanupServer();
		}
	}

	public function watchFileChange(callback: FileChangeCallback) {
		for (i => cb in onFileChangeHandlers) {
			if (Reflect.compareMethods(cb, callback) == true) {
				throw "callback already registered";
			}
		}
		onFileChangeHandlers.push(callback);
	}

	public function unwatchFileChange(callback: FileChangeCallback) {
		for (i => cb in onFileChangeHandlers) {
			if (Reflect.compareMethods(cb, callback) == true) {
				onFileChangeHandlers.splice(i, 1);
				return;
			}
		}
		throw "No callback was registered";
	}

	// Path-based filesystem api

	/**
		Copy multiple files to their given destinations
	**/
	public static function copyFilesPaths(operations: Array<{source: String, destination: String}>) {
		var roots = getRootsPaths([for (op in operations) op.source]);
		var newOp = [];
		for (source in roots) {
			for (op in operations) {
				if (source == op.source)
					newOp.push(op);
			}
		}

		operations = newOp;

		for (op in operations) {
			var absSource = ensureAbsPath(op.source);
			var absDest = ensureAbsPath(op.destination);
			if (sys.FileSystem.exists(absDest))
				throw '$absDest already exists';

			var newOps : Array<{source: String, destination: String, isDir: Bool}> = [];
			gatherCopyOperations(op.source, op.destination, newOps);

			for (op in newOps) {
				if (op.isDir) {
					sys.FileSystem.createDirectory(op.destination);
				} else {
					var content = sys.io.File.getBytes(op.source);
					sys.io.File.saveBytes(op.destination, content);
				}
			}
		}
	}

	/**
		Copy a file/folder from absSource to absDestination
	**/
	public static function copyFilePath(absSource: String, absDestination: String) {
		if (sys.FileSystem.isDirectory(absSource)) {
			sys.FileSystem.createDirectory(absDestination);
			for (file in sys.FileSystem.readDirectory(absSource)) {
				var subSource = absSource + "/" + file;
				if (subSource == absDestination)
					continue;
				copyFilePath(absSource + "/" + file, absDestination + "/" + file);
			}
		} else {
			var content = sys.io.File.getBytes(absSource);
			sys.io.File.saveBytes(absDestination, content);
		}
	}

	public static function deleteFilePath(absPath: String) : Void {
		if (sys.FileSystem.isDirectory(absPath)) {
			for (file in sys.FileSystem.readDirectory(absPath)) {
				deleteFilePath(haxe.io.Path.join([absPath, file]));
			}
			sys.FileSystem.deleteDirectory(absPath);
		} else {
			sys.FileSystem.deleteFile(absPath);
		}
	}

	static public function deleteFilesPaths(filePathsAbs : Array<String>) {
		var roots = getRootsPaths(filePathsAbs);
		for (file in roots) {
			try {
				deleteFilePath(file);
			} catch (e) {
				throw "Couldn't delete " + file + " : " + e;
			}
		}
	}

	public function deleteFiles(files : Array<FileEntry>) {
		var roots = getRoots(files);
		for (file in roots) {
			deleteFilePath(file.getPath());
		}
	}

	/**
		Like getRoots, but directly manipulate absolute paths instead of FileEntry objects
	**/
	static public function getRootsPaths(filesAbs: Array<String>) : Array<String> {
		var dirs: Array<String> = [];

		for (file in filesAbs) {
			if (sys.FileSystem.isDirectory(file)) {
				dirs.push(file);
			}
		}

		var roots: Array<String> = [];
		for (file in filesAbs) {
			var isContainedInAnotherDir = false;
			for (dir in dirs) {
				if (file == dir) {
					continue;
				}
				if (StringTools.contains(file, dir)) {
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

	/**
		Ensure that the given path is absolute (if it's not absolute, it is assumed that it is relative to the
		res path of the current project)
	**/
	static function ensureAbsPath(path: String) : String {
		if (!haxe.io.Path.isAbsolute(path))
			return hide.Ide.inst.getPath(path);
		return path;
	}

	/**
		List all the filesystem operations that must happen to copy currentPath to currentDest
	**/
	static function gatherCopyOperations(currentPath: String, currentDest: String, op: Array<{source: String, destination: String, isDir: Bool}>) : Void {
		if (sys.FileSystem.isDirectory(currentPath)) {
			op.push({source: currentPath, destination: currentDest, isDir: true});
			for (file in sys.FileSystem.readDirectory(currentPath)) {
				gatherCopyOperations(currentPath + "/" + file, currentDest + "/" + file, op);
			}
		} else {
			op.push({source: currentPath, destination: currentDest, isDir: false});
		}
	}

	/**
		Return file entry corresponding to given path if it exists
	**/
	public function getFileEntry(path: String) : Null<FileEntry> {
		var relPath = haxe.io.Path.isAbsolute(path) ? hide.Ide.inst.makeRelative(path) : path;
		return fileIndex.get(relPath);
	}

	/**
		Return a filtered array that that only contains files/directories that are not already contained in
		another directory in the list, to simplify bulk operations
	**/
	public function getRoots(files: Array<FileEntry>) : Array<FileEntry> {
		var dirs : Array<FileEntry> = [];

		for (file in files) {
			if(file.kind == Dir) {
				dirs.push(file);
			}
		}

		// Find the minimum ammount of files that need to be moved
		var roots: Array<FileEntry> = [];
		for (file in files) {
			var isContainedInAnotherDir = false;
			for (dir2 in dirs) {
				if (file == dir2)
					continue;
				if (StringTools.contains(file.getPath(), dir2.getPath())) {
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

	function init() {
		var exclPatterns : Array<String> = hide.Ide.inst.currentConfig.get("filetree.excludes", []);
		ignorePatterns = [];
		ignorePatterns.push(~/\.tmp/i);

		for(pat in exclPatterns)
			ignorePatterns.push(new EReg(pat, "i"));

		initFileSystem();
	}

	function initFileSystem() {
		fileEntryRefreshDelay = new Delayer((entry: FileEntry) -> {
			entry.refreshChildren();
		});


		var rootPath = new haxe.io.Path(hide.Ide.inst.resourceDir);
		fileRoot = new FileEntry(rootPath.file, null, Dir, rootPath.dir);

		queueRefreshSVN();
	}

	function fileChangeInternal(entry: FileEntry) {
		// invalidate thumbnail
		entry.iconPath = null;

		if (entry.kind == Dir) {
			fileEntryRefreshDelay.queue(entry);
		}

		queueRefreshSVN();

		for (handler in onFileChangeHandlers) {
			handler(entry);
		}
	}

	/**
		Checks that the live file system matches the actual file system (to check that there are no desyncs)
	**/
	function checkIntegrity() : Bool {
		var rootPath = new haxe.io.Path(hide.Ide.inst.resourceDir);

		function rec(path: String) : Bool {

			var relPath = StringTools.replace(path, rootPath.dir + "/", "");
			if (FileEntry.isIgnored(relPath))
				return true;

			var entry = fileIndex.get(relPath);
			if (entry == null)
				return false;

			if (entry.kind == Dir) {
				for (fileName in sys.FileSystem.readDirectory(path)) {
					rec(path + "/" + fileName);
				}
			}

			return true;
		}

		return rec(hide.Ide.inst.resourceDir);
	}

	public static function doRename(operations: Array<{from: String, to: String}>) {
		for (op in operations) {
			onRenameRec(op.from, "/" + op.to);
		}

		replacePathInFiles(operations);
	}

	public static function doRenameAbs(operations: Array<{from: String, to:String}>) {
		for (op in operations) {
			renameAbsInternal(op.from, op.to);
		}

		replacePathInFilesAbs(operations);
	}

	public static function onRenameRec(path:String, name:String) {
		var ide = hide.Ide.inst;
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

		if (!sys.FileSystem.exists(ide.getPath(path)))
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

				ide.app.ui.confirm(newPath+" already exists, invert files?", Cancel | Ok, (button) -> {
					if (button == Ok) {
						var rand = "__tmp"+Std.random(10000);
						onRenameRec(path, "/"+addPath(path,rand));
						onRenameRec(newPath, "/"+path);
						onRenameRec(addPath(path,rand), name);
					}
				});
			}
			return false;
		}

		var isDir = sys.FileSystem.isDirectory(ide.getPath(path));
		var wasRenamed = false;
		var isSVNRepo = sys.FileSystem.exists(ide.projectDir+"/.svn"); /*|| js.node.ChildProcess.spawnSync("svn",["info"], { cwd : ide.resourceDir }).status == 0;*/ // handle not root dirs
		if( isSVNRepo ) {
			if( hide.Ide.inst.isSVNAvailable ) {
				if( isDir && !ide.confirm("Renaming a SVN directory, but 'svn' system command was not found. Continue ?") )
					return false;
			} else {
				// Check if origin file and target directory are versioned
				var isFileVersioned = Sys.command("svn",["info", ide.getPath(path)]) == 0;
				var newAbsPath = ide.getPath(newPath);
				var parentFolder = newAbsPath.substring(0, newAbsPath.lastIndexOf('/'));
				var isDirVersioned = Sys.command("svn",["info", parentFolder]) == 0;
				if (isFileVersioned && isDirVersioned) {
					var cwd = Sys.getCwd();
					Sys.setCwd(ide.resourceDir);
					var code = Sys.command("svn",["rename", path, newPath]);
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
		if (newSysPath.ext?.toLowerCase() == "fbx" && oldSysPath.ext?.toLowerCase() == "fbx") {
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
				sys.io.File.saveContent(newMatPropsPath, hide.Ide.inst.toJSON(newMatProps));

				if (oldMatPropsPath != newMatPropsPath) {
					if (Reflect.fields(oldMatProps).length > 0) {
						sys.io.File.saveContent(oldMatPropsPath, hide.Ide.inst.toJSON(oldDataToSave));
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


	static function renameAbsInternal(sourceAbs: String, destAbs: String) : Bool {
		if( sourceAbs == destAbs )
			return false;

		if (!sys.FileSystem.exists(sourceAbs))
			return false;

		if( sys.FileSystem.exists(destAbs) ) {
			throw '$destAbs already exists';
			// function addPath(path:String,rand:String) {
			// 	var p = path.split(".");
			// 	if( p.length > 1 )
			// 		p[p.length-2] += rand;
			// 	else
			// 		p[p.length-1] += rand;
			// 	return p.join(".");
			// }
			// if( path.toLowerCase() == newPath.toLowerCase() ) {
			// 	// case change
			// 	var rand = "__tmp"+Std.random(10000);
			// 	onRenameRec(path, "/"+addPath(path,rand));
			// 	onRenameRec(addPath(path,rand), name);
			// } else {

			// 	ide.app.ui.confirm(newPath+" already exists, invert files?", Cancel | Ok, (button) -> {
			// 		if (button == Ok) {
			// 			var rand = "__tmp"+Std.random(10000);
			// 			onRenameRec(path, "/"+addPath(path,rand));
			// 			onRenameRec(newPath, "/"+path);
			// 			onRenameRec(addPath(path,rand), name);
			// 		}
			// 	});
			// }
			return false;
		}

		var ide = hide.Ide.inst;

		var isDir = sys.FileSystem.isDirectory(sourceAbs);
		var wasRenamed = false;

		var isSVNRepo = sys.FileSystem.exists(ide.projectDir+"/.svn"); /*|| js.node.ChildProcess.spawnSync("svn",["info"], { cwd : ide.resourceDir }).status == 0;*/ // handle not root dirs
		if( isSVNRepo ) {
			if( hide.Ide.inst.isSVNAvailable ) {
				if( isDir && !ide.confirm("Renaming a SVN directory, but 'svn' system command was not found. Continue ?") )
					return false;
			} else {
				// Check if origin file and target directory are versioned
				var isFileVersioned = Sys.command("svn",["info", sourceAbs]) == 0;
				var newAbsPath = sourceAbs;
				var parentFolder = newAbsPath.substring(0, newAbsPath.lastIndexOf('/'));
				var isDirVersioned = Sys.command("svn",["info", parentFolder]) == 0;
				if (isFileVersioned && isDirVersioned) {
					var cwd = Sys.getCwd();
					Sys.setCwd(ide.resourceDir);
					var code = Sys.command("svn",["rename", sourceAbs, newAbsPath]);
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
			sys.FileSystem.rename(sourceAbs, destAbs);

		var dataDir = new haxe.io.Path(sourceAbs);
		if( dataDir.ext != "dat" ) {
			dataDir.ext = "dat";
			var dataPath = dataDir.toString();
			if( sys.FileSystem.isDirectory(dataPath) ) {
				var destPath = new haxe.io.Path(destAbs);
				destPath.ext = "dat";
				renameAbsInternal(dataPath, destPath.toString());
			}
		}

		// update Materials.props if an FBX is moved/renamed
		var newSysPath = new haxe.io.Path(destAbs);
		var oldSysPath = new haxe.io.Path(sourceAbs);
		if (newSysPath.dir == null) {
			newSysPath.dir = oldSysPath.dir;
		}
		if (newSysPath.ext?.toLowerCase() == "fbx" && oldSysPath.ext?.toLowerCase() == "fbx") {

			var oldMatPropsPath = (oldSysPath.dir ?? "") + "/materials.props";

			if (sys.FileSystem.exists(oldMatPropsPath)) {
				var newMatPropsPath = ide.getPath((newSysPath.dir ?? "") + "/materials.props");

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
				sys.io.File.saveContent(newMatPropsPath, hide.Ide.inst.toJSON(newMatProps));

				if (oldMatPropsPath != newMatPropsPath) {
					if (Reflect.fields(oldMatProps).length > 0) {
						sys.io.File.saveContent(oldMatPropsPath, hide.Ide.inst.toJSON(oldDataToSave));
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

	public static function replacePathInFilesAbs(operations: Array<{from: String, to: String}>) {
		var copy = operations.copy();
		var ide = hide.Ide.inst;
		for (op in copy) {
			op.from = ide.getRelPath(op.from);
			op.to = ide.getRelPath(op.to);
		}
		replacePathInFiles(copy);
	}

	public static function replacePathInFiles(operations: Array<{from: String, to: String}>) {
		function filter(ctx: FilterPathContext) {
			var p = ctx.valueCurrent;
			if( p == null )
				return;
			for (op in operations) {
				var oldPath = op.from;
				var newPath = op.to;

				if( p == oldPath ) {
					ctx.change(newPath);
					return;
				}
				if( p == "/"+oldPath ) {
					ctx.change(newPath);
					return;
				}
				if( StringTools.startsWith(p,oldPath+"/") ) {
					ctx.change(newPath + p.substr(oldPath.length));
					return;
				}
				if( StringTools.startsWith(p,"/"+oldPath+"/") ) {
					ctx.change("/"+newPath + p.substr(oldPath.length+1));
					return;
				}
			}
		}

		FileManager.inst.filterPaths(filter);
	}

	/**
		Iterate throught all the strings in the project that could contain a path, replacing
		the value by what `callb` returns. The callb must call `changed()` if it changed the path.
	**/
	public function filterPaths(callb: (ctx : FilterPathContext) -> Void) {
		var ide = hide.Ide.inst;
		var context = new FilterPathContext(callb);

		var adaptedFilter = function(name: String) {
			return context.filter(name, context.currentObject);
		}

		function filterContent(content:Dynamic) {
			var visited = new Map<{}, Bool>();
			function browseRec(obj:Dynamic, parent: Dynamic) : Dynamic {
				switch( Type.typeof(obj) ) {
				case TObject:
					if( visited.exists(cast obj)) return null;
					visited.set(cast obj, true);
					for( f in Reflect.fields(obj) ) {
						var v : Dynamic = Reflect.field(obj, f);
						v = browseRec(v, obj);
						if( v != null ) Reflect.setField(obj, f, v);
					}
				case TClass(Array):
					if( visited.exists(cast obj)) return null;
					visited.set(cast obj, true);
					var arr : Array<Dynamic> = obj;
					for( i in 0...arr.length ) {
						var v : Dynamic = arr[i];
						v = browseRec(v, arr);
						if( v != null ) arr[i] = v;
					}
				case TClass(String):
					return context.filter(obj, parent);
				default:
				}
				return null;
			}
			for( f in Reflect.fields(content) ) {
				if (f == "children")
					continue;
				var v = browseRec(Reflect.field(content,f), content);
				if( v != null ) Reflect.setField(content,f,v);
			}
		}

		{
			var currentPath : String = null;
			var currentPrefab: hrt.prefab.Prefab = null;
			context.getRef = () -> {
				var p = currentPath; // needed capture
				var cp = currentPrefab; // needed capture
				return {str: '$p:${cp.getAbsPath()}', goto: () -> throw "implement" /*openFile(getPath(p), null, (view) -> {
					var pref = Std.downcast(view, hide.view.Prefab);
					if (pref != null) {
						pref.delaySceneEditor(() -> {
							pref.sceneEditor.selectElementsIndirect([cp]);
						});
					}
					else {
						var fx = Std.downcast(view, hide.view.FXEditor);
						fx.delaySceneEditor(() -> {
							@:privateAccess fx.sceneEditor.selectElementsIndirect([cp]);
						});
					}
				})*/};
			};

			filterPrefabs(function(p:hrt.prefab.Prefab, path: String) {
				context.changed = false;
				currentPath = path;
				currentPrefab = p;
				context.currentObject = p;
				p.source = context.filter(p.source, p);
				/*var h = p.getHideProps();
				if( h.onResourceRenamed != null )
					h.onResourceRenamed(adaptedFilter);
				else {*/
				filterContent(p);
				/*}*/
				return context.changed;
			});
		}

		{
			var currentPath : String = null;
			context.getRef = () -> {
				var p = currentPath;
				return {str: p, goto : () -> throw "implement"/*Ide.showFileInExplorer.bind(getPath(p))*/};
			}

			filterProps(function(content:Dynamic, path: String) {
				context.changed = false;
				currentPath = path;
				filterContent(content);
				return context.changed;
			});
		}


		context.changed = false;
		var tmpSheets = [];

		var currentSheet : cdb.Sheet = null;
		var currentColumn : String = null;
		var currentObject : Dynamic = null;
		context.getRef = () -> {
			var cs = currentSheet;
			var cc = currentColumn;
			var sheets = cdb.Sheet.getSheetPath(cs, cc);

			var path = CdbUtils.splitPath({s: sheets, o: currentObject});
			return {str: sheets[0].s.name+"."+path.pathNames.join("."), goto: () -> throw "implement" /*hide.comp.cdb.Editor.openReference2.bind(sheets[0].s, path.pathParts)*/};
		};

		for( sheet in ide.database.sheets ) {
			if( sheet.props.dataFiles != null && sheet.lines == null ) {
				// we already updated prefabs, no need to load data files
				tmpSheets.push(sheet);
				@:privateAccess sheet.sheet.lines = [];
			}
			for( c in sheet.columns ) {
				switch( c.type ) {
				case TFile:
					var sheets = cdb.Sheet.getSheetPath(sheet, c.name);
					for( obj in sheet.getObjects() ) {
						currentSheet = sheet;
						currentColumn = c.name;
						currentObject = obj;
						var path = Reflect.field(obj.path[obj.path.length - 1], c.name);
						var v : Dynamic = context.filter(path, obj.path[obj.path.length - 1]);
						if( v != null ) Reflect.setField(obj.path[obj.path.length - 1], c.name, v);
					}
				case TTilePos:
					var sheets = cdb.Sheet.getSheetPath(sheet, c.name);
					for( obj in sheet.getObjects() ) {
						currentSheet = sheet;
						currentColumn = c.name;
						currentObject = obj;

						var tilePos : cdb.Types.TilePos = Reflect.field(obj.path[obj.path.length - 1], c.name);
						if (tilePos != null) {
							var v : Dynamic = context.filter(tilePos.file, tilePos);
							if (v != null) Reflect.setField(tilePos, 'file', v);
						}
					}
				default:
				}
			}
		}
		if( context.changed ) {
			ide.saveDatabase();
			/*hide.comp.cdb.Editor.refreshAll(true);*/
		}
		for( sheet in tmpSheets )
			@:privateAccess sheet.sheet.lines = null;

		/*for (customFilter in customFilepathRefFilters) {
			customFilter(context);
		}*/
	}

	public function filterPrefabs( callb : (hrt.prefab.Prefab, path: String) -> Bool) {
		var ide = hide.Ide.inst;

		var exts = Lambda.array({iterator : @:privateAccess hrt.prefab.Prefab.extensionRegistry.keys });
		exts.push("prefab");
		var todo = [];
		browseFiles(function(path) {
			var ext = path.split(".").pop();
			if( exts.indexOf(ext) < 0 ) return;
			var prefab = try {
				ide.loadPrefab(path);
			} catch (e) {
				hide.Ide.showWarning("Couldn't open '" + path + "' to fix paths, error:" + e);
				return;
			}
			var changed = false;
			function filterRec(p) {
				if( callb(p, path) ) changed = true;
				for( ps in p.children )
					filterRec(ps);
			}
			filterRec(prefab);
			if( !changed ) return;
			@:privateAccess todo.push(function() sys.io.File.saveContent(ide.getPath(path), ide.toJSON(prefab.serialize())));
		});
		for( t in todo )
			t();
	}

	public function filterProps( callb : (data: Dynamic, path: String) -> Bool ) {
		var ide = hide.Ide.inst;

		var exts = ["props", "json"];
		var todo = [];
		browseFiles(function(path) {
			var ext = path.split(".").pop();
			if( exts.indexOf(ext) < 0 ) return;
			try {
				var content = ide.parseJSON(sys.io.File.getContent(ide.getPath(path)));
				var changed = callb(content, path);
				if( !changed ) return;
				todo.push(function() sys.io.File.saveContent(ide.getPath(path), ide.toJSON(content)));
			} catch (e) {};
		});
		for( t in todo )
			t();
	}

	function browseFiles( callb : String -> Void ) {
		var ide = hide.Ide.inst;

		function browseRec(path) {
			if( path == ".tmp" ) return;
			if( path == ".backed" ) return;

			for( p in sys.FileSystem.readDirectory(ide.resourceDir + "/" + path) ) {
				var p = path == "" ? p : path + "/" + p;
				if( sys.FileSystem.isDirectory(ide.resourceDir+"/"+p) ) {
					browseRec(p);
					continue;
				}
				callb(p);
			}
		}
		browseRec("");
	}



	// SVN Support
	function queueRefreshSVN() {
		if (hide.Ide.inst.isSVNAvailable) {
			getSVNModifiedFiles(onSVNFileModified);
		}
	}

	var delayedSvnStatusCallbacks : Array<(files : Array<String>) -> Void> = null;
	function getSVNModifiedFiles(callback: (files : Array<String>) -> Void) : Void{
		if (!hide.Ide.inst.isSVNAvailable)
			throw "SVN not available";

		if (delayedSvnStatusCallbacks == null) {
			delayedSvnStatusCallbacks = [];
			execSvnModifiedCommand(onSvnStatusFinished.bind([callback]));
		} else {
			delayedSvnStatusCallbacks.push(callback);
		}
	}

	function onSvnStatusFinished(callbacks: Array<(files : Array<String>) -> Void>, process: sys.io.Process) {
		var modifiedFiles : Array<String> = [];
		var ide = hide.Ide.inst;

		var stdout = process.stdout.readAll().toString();
		var outputs : Array<String> = stdout.split("\r\n");
		for (o in outputs) {
			if (o.length == 0)
				continue;

			o = StringTools.replace(o, '\\', "/");
			var file = ide.getPath(o.substr(o.indexOf("res/") + 4));
			modifiedFiles.push(file);
		}
		for (callback in callbacks) {
			callback(modifiedFiles);
		}

		if (delayedSvnStatusCallbacks != null && delayedSvnStatusCallbacks.length > 0) {
			var oldCallbacks = delayedSvnStatusCallbacks;
			delayedSvnStatusCallbacks = [];
			execSvnModifiedCommand(onSvnStatusFinished.bind(delayedSvnStatusCallbacks));
		} else {
			delayedSvnStatusCallbacks = null;
		}
	}

	function execSvnModifiedCommand(cb: (sys.io.Process) -> Void) {
		new ProcessAsync('svn', ["status", hide.Ide.inst.projectDir], cb);
	}

	function onSVNFileModified(modifiedFiles: Array<String>) {
		for (file in fileIndex) {
			file.vcsStatus = UpToDate;
		}

		for (modifiedFile in modifiedFiles) {
			var relPath = hide.Ide.inst.getRelPath(modifiedFile);
			var file = fileIndex.get(relPath);

			while(file != null && file.vcsStatus != Modified) {
				file.vcsStatus = Modified;
				file = file.parent;
			}
		}

		for (handler in onVCSStatusUpdateHandlers) {
			handler();
		}
	}

	/**
		Return the path to a temporary file with all the paths in the files array inside
	**/
	public function createSVNFileList(files: Array<FileEntry>) : String {
		var tmpdir = Sys.getEnv("TEMP");
		var name = 'hidefiles${Std.int(hxd.Math.random(100000000))}.txt';
		var path = tmpdir + "/" + name;

		var str = [for(f in files) f.getPath()].join("\n");

		// Encode paths as utf-16 because tortoiseproc want the file encoded that way
		var bytes = haxe.io.Bytes.alloc(str.length * 2);
		var pos = 0;

		for (char in 0...str.length) {
			bytes.setUInt16(pos, str.charCodeAt(char));
			pos += 2;
		}
		sys.io.File.saveBytes(path, bytes);
		return path;
	}
}


@:allow(hrt.tools.FileManager)
class FilterPathContext {
	public var valueCurrent: String;
	public var currentObject: Dynamic;
	var valueChanged: String;

	public var filterFn: (FilterPathContext) -> Void;

	var changed = false;
	public function new(filterFn: (FilterPathContext) -> Void) {
		this.filterFn = filterFn;
	};

	public function change(newValue) : Void {
		changed = true;
		valueChanged = newValue;
	}

	public function filter(valueCurrent: String, obj: Dynamic) {
		this.valueCurrent = valueCurrent;
		this.currentObject = obj;
		valueChanged = null;
		var prevChanged = changed;
		changed = false;
		filterFn(this);
		var res = changed ? valueChanged : valueCurrent;
		changed = prevChanged || changed;
		return res;
	}

	public var getRef : () -> {str: String, ?goto: () -> Void};
}

#end


// enum RenderWindowState {
// 	Pending;
// 	Ready;
// }

// @:allow(hrt.tools.FileManager)
// @:access(hrt.tools.FileManager)
// class RenderWindowManager {
// 	var state : RenderWindowState = Pending;
// 	var generatorWindow : nw.Window;

// 	function new() {
// 		state = Pending;
// 		// wait that the browser is idle before creating the rendering window, so
// 		// the generator socket is properly initialised
// 		untyped js.Browser.window.requestIdleCallback(() -> {
// 			state = Ready;
// 			nw.Window.open('app.html?thumbnail=true', cast {
// 					new_instance: true,
// 					show: false,
// 					title: "HideThumbnailGenerator"
// 				}, (win: nw.Window) -> {
// 					generatorWindow = win;
// 				win.on("close", () -> {
// 					hrt.tools.FileManager.cleanupGenerator();
// 				});
// 			});
// 		}, {timeout: 1000});
// 	}


// }
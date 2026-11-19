package hide.tools;


enum abstract GenToManagerCommand(String) {
	var start;
	var success;
}

enum abstract ManagerToGenCommand(String) {
	var queue;
	var prio;
	var clear;
}

typedef GenToManagerSuccessMessage = {
	var originalPath : String;
	var thumbnailPath : String;
}

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

@:access(hide.tools.FileManager)
@:allow(hide.tools.FileManager)
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
	public var ignored: Bool = false;

	// last known modification time, file system events older than it are ignored
	var stamp : Float = Date.now().getTime();
	var changeTimer : haxe.Timer = null;

	public function new(name: String, parent: FileEntry, kind: FileKind) {
		this.name = name;
		this.parent = parent;
		this.kind = kind;
		this.relPath = computeRelPath();
		this.path = computePath();
		this.ignored = computeIgnore();

		FileManager.inst.fileIndex.set(this.getRelPath(), this);
		FileManager.inst.addToExtIndex(this);
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
		disposed = true;
		children = null;
		FileManager.inst.fileIndex.remove(this.getRelPath());
		FileManager.inst.removeFromExtIndex(this);
	}

	public function getIcon(onReady: MiniatureReadyCallback) {
		if (iconPath != null && iconPath != "loading")
			onReady(iconPath);
		else {
			@:privateAccess FileManager.inst.renderMiniature(this, onReady);
		}
	}

	function refreshChildren() {
		if (kind != Dir)
			return;
		var fullPath = getPath();

		var oldChildren : Map<String, FileEntry> = [for (file in (children ?? [])) file.name => file];

		if (children == null)
			children = [];
		else
			children.resize(0);

		if (js.node.Fs.existsSync(fullPath)) {
			var entries : Array<Dynamic> = (js.node.Fs : Dynamic).readdirSync(fullPath, { withFileTypes : true });

			for (entry in entries) {
				var path : String = entry.name;
				if (StringTools.startsWith(path, "."))
					continue;
				var prev = oldChildren.get(path);
				if (prev != null) {
					children.push(prev);
					oldChildren.remove(path);
				} else {
					var isDir : Bool = entry.isSymbolicLink() ? js.node.Fs.statSync(fullPath + "/" + path).isDirectory() : entry.isDirectory();
					var newEntry = new FileEntry(path, this, isDir ? Dir : File);
					newEntry.refreshChildren();
					children.push(newEntry);
				}
			}
		}

		for (child in oldChildren) {
			child.dispose();
		}

		children.sort(compareFile);
	}

	public inline function getRelPath() {
		return this.relPath;
	}

	public inline function getPath() {
		return this.path;
	}

	function computePath() {
		if (this.parent == null) return hide.Ide.inst.resourceDir;
		return this.parent.computePath() + "/" + this.name;
	}

	function computeRelPath() {
		if (this.parent == null) return "";
		if (this.parent.parent == null) return this.name;
		return this.parent.computeRelPath() + "/" + this.name;
	}

	function computeIgnore() {
		for (excl in FileManager.inst.ignorePatterns) {
			if (excl.match(getRelPath()))
				return true;
		}
		return return false;
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

/**
	Class that handle parsing and maintaining the state of the project files, and generate miniatures for them on demand
**/
class FileManager {

	public var fileRoot: FileEntry;
	var fileIndex : Map<String, FileEntry> = [];
	// lowercase extension without the dot => files
	var extIndex : Map<String, {version: Int, files: Map<FileEntry, Bool>}> = [];

	public static var inst(get, default) : FileManager;
	public var onFileChangeHandlers: Array<(entry: FileEntry) -> Void> = [];
	public var onVCSStatusUpdateHandlers: Array<() -> Void> = [];

	var svnEnabled = false;

	var windowManager : RenderWindowManager = null;

	var onReadyCallbacks : Map<String, Array<MiniatureReadyCallback>> = [];

	var generatorPort : js.html.MessagePort = null;
	var ignorePatterns: Array<EReg> = [];


	var fileEntryRefreshDelay : Delayer<FileEntry>;

	var retries = 0;
	static final maxRetries = 5;

	var currentJob : String = null;
	var jobTimer : haxe.Timer = null;
	static final jobTimeout = 20000;
	// files that crashed or hung the generator, skipped until they change
	var failedPaths : Map<String, Bool> = [];

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
			inst.cleanupGenerator();
		}
	}

	public function deleteFiles(files : Array<FileEntry>) {
		//trace(fullPaths);
		var roots = getRoots(files);
		for (file in roots) {
			if( file.kind == Dir ) {
				file.dispose(); // kill watchers
				untyped js.node.Fs.rmSync(file.getPath(), {force: true, recursive: true});
			} else {
				file.dispose(); // kill watchers
				untyped js.node.Fs.rmSync(file.getPath(), {force: true, recursive: false});
			}
		}
	}

	public function getFileEntry(path: String) {
		var relPath = hide.Ide.inst.makeRelative(path);
		return fileIndex.get(relPath);
	}

	public function getFilesWithExt(ext: String) : Iterator<FileEntry> {
		var entry = extIndex.get(ext.toLowerCase());
		return entry != null ? entry.files.keys() : [].iterator();
	}

	/**
		Incremented each time the set of files with `ext` changes, 0 if no file ever had `ext`
	**/
	public function getFilesWithExtCacheVersion(ext: String) : Int {
		return extIndex.get(ext.toLowerCase())?.version ?? 0;
	}

	function addToExtIndex(entry: FileEntry) {
		if (entry.kind != File)
			return;

		var ext = haxe.io.Path.extension(entry.name).toLowerCase();
		var extEntry = extIndex.get(ext);
		if (extEntry == null) {
			extEntry = {version: 0, files: []};
			extIndex.set(ext, extEntry);
		}
		if (!extEntry.files.exists(entry)) {
			extEntry.files.set(entry, true);
			extEntry.version++;
		}
	}

	// empty entries are kept so their version never goes back to 0
	function removeFromExtIndex(entry: FileEntry) {
		if (entry.kind != File)
			return;

		var extEntry = extIndex.get(haxe.io.Path.extension(entry.name).toLowerCase());
		if (extEntry != null && extEntry.files.remove(entry))
			extEntry.version++;
	}

	// Deduplicate paths if they are contained in a directory
	// also present in paths, to simplify bulk operations
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
		var tmpdir = js.node.Os.tmpdir();
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

	function onGeneratorConnected(port: js.html.MessagePort) {
		generatorPort = port;
		generatorPort.onmessage = (e : js.html.MessageEvent) -> processThumbnailGeneratorMessage(e.data);

		trace("Thumbnail generator connected");

		// resend command that weren't completed
		for (path => _ in onReadyCallbacks) {
			sendGenerateCommand(path);
		}
	}

	function cleanupGenerator() {
		if (generatorPort != null) {
			generatorPort.close();
			generatorPort = null;
		}

		if (windowManager != null && windowManager.generatorWindow != null) {
			windowManager.generatorWindow.close(true);
		}

		windowManager = null;

		for (win in electron.Window.getAll()) {
			if (win.title == "HideThumbnailGenerator") {
				win.close(true);
			}
		}
	}

	/**
		The generator crashed or hung : the file it was rendering is skipped until it changes, and the generator is restarted
	**/
	function onGeneratorLost(reason: String) {
		jobTimer?.stop();
		jobTimer = null;
		var path = currentJob;
		currentJob = null;
		cleanupGenerator();

		if (path != null) {
			js.html.Console.warn('Thumbnail generator error : $path : $reason');
			failedPaths.set(path, true);
			var file = getFileEntry(path);
			if (file != null)
				file.iconPath = null;
			var cbs = onReadyCallbacks.get(path);
			onReadyCallbacks.remove(path);
			if (cbs != null) {
				for (cb in cbs)
					cb(null);
			}
		}

		if (onReadyCallbacks.iterator().hasNext())
			checkWindowReady();
	}

	function init() {
		// kill generator when page is reloaded
		js.Browser.window.addEventListener('beforeunload', () -> cleanupGenerator());

		svnEnabled = hide.Ide.inst.isSVNAvailable();

		var exclPatterns : Array<String> = hide.Ide.inst.currentConfig.get("filetree.excludes", []);
		ignorePatterns = [];
		for(pat in exclPatterns)
			ignorePatterns.push(new EReg(pat, "i"));

		checkWindowReady();
		initFileSystem();
	}

	function initFileSystem() {
		fileEntryRefreshDelay = new Delayer((entry: FileEntry) -> {
			entry.refreshChildren();
		});

		hide.Ide.inst.fileWatcher.listenRoot(onFileSystemEvent);
		fileRoot = new FileEntry("res", null, Dir);
		fileRoot.refreshChildren();

		queueRefreshSVN();
	}

	function onFileSystemEvent(relPath: String, kind: String) {
		function queueChange(entry: FileEntry) {
			if (entry.changeTimer != null)
				entry.changeTimer.stop();
			entry.changeTimer = haxe.Timer.delay(() -> {
				entry.changeTimer = null;
				if (!entry.disposed)
					fileChangeInternal(entry);
			}, 100);
		}

		function updateStamp(entry: FileEntry, st: js.node.fs.Stats) {
			var time = Math.max(st.mtime.getTime(), st.ctime.getTime());
			if (time <= entry.stamp)
				return false;
			entry.stamp = time;
			return true;
		}

		// events were lost
		if (relPath == null) {
			for (entry in fileIndex)
				js.node.Fs.stat(entry.getPath(), (err, st) -> {
					if (err != null || updateStamp(entry, st))
						queueChange(entry);
				});
			return;
		}

		var entry = fileIndex.get(relPath);
		if (entry != null) {
			if (entry.kind == File) {
				var st = try js.node.Fs.statSync(entry.getPath()) catch (e: Dynamic) null;
				if (st == null || updateStamp(entry, st) || kind == "rename")
					queueChange(entry);
			} else if (kind == "rename") {
				queueChange(entry);
			}
		}

		// added, removed or replaced: refresh the parent directory
		if (kind == "rename") {
			var sep = relPath.lastIndexOf("/");
			var dir = fileIndex.get(sep < 0 ? "" : relPath.substr(0, sep));
			if (dir != null && dir.kind == Dir)
				queueChange(dir);
		}
	}

	function fileChangeInternal(entry: FileEntry) {
		// invalidate thumbnail
		entry.iconPath = null;
		failedPaths.remove(entry.getPath());

		if (!js.node.Fs.existsSync(entry.getPath()) && entry.parent != null) {
			fileEntryRefreshDelay.queue(entry.parent);
			return;
		}
		if (entry.kind == Dir) {
			fileEntryRefreshDelay.queue(entry);
		}

		queueRefreshSVN();

		for (handler in onFileChangeHandlers) {
			handler(entry);
		}
	}

	public function queueRefreshSVN() {
		if (svnEnabled) {
			hide.Ide.inst.getSVNModifiedFiles(onSVNFileModified);
		}
	}

	public function cloneFile(entry: FileEntry) {
		var sourcePath = entry.getPath();
		var nameNewFile = hide.Ide.inst.ask("New filename:", new haxe.io.Path(sourcePath).file);
		if (nameNewFile == null || nameNewFile.length == 0) {
			return false;
		}

		var targetPath = new haxe.io.Path(sourcePath).dir + "/" + nameNewFile;
		if ( sys.FileSystem.exists(targetPath) ) {
			throw "File already exists";
		}

		function rec(origin : String, target : String, depth : Int = 0) {
			if (sys.FileSystem.isDirectory(origin)) {
				sys.FileSystem.createDirectory(target + "/");
				for (f in sys.FileSystem.readDirectory(origin))
					rec(origin + "/" + f, target + "/" + f, depth + 1);
			} else {
				if (depth == 0 && target.indexOf(".") == -1) {
					var oldExt = origin.split(".").pop();
					target += "." + oldExt;
				}

				sys.io.File.saveBytes(target, sys.io.File.getBytes(origin));
			}
		}

		rec(sourcePath, targetPath, 0);

		return true;
	}


	function processThumbnailGeneratorMessage(message: Dynamic) {
		try {
			switch((message.type:GenToManagerCommand)) {
				case start:
					currentJob = message.path;
					jobTimer?.stop();
					jobTimer = haxe.Timer.delay(() -> onGeneratorLost('thumbnail generation timed out after ${jobTimeout}ms'), jobTimeout);
				case success:
					var message : GenToManagerSuccessMessage = message.data;
					if (message.originalPath == currentJob) {
						currentJob = null;
						jobTimer?.stop();
						jobTimer = null;
					}
					if (message.thumbnailPath != null)
						retries = 0;
					else
						failedPaths.set(message.originalPath, true);
					var cbs = onReadyCallbacks.get(message.originalPath);
					if (cbs == null) {
						return;
						//throw "Generated a thumbnail for a file not registered";
					}
					onReadyCallbacks.remove(message.originalPath);
					var file = getFileEntry(message.originalPath);
					if (file != null)
						file.iconPath = message.thumbnailPath;
					for (cb in cbs) {
						cb(message.thumbnailPath);
					}
				default:
					throw "Unknown message type " + message.type;
			}
		} catch(e) {
			hide.Ide.inst.quickError("Thumb Generator invalid message : " + e + "\n" + haxe.Json.stringify(message));
		}
	}

	var queued = false;

	/**
		Asynchronously generates a miniature.
		onReady is called back with the path of the loaded miniature, or null if the miniature couldn't be loaded
	**/
	function renderMiniature(file: FileEntry, onReady: MiniatureReadyCallback) {
		var path = file.getPath();
		if (retries >= maxRetries || failedPaths.exists(path)) {
			onReady(null);
			return;
		}
		var ext = path.split(".").pop().toLowerCase();
		switch(ext) {
			case "prefab" | "fbx" | "l3d" | "fx" | "shgraph" | "jpg" | "jpeg" | "png" | "dds":
				file.iconPath = "loading";
				var callbacks = onReadyCallbacks.get(path);
				if (callbacks == null) {
					onReadyCallbacks.set(path, [onReady]);
					sendGenerateCommand(path);
				} else {
					callbacks.push(onReady);
				}
			default:
				onReady(null);
		}
	}

	public function invalidateMiniature(file: FileEntry) {
		if (file.children != null) {
			for (child in file.children) {
				invalidateMiniature(child);
			}
			return;
		}
		if (file.iconPath != null && file.iconPath != "loading") {
			try {
				sys.FileSystem.deleteFile(file.iconPath);
			} catch (e) {};
		}

		file.iconPath = null;
	}

	public function checkWindowReady() {
		if (windowManager == null) {
			if (retries < maxRetries) {
				retries ++;
				windowManager = new RenderWindowManager();
			}
			if (retries == maxRetries) {
				js.Browser.window.alert("Max retries for thumbnail render window reached");
				retries++;
			}
			return false;
		}
		return generatorPort != null;
	}

	public function clearRenderQueue() {
		onReadyCallbacks.clear();
		if (!checkWindowReady()) {
			return;
		}
		generatorPort.postMessage({
			type: ManagerToGenCommand.clear,
		});
	}

	public function setPriority(path: String, newPriority: Int) {
		if (!onReadyCallbacks.exists(path)) {
			return;
		}
		// not sent before the generator is connected : the priorities are reset when it connects
		if (!checkWindowReady())
			return;
		generatorPort.postMessage({
			type: ManagerToGenCommand.prio,
			path: path,
			prio: newPriority
		});
	}

	function sendGenerateCommand(path: String) {
		if (!checkWindowReady()) {
			return;
		}
		generatorPort.postMessage({
			type: ManagerToGenCommand.queue,
			path: path,
		});
	}

	public static function doRename(operations: Array<{from: String, to: String}>) {
		for (op in operations)
			onRenameRec(op.from, "/" + op.to);

		replacePathInFiles(operations);
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
				// Check if origin file and target directory are versioned
				var isFileVersioned = js.node.ChildProcess.spawnSync("svn",["info", ide.getPath(path)]).status == 0;
				var newAbsPath = ide.getPath(newPath);
				var parentFolder = newAbsPath.substring(0, newAbsPath.lastIndexOf('/'));
				var isDirVersioned = js.node.ChildProcess.spawnSync("svn",["info", parentFolder]).status == 0;
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

		moveDatDir(path, newPath);
		renameAnimationProps(path, newPath);
		moveMaterialProps(path, newPath);

		return true;
	}

	public static function replacePathInFiles(operations: Array<{from: String, to: String}>) {
		function filter(ctx: hide.Ide.FilterPathContext) {
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

		hide.Ide.inst.filterPaths(filter, [for (op in operations) op.from]);
	}

	static function renameAnimationProps(path: String, newPath: String) {
		var oldFile = new haxe.io.Path(path);
		var newFile = new haxe.io.Path(newPath);
		var modelExts = ["fbx", "hmd"];
		if (!modelExts.contains(oldFile.ext?.toLowerCase()) || !modelExts.contains(newFile.ext?.toLowerCase()))
			return;

		var oldProps = new haxe.io.Path(path);
		oldProps.ext = "props";
		var newProps = new haxe.io.Path(newPath);
		newProps.ext = "props";
		var ide = hide.Ide.inst;
		if (!sys.FileSystem.exists(ide.getPath(oldProps.toString())))
			return;
		onRenameRec(oldProps.toString(), "/" + newProps.toString());

		var oldKey = oldFile.file + "." + oldFile.ext;
		var newKey = newFile.file + "." + newFile.ext;
		if (oldKey == newKey)
			return;
		var propsPath = ide.getPath(newProps.toString());
		var props : h3d.prim.ModelCache.HideProps = haxe.Json.parse(sys.io.File.getContent(propsPath));
		if (props.animations == null || !props.animations.exists(oldKey))
			return;
		props.animations.set(newKey, props.animations.get(oldKey));
		props.animations.remove(oldKey);
		sys.io.File.saveContent(propsPath, ide.toJSON(props));
	}

	static function moveDatDir(path: String, newPath: String) {
		var dataDir = new haxe.io.Path(path);
		if (dataDir.ext == "dat") {
			return;
		}
		dataDir.ext = "dat";
		if (!sys.FileSystem.isDirectory(hide.Ide.inst.getPath(dataDir.toString()))) {
			return;
		}
		var destDir = new haxe.io.Path(newPath);
		destDir.ext = "dat";
		onRenameRec(dataDir.toString(), "/" + destDir.toString());
	}

	static function moveMaterialProps(path: String, newPath: String) {
		var oldFile = new haxe.io.Path(path);
		var newFile = new haxe.io.Path(newPath);
		if (oldFile.ext?.toLowerCase() != "fbx" || newFile.ext?.toLowerCase() != "fbx") {
			return;
		}

		var ide = hide.Ide.inst;
		var oldMatPropsPath = ide.getPath(haxe.io.Path.join([oldFile.dir, "materials.props"]));
		if (!sys.FileSystem.exists(oldMatPropsPath)) {
			return;
		}
		var newMatPropsPath = ide.getPath(haxe.io.Path.join([newFile.dir, "materials.props"]));

		var oldMatProps = haxe.Json.parse(sys.io.File.getContent(oldMatPropsPath));
		var newMatProps : Dynamic = sys.FileSystem.exists(newMatPropsPath) ? haxe.Json.parse(sys.io.File.getContent(newMatPropsPath)) : {};

		var oldNameExt = oldFile.file + "." + oldFile.ext;
		var newNameExt = newFile.file + "." + newFile.ext;
		function moveRec(originalData: Dynamic, oldData: Dynamic, newData: Dynamic) {
			for (field in Reflect.fields(originalData)) {
				if (StringTools.endsWith(field, oldNameExt)) {
					var innerData = Reflect.getProperty(originalData, field);
					var newField = StringTools.replace(field, oldNameExt, newNameExt);
					Reflect.setProperty(newData, newField, innerData);
					Reflect.deleteField(oldData, field);
					continue;
				}

				var originalInner = Reflect.getProperty(originalData, field);
				if (Type.typeof(originalInner) != TObject)
					continue;

				var oldInner = Reflect.getProperty(oldData, field);
				var newInner = Reflect.getProperty(newData, field) ?? {};
				moveRec(originalInner, oldInner, newInner);

				if (Reflect.fields(newInner).length > 0) {
					Reflect.setProperty(newData, field, newInner);
				}
				if (Reflect.fields(oldInner).length == 0) {
					Reflect.deleteField(oldData, field);
				}
			}
		}

		var oldDataToSave = oldMatPropsPath == newMatPropsPath ? newMatProps : haxe.Json.parse(haxe.Json.stringify(oldMatProps));
		moveRec(oldMatProps, oldDataToSave, newMatProps);
		sys.io.File.saveContent(newMatPropsPath, ide.toJSON(newMatProps));

		if (oldMatPropsPath != newMatPropsPath) {
			if (Reflect.fields(oldMatProps).length > 0) {
				sys.io.File.saveContent(oldMatPropsPath, ide.toJSON(oldDataToSave));
			} else {
				sys.FileSystem.deleteFile(oldMatPropsPath);
			}
		}

		@:privateAccess {
			if (h3d.mat.MaterialSetup.current != null) {
				h3d.mat.MaterialSetup.current.database.db.remove(ide.makeRelative(oldMatPropsPath));
				h3d.mat.MaterialSetup.current.database.db.remove(ide.makeRelative(newMatPropsPath));
			}
			hxd.res.Loader.currentInstance.cache.remove(ide.makeRelative(oldMatPropsPath));
			hxd.res.Loader.currentInstance.cache.remove(ide.makeRelative(newMatPropsPath));
		}
	}
}


@:allow(hide.tools.FileManager)
@:access(hide.tools.FileManager)
class RenderWindowManager {
	var generatorWindow : electron.Window;

	function new() {
		generatorWindow = electron.Window.open('app.html?thumbnail=true&project=' + StringTools.urlEncode(hide.Ide.inst.projectDir), {
			show: false,
			title: "HideThumbnailGenerator"
		});
		generatorWindow.onConnect((port) -> {
			// a previous generator connecting after its replacement was started
			if (FileManager.inst.windowManager != this) {
				port.close();
				return;
			}
			FileManager.inst.onGeneratorConnected(port);
		});
		for (event in ["closed", "crashed"]) {
			generatorWindow.on(event, () -> {
				// a previous generator closing after its replacement was started
				if (FileManager.inst.windowManager != this)
					return;
				FileManager.inst.onGeneratorLost('generator window $event');
			});
		}
	}


}
package hide.tools;


enum abstract GenToManagerCommand(String) {
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
	public var iconPath: String;
	public var disposed: Bool = false;
	public var vcsStatus: VCSStatus = None;
	public var ignored: Bool = false;

	var registeredWatcher : hide.tools.FileWatcher.FileWatchEvent = null;

	public function new(name: String, parent: FileEntry, kind: FileKind) {
		this.name = name;
		this.parent = parent;
		this.kind = kind;
		this.relPath = computeRelPath();
		this.path = computePath();
		this.ignored = computeIgnore();

		watch();
		FileManager.inst.fileIndex.set(this.getRelPath(), this);
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
		if (registeredWatcher != null) {
			hide.Ide.inst.fileWatcher.unregister(this.getPath(), registeredWatcher.fun);
			registeredWatcher = null;
		}
		FileManager.inst.fileIndex.remove(this.getRelPath());
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
			var paths = js.node.Fs.readdirSync(fullPath);

			for (path in paths) {
				if (StringTools.startsWith(path, "."))
					continue;
				var prev = oldChildren.get(path);
				if (prev != null) {
					children.push(prev);
					oldChildren.remove(path);
				} else {
					var info = js.node.Fs.statSync(fullPath + "/" + path);
					var newEntry = new FileEntry(path, this, info.isDirectory() ? Dir : File);
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

	function watch() {
		if (registeredWatcher != null)
			throw "already watching";

		var rel = this.getRelPath();
		registeredWatcher = hide.Ide.inst.fileWatcher.register(rel, FileManager.inst.fileChangeInternal.bind(this), true);
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

	public static final thumbnailGeneratorPort = 9669;
	public static final thumbnailGeneratorUrl = "localhost";

	public static var inst(get, default) : FileManager;
	public var onFileChangeHandlers: Array<(entry: FileEntry) -> Void> = [];
	public var onVCSStatusUpdateHandlers: Array<() -> Void> = [];

	var svnEnabled = false;

	var windowManager : RenderWindowManager = null;

	var onReadyCallbacks : Map<String, MiniatureReadyCallback> = [];

	var serverSocket : hxd.net.Socket = null;
	var generatorSocket : hxd.net.Socket = null;
	var pendingMessages : Array<String> = [];
	var ignorePatterns: Array<EReg> = [];


	var fileEntryRefreshDelay : Delayer<FileEntry>;

	var retries = 0;
	static final maxRetries = 5;

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
			inst.cleanupServer();
		}
	}


	var pendingMessageQueued = false;
	function queueProcessPendingMessages() {
		if (!pendingMessageQueued) {
			haxe.Timer.delay(processPendingMessages, 10);
			pendingMessageQueued = true;
		}
	}
	function processPendingMessages() {
		pendingMessageQueued = false;
		if (!checkWindowReady()) {
			return;
		}
		var len = hxd.Math.imin(300, pendingMessages.length);
		for (i in 0 ... len) {
			generatorSocket.out.writeString(pendingMessages[i]);
		}
		pendingMessages.splice(0, len);
		if (pendingMessages.length > 0) {
			queueProcessPendingMessages();
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

	function setupServer() {
		if (serverSocket != null)
			throw "Server already exists";

		serverSocket = new hxd.net.Socket();
		serverSocket.onError = (msg) -> {
			hide.Ide.inst.quickError("FileManager socket error : " + msg);
			cleanupGenerator();
			cleanupServer();
		}
		serverSocket.bind(thumbnailGeneratorUrl, thumbnailGeneratorPort, (remoteSocket) -> {
			if (generatorSocket != null) {
				generatorSocket.close();
			}
			generatorSocket = remoteSocket;
			generatorSocket.onError = (msg) -> {
				hide.Ide.inst.quickError("Generator socket error : " + msg);
				cleanupGenerator();
			}

			var handler = new hide.tools.ThumbnailGenerator.MessageHandler(generatorSocket, processThumbnailGeneratorMessage);

			trace("Thumbnail generator connected");

			// resend command that weren't completed
			for (path => _ in onReadyCallbacks) {
				sendGenerateCommand(path);
			}

		});
	}

	function cleanupServer() {
		if (serverSocket != null) {
			serverSocket.close();
			serverSocket = null;
		}
	}

	function cleanupGenerator() {
		if (generatorSocket != null) {
			generatorSocket.close();
			generatorSocket = null;
		}

		if (windowManager != null && windowManager.generatorWindow != null) {
			windowManager.generatorWindow.close(true);
		}

		windowManager = null;

		untyped nw.Window.getAll((win:nw.Window) -> {
			if (win.title == "HideThumbnailGenerator") {
				win.close(true);
			}
		});
	}

	function init() {
		// kill server when page is reloaded
		js.Browser.window.addEventListener('beforeunload', () -> { cleanupGenerator(); cleanupServer(); });

		svnEnabled = hide.Ide.inst.isSVNAvailable();

		var exclPatterns : Array<String> = hide.Ide.inst.currentConfig.get("filetree.excludes", []);
		ignorePatterns = [];
		for(pat in exclPatterns)
			ignorePatterns.push(new EReg(pat, "i"));

		setupServer();
		checkWindowReady();
		initFileSystem();
	}

	function initFileSystem() {
		fileEntryRefreshDelay = new Delayer((entry: FileEntry) -> {
			entry.refreshChildren();
		});

		fileRoot = new FileEntry("res", null, Dir);
		fileRoot.refreshChildren();

		queueRefreshSVN();
	}

	function fileChangeInternal(entry: FileEntry) {
		// invalidate thumbnail
		entry.iconPath = null;

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

		if( sys.FileSystem.isDirectory(sourcePath) ) {
			sys.FileSystem.createDirectory(targetPath + "/");
			for( f in sys.FileSystem.readDirectory(sourcePath) ) {
				sys.io.File.saveBytes(targetPath + "/" + f, sys.io.File.getBytes(sourcePath + "/" + f));
			}
		} else {
			if (targetPath.indexOf(".") == -1) {
				var oldExt = sourcePath.split(".").pop();
				targetPath += "." + oldExt;
			}
			sys.io.File.saveBytes(targetPath, sys.io.File.getBytes(sourcePath));
		}
		return true;
	}


	function processThumbnailGeneratorMessage(message: String) {
		try {
			var message = haxe.Json.parse(message);
			switch(message.type) {
				case success:
					var message : GenToManagerSuccessMessage = message.data;
					var cb = onReadyCallbacks.get(message.originalPath);
					if (cb == null) {
						return;
						//throw "Generated a thumbnail for a file not registered";
					}
					cb(message.thumbnailPath);
					onReadyCallbacks.remove(message.originalPath);
				default:
					throw "Unknown message type " + message.type;
			}
		} catch(e) {
			hide.Ide.inst.quickError("Thumb Generator invalid message : " + e + "\n" + message);
		}
	}

	var queued = false;

	/**
		Asyncrhonusly generates a miniature.
		onReady is called back with the path of the loaded miniature, or null if the miniature couldn't be loaded
	**/
	public function renderMiniature(path: String, onReady: MiniatureReadyCallback) {
		if (retries >= maxRetries) {
			onReady(null);
			return;
		}
		var ext = path.split(".").pop().toLowerCase();
		switch(ext) {
			case "prefab" | "fbx" | "l3d" | "fx" | "shgraph" | "jpg" | "jpeg" | "png":
				if (!onReadyCallbacks.exists(path)) {
					onReadyCallbacks.set(path, onReady);
					sendGenerateCommand(path);
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
		var thumbnail = ThumbnailGenerator.getThumbPath(file.getPath());
		try {
			sys.FileSystem.deleteFile(thumbnail.toString());
		} catch (e) {};
		file.iconPath = null;
	}

	public function checkWindowReady() {
		if (serverSocket == null)
			return false;
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
		if (windowManager.state == Pending) {
			return false;
		}
		if (windowManager.state == Ready && generatorSocket != null) {
			return true;
		}
		return false;
	}

	public function clearRenderQueue() {
		onReadyCallbacks.clear();
		if (!checkWindowReady()) {
			return;
		}
		var message = {
			type: ManagerToGenCommand.clear,
		};
		var cmd = haxe.Json.stringify(message) + "\n";
		generatorSocket.out.writeString(cmd);
		pendingMessages = [];
	}

	public function setPriority(path: String, newPriority: Int) {
		if (!onReadyCallbacks.exists(path)) {
			return;
		}
		if (retries >= maxRetries)
			return;
		var message = {
			type: ManagerToGenCommand.prio,
			path: path,
			prio: newPriority
		};
		var cmd = haxe.Json.stringify(message) + "\n";
		pendingMessages.push(cmd);
		queueProcessPendingMessages();
	}

	function sendGenerateCommand(path: String) {
		if (!checkWindowReady()) {
			return;
		}
		var message = {
			type: ManagerToGenCommand.queue,
			path: path,
		};
		var cmd = haxe.Json.stringify(message) + "\n";
		pendingMessages.push(cmd);
		queueProcessPendingMessages();
	}
}


enum RenderWindowState {
	Pending;
	Ready;
}

@:allow(hide.tools.FileManager)
@:access(hide.tools.FileManager)
class RenderWindowManager {
	var state : RenderWindowState = Pending;
	var generatorWindow : nw.Window;

	function new() {
		state = Pending;
		// wait that the browser is idle before creating the rendering window, so
		// the generator socket is properly initialised
		untyped js.Browser.window.requestIdleCallback(() -> {
			state = Ready;
			nw.Window.open('app.html?thumbnail=true', cast {
					new_instance: true,
					show: false,
					title: "HideThumbnailGenerator"
				}, (win: nw.Window) -> {
					generatorWindow = win;
				win.on("close", () -> {
					hide.Tools.FileManager.cleanupGenerator();
				});
			});
		}, {timeout: 1000});
	}


}
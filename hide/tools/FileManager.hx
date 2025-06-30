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

@:access(hide.tools.FileManager)
@:allow(hide.tools.FileManager)
class FileEntry {
	public var name: String;
	public var children: Array<FileEntry>;
	public var kind: FileKind;
	public var parent: FileEntry;
	public var iconPath: String;

	var registeredWatcher : hide.tools.FileWatcher.FileWatchEvent = null;

	public function new(name: String, parent: FileEntry, kind: FileKind) {
		this.name = name;
		this.parent = parent;
		this.kind = kind;

		watch();
	}

	public function dispose() {
		if (children != null) {
			for (child in children) {
				child.dispose();
			}
		}
		children = null;
		if (registeredWatcher != null) {
			hide.Ide.inst.fileWatcher.unregister(this.getPath(), registeredWatcher.fun);
			registeredWatcher = null;
		}
	}

	function refreshChildren(rec: Bool) {
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
					children.push(
						new FileEntry(path, this, info.isDirectory() ? Dir : File)
					);
				}
			}
		}

		for (child in oldChildren) {
			child.dispose();
		}

		children.sort(compareFile);

		if (rec) {
			for (child in children) {
				child.refreshChildren(rec);
			}
		}
	}

	function watch() {
		if (registeredWatcher != null)
			throw "already watching";

		var rel = this.getRelPath();
		registeredWatcher = hide.Ide.inst.fileWatcher.register(rel, FileManager.inst.fileChangeInternal.bind(this), true);
	}

	public function getPath() {
		if (this.parent == null) return hide.Ide.inst.resourceDir;
		return this.parent.getPath() + "/" + this.name;
	}

	public function getRelPath() {
		if (this.parent == null) return "";
		if (this.parent.parent == null) return this.name;
		return this.parent.getRelPath() + "/" + this.name;
	}

	// sort directories before files, and then dirs and files alphabetically
	static public function compareFile(a: FileEntry, b: FileEntry) {
		if (a.kind != b.kind) {
			if (a.kind == Dir) {
				return -1;
			}
			return 1;
		}
		return Reflect.compare(a.name, b.name);
	}
}

typedef MiniatureReadyCallback = (miniaturePath: String) -> Void;

/**
	Class that handle parsing and maintaining the state of the project files, and generate miniatures for them on demand
**/
class FileManager {

	public var fileRoot: FileEntry;

	public static final thumbnailGeneratorPort = 9669;
	public static final thumbnailGeneratorUrl = "localhost";

	public static var inst(get, default) : FileManager;
	public var onFileChangeHandlers: Array<(entry: FileEntry) -> Void> = [];

	var windowManager : RenderWindowManager = null;

	var onReadyCallbacks : Map<String, MiniatureReadyCallback> = [];

	var serverSocket : hxd.net.Socket = null;
	var generatorSocket : hxd.net.Socket = null;
	var pendingMessages : Array<String> = [];

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

		setupServer();
		checkWindowReady();
		initFileSystem();
	}

	function initFileSystem() {
		fileEntryRefreshDelay = new Delayer((entry: FileEntry) -> {
			entry.refreshChildren(false);
		});

		fileRoot = new FileEntry("res", null, Dir);
		fileRoot.refreshChildren(true);
	}

	function fileChangeInternal(entry: FileEntry) {
		if (!js.node.Fs.existsSync(entry.getPath()) && entry.parent != null) {
			fileEntryRefreshDelay.queue(entry.parent);
			return;
		}
		if (entry.kind == Dir) {
			fileEntryRefreshDelay.queue(entry);
		}
		for (handler in onFileChangeHandlers) {
			handler(entry);
		}
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
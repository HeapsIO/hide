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

typedef FileData = {
	name: String,
	parent: FileData,
}

typedef MiniatureReadyCallback = (miniaturePath: String) -> Void;

/**
	Class that handle parsing and maintaining the state of the project files, and generate miniatures for them on demand
**/
class FileManager {

	public static final thumbnailGeneratorPort = 9669;
	public static final thumbnailGeneratorUrl = "localhost";

	public static var inst(get, default) : FileManager;

	var windowManager : RenderWindowManager = null;

	var onReadyCallbacks : Map<String, MiniatureReadyCallback> = [];

	var serverSocket : hxd.net.Socket = null;
	var generatorSocket : hxd.net.Socket = null;
	var pendingMessages : Array<String> = [];

	var retries = 0;
	static final maxRetries = 5;

	static function get_inst() {
		if (inst == null) {
			inst = new FileManager();
		}
		return inst;
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

	function new() {
		// kill server when page is reloaded
		js.Browser.window.addEventListener('beforeunload', () -> { cleanupGenerator(); cleanupServer(); });

		setupServer();
		checkWindowReady();
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
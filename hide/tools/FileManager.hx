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

	var generatorWindow : nw.Window;

	var onReadyCallbacks : Map<String, MiniatureReadyCallback> = [];

	var serverSocket : hxd.net.Socket = null;
	var generatorSocket : hxd.net.Socket = null;

	static function get_inst() {
		if (inst == null) {
			inst = new FileManager();
		}
		return inst;
	}

	public static function onBeforeReload() {
		if (inst != null) {
			inst.cleanupGenerator();
		}
	}

	var reloadQueued = false;

	function queueReload() {
		if (reloadQueued == false) {
			reloadQueued = true;
			haxe.Timer.delay(setupGenerator, 5000);
		}
	}

	function setupGenerator() {
		reloadQueued = false;
		serverSocket = new hxd.net.Socket();
		serverSocket.onError = (msg) -> {
			hide.Ide.inst.quickError("FileManager socket error : " + msg);
			cleanupGenerator();
			queueReload();
		}
		serverSocket.bind(thumbnailGeneratorUrl, thumbnailGeneratorPort, (remoteSocket) -> {
			if (generatorSocket != null) {
				generatorSocket.close();
			}
			generatorSocket = remoteSocket;
			generatorSocket.onError = (msg) -> {
				hide.Ide.inst.quickError("Generator socket error : " + msg);
				cleanupGenerator();
				queueReload();
			}

			var handler = new hide.tools.ThumbnailGenerator.MessageHandler(generatorSocket, processThumbnailGeneratorMessage);

			// resend command that weren't completed
			for (path => _ in onReadyCallbacks) {
				sendGenerateCommand(path);
			}
		});

		nw.Window.open('app.html?thumbnail=true', cast {
				new_instance: true,
				show: false,
				title: "HideThumbnailGenerator"
			}, (win: nw.Window) -> {
				generatorWindow = win;
			win.on("close", () -> {

				cleanupGenerator();
			});
		});
	}

	function cleanupGenerator() {
		if (generatorSocket != null) {
			generatorSocket.close();
			generatorSocket = null;
		}

		if (serverSocket != null) {
			serverSocket.close();
			serverSocket = null;
		}

		if (generatorWindow != null) {
			generatorWindow.close(true);
			generatorWindow = null;
		}
		untyped nw.Window.getAll((win:nw.Window) -> {
			if (win.title == "HideThumbnailGenerator") {
				win.close(true);
			}
		});
	}

	function new() {
		setupGenerator();
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

	public function clearRenderQueue() {
		onReadyCallbacks.clear();
		if (generatorSocket == null) {
			return;
		}
		var message = {
			type: ManagerToGenCommand.clear,
		};
		var cmd = haxe.Json.stringify(message) + "\n";
		generatorSocket.out.writeString(cmd);
	}

	public function setPriority(path: String, newPriority: Int) {
		if (!onReadyCallbacks.exists(path)) {
			return;
		}
		if (generatorSocket == null) {
			return;
		}
		var message = {
			type: ManagerToGenCommand.prio,
			path: path,
			prio: newPriority
		};
		var cmd = haxe.Json.stringify(message) + "\n";
		generatorSocket.out.writeString(cmd);
	}

	function sendGenerateCommand(path: String) {
		if (generatorSocket == null) {
			return;
		}
		var message = {
			type: ManagerToGenCommand.queue,
			path: path,
		};
		var cmd = haxe.Json.stringify(message) + "\n";
		generatorSocket.out.writeString(cmd);
	}


}
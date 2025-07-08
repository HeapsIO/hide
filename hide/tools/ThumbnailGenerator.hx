package hide.tools;

typedef RenderInfo = {path: String, cb: hide.tools.FileManager.MiniatureReadyCallback, priority: Int};

/**
	Handle recieving messages separated by `\n` characters by a socket, correctly buffering the data
**/
class MessageHandler {
	var socket: hxd.net.Socket;
	var bufferedData : haxe.io.Bytes;
	var bufferSize = 0;
	static final maxBufferSize = 16384;

	public function new(socket: hxd.net.Socket, callback: (content: String) -> Void) {
		this.socket = socket;
		bufferedData = haxe.io.Bytes.alloc(maxBufferSize);
		bufferSize = 0;

		socket.onData = () -> {
			while(socket.input.available > 0) {
				var read = hxd.Math.imin(maxBufferSize - bufferSize, socket.input.available);
				if (read == 0) {
					throw "message too long";
				}

				socket.input.readFullBytes(bufferedData, bufferSize, read);
				bufferSize += read;

				var last = 0;
				var pos = 0;

				// split on newLines
				while(pos < bufferSize) {
					if (bufferedData.get(pos) == 10) {
						var command = bufferedData.getString(last, pos-last);
						callback(command);
						last = pos+1;
					}
					pos ++;
				}

				if (last > 0) {
					var remaining = bufferSize - last;
					if (remaining > 0) {
						bufferedData.blit(0, bufferedData, last, remaining);
						bufferSize = remaining;
					} else {
						bufferSize = 0;
					}
				} else if (bufferSize == maxBufferSize) {
					throw "message too long";
				}
			}
		}
	}
}

@:access(hide.tools.FileManager)
class ThumbnailGenerator {
	var miniaturesToRender : Array<RenderInfo> = [];
	var prioDirty = false;
	var renderCanvas : hide.comp.Scene;
	var renderTexture : h3d.mat.Texture;
	final renderRes = 512;

	var sceneRoot : h3d.scene.Object;

	var socket : hxd.net.Socket = null;
	var ready : Bool = false;

	function sendSuccess(originalPath: String, finalPath: String) {
		var message = {
			type: hide.tools.FileManager.GenToManagerCommand.success,
			data: ({
				originalPath: originalPath,
				thumbnailPath: finalPath,
			}:hide.tools.FileManager.GenToManagerSuccessMessage)
		};
		var serialized = haxe.Json.stringify(message);
		socket.out.writeString(serialized + "\n");
	}

	var bufferedData : haxe.io.Bytes;
	var bufferSize = 0;
	static final maxBufferSize = 16384;

	function new() {
		if (Ide.inst.ideConfig.filebrowserDebugShowWindow) {
			nw.Window.get().show(true);
		} else {
			untyped nw.Window.get().hide();
		}
		nw.Window.get().resizeTo(128,128);

		bufferedData = haxe.io.Bytes.alloc(maxBufferSize);

		socket = new hxd.net.Socket();
		socket.timeout = 5000;

		// Destroy the generator if any error occurs
		socket.onError = (msg) -> {
			nw.Window.get().close(true);
		}

		var handler = new MessageHandler(socket, handleCommand);

		var cont = new Element('<div style="width: 512px; height: 512px; z-index: 10000; position: absolute; top:0; left: 0;"></div>').appendTo(js.Browser.document.body);
		renderCanvas = new hide.comp.Scene(hide.Ide.inst.currentConfig, cont, null);
		renderCanvas.enableNewErrorSystem = true;
		renderCanvas.errorHandler = (e) -> {
			// do nothing;
			return null;
		}
		renderCanvas.autoUpdate = false;
		renderCanvas.onReady = () -> {
			renderCanvas.engine.setCurrent();

			renderCanvas.s3d.removeChildren();
			renderCanvas.s2d.removeChildren();

			renderTexture = new h3d.mat.Texture(renderRes,renderRes, [Target]);

			sceneRoot = new h3d.scene.Object(renderCanvas.s3d);

			renderCanvas.errorHandler = (e) -> null;

			haxe.Timer.delay(() -> {
				this.ready = true;

				socket.connect(hide.tools.FileManager.thumbnailGeneratorUrl, hide.tools.FileManager.thumbnailGeneratorPort, () -> {
				});

			}, 1);
		};
	}

	function handleCommand(command: String) {
		var message : Dynamic = {};
		try {
			message = haxe.Json.parse(command);
		} catch (e) {
			return;
		}
		switch((message.type:FileManager.ManagerToGenCommand)) {
			case queue:
					renderMiniature(message.path, sendSuccess.bind(message.path));
			case clear:
				miniaturesToRender = [];
			case prio:
				var toSet = Lambda.find(miniaturesToRender, (m) -> m.path == message.path);
				if (toSet != null) {
					toSet.priority = message.prio;
					prioDirty = true;
				}
		}
	}

	var queued = false;

	/**
		Asynchronously generates a miniature.
		onReady is called back with the path of the loaded miniature, or null if the miniature couldn't be loaded
	**/
	public function renderMiniature(path: String, onReady: hide.tools.FileManager.MiniatureReadyCallback) {
		miniaturesToRender.push({path: path, cb: onReady, priority: 0});
		if (!queued) {
			haxe.Timer.delay(processMiniature, 1);
		}
	}

	public static final thumbRoot = ".tmp/";
	public static final thumbExt = "thumb.jpg";

	static public function getThumbPath(basePath: String) : haxe.io.Path {
		basePath = StringTools.replace(basePath, hide.Ide.inst.resourceDir, "");
		var path = new haxe.io.Path(haxe.io.Path.join([hide.Ide.inst.resourceDir, thumbRoot, basePath]));
		path.ext += "." + thumbExt;
		return path;
	}

	static function getRenderProps(filePath: String, config: Config) : String {
		var renderPropsPath = config.getLocal("thumbnail.renderProps");
		if (renderPropsPath == null) {
			var renderPropsList = hide.comp.ScenePreview.listRenderPropsStatic(config);
			if (renderPropsList.length > 0) {
				renderPropsPath =  renderPropsList[0].value;
			}
		}
		return renderPropsPath;
	}

	static function getThumbnailHash(filePath: String) : String {
		var config = Config.loadForFile(Ide.inst, filePath);
		var toHash = "";
		toHash += getRenderProps(filePath, config);
		toHash += sys.FileSystem.stat(filePath).mtime.getTime();
		return haxe.crypto.Md5.encode(toHash);
	}

	function handleModel(toRender: RenderInfo) {
		renderCanvas.engine.setCurrent();

		renderCanvas.s3d.removeChildren();

		var config = Config.loadForFile(Ide.inst, toRender.path);
		var renderPropsPath = getRenderProps(toRender.path, config);

		if (renderPropsPath != null)
			renderCanvas.setRenderProps(renderPropsPath);

		sceneRoot = new h3d.scene.Object(renderCanvas.s3d);

		var engine = renderCanvas.engine;

		var ctx = new hide.prefab.ContextShared(null, sceneRoot);
		ctx.scene = renderCanvas;

		var ext = toRender.path.split(".").pop().toLowerCase();

		var abort = false;
		if (ext == "fbx") {
			var model = new hrt.prefab.Model(null, null);
			model.source = toRender.path;
			model.make(ctx);
		} else if (ext == "prefab" || ext == "l3d" || ext == "fx") {
			try {
				var cut = StringTools.replace(toRender.path, hide.Ide.inst.resourceDir + "/", "");
				var prefab = hxd.res.Loader.currentInstance.load(cut).toPrefab().loadBypassCache();

				var prefab = prefab.make(ctx);

				if (ext == "fx") {
					var fx = prefab.find(hrt.prefab.fx.FX, true, false);
					if (fx != null) {
						var fxAnim = Std.downcast(fx.local3d, hrt.prefab.fx.FX.FXAnimation);
						// Forward the animations a little bit to show something more usefull
						if (fxAnim != null) {
							var duration = fxAnim.duration;
							fxAnim.setTime(duration * 0.25);
						}
					}
				}

			} catch (e) {
				hide.Ide.inst.quickError('miniature render fail for ${toRender.path} : $e');
				abort = true;
			}
		} else if (ext == "shgraph") {
			try {
				var spherePrim = new h3d.prim.Sphere(1.0, 32, 32, 1);
				spherePrim.addNormals();
				spherePrim.addUVs();
				spherePrim.addTangents();

				var sphere = new h3d.scene.Mesh(spherePrim, sceneRoot);

				var shgraph = new hrt.prefab.DynamicShader(null, null);
				var cut = StringTools.replace(toRender.path, hide.Ide.inst.resourceDir + "/", "");
				shgraph.source = cut;
				ctx = new hide.prefab.ContextShared(null, sphere);
				shgraph.makeShader();
				for (m in sphere.getMaterials()) {
					@:privateAccess shgraph.applyShader(sphere, m, shgraph.shader);
				}
			} catch(e) {
				hide.Ide.inst.quickError('miniature render fail for ${toRender.path} : $e');
				abort = true;
			}
		}
		if (!abort) {
			try {
				renderCanvas.s3d.camera.setFovX(25, 1.0);
				var downscale = 1.0;
				// FX have usually large bounds. Scale them down
				var fx = sceneRoot.find((f) -> Std.downcast(f, hrt.prefab.fx.FX.FXAnimation));
				if (fx != null)
					downscale = 0.5;
				renderCanvas.resetCamera2(sceneRoot, downscale, 1000.0);

				renderTexture.clear(0,0);

				@:privateAccess renderCanvas.doSync();

				engine.pushTarget(renderTexture);
				engine.clear();
				renderCanvas.s3d.render(engine);
				engine.popTarget();

				renderCanvas.s3d.removeChildren();
				renderCanvas.s2d.removeChildren();

				var path = convertAndWriteThumbnail(toRender.path, renderTexture);
				toRender.cb(path);
			}
			catch (e) {
				toRender.cb(null);
			}
		} else {
			toRender.cb(null);
		}
	}

	function convertAndWriteThumbnail(basePath: String, texture: h3d.mat.Texture) {
		var path = getThumbPath(basePath).toString();
		path = StringTools.replace(path, "\\", "/");

		var dir = path.split("/");
		dir.pop();
		var dirPath = dir.join("/") + "/";
		if(!sys.FileSystem.isDirectory( hide.Ide.inst.getPath(dirPath)))
			sys.FileSystem.createDirectory( hide.Ide.inst.getPath(dirPath));

		var pixels = texture.capturePixels();
		pixels.convert(ARGB);
		//sys.io.File.saveBytes(path, renderTexture.capturePixels().toPNG());
		var bytes = new haxe.io.BytesOutput();
		var writer = new format.jpg.Writer(bytes);
		writer.write({
			width: texture.width,
			height: texture.height,
			pixels: pixels.bytes,
			quality: 50
		});

		sys.io.File.saveBytes(path, bytes.getBytes());
		sys.io.File.saveContent(path + ".meta", getThumbnailHash(basePath));
		return path;
	}

	function handleTexture(toRender: RenderInfo) {
		renderCanvas.engine.setCurrent();

		try {
			var cut = StringTools.replace(toRender.path, hide.Ide.inst.resourceDir + "/", "");
			var img = hxd.res.Loader.currentInstance.load(cut).toTexture();
			var width = img.width;
			var height = img.height;

			final size = 512;

			if (width > height) {
				height = hxd.Math.floor(height / width * size);
				width = size;
			} else if (width < height) {
				width = hxd.Math.floor(width / height * size);
				height = size;
			} else {
				width = size;
				height = size;
			}

			renderCanvas.s2d.removeChildren();

			var bg = new h2d.Bitmap(h2d.Tile.fromColor(0), renderCanvas.s2d);
			bg.width = size;
			bg.height = size;

			var bmp = new h2d.Bitmap(h2d.Tile.fromTexture(img), renderCanvas.s2d);
			bmp.width = width;
			bmp.height = height;
			bmp.x = (size - width) / 2;
			bmp.y = (size - height) / 2;

			bmp.blendMode = None;

			var shader = new hide.view.GraphEditor.PreviewShaderAlpha();
			bmp.addShader(shader);

			var engine = renderCanvas.engine;

			engine.pushTarget(renderTexture);
			engine.clear();
			renderCanvas.render(engine);
			engine.popTarget();

			var path = convertAndWriteThumbnail(toRender.path, renderTexture);

			// restore renderTexture original size
			renderTexture.resize(512, 512);

			toRender.cb(path);
		} catch (e) {
			toRender.cb(null);
		}

		renderCanvas.s2d.removeChildren();

	}

	function processMiniature() {
		if (!ready || renderCanvas.s3d == null) {
			haxe.Timer.delay(processMiniature, 1);
			return;
		}

		queued = false;


		var startTime = haxe.Timer.stamp();

		// timeslice at 30 FPS
		while(haxe.Timer.stamp() - startTime < 0.33) {

			if (miniaturesToRender.length == 0) {
				return;
			}

			if (prioDirty) {
				miniaturesToRender.sort((a, b) -> Reflect.compare(a.priority, b.priority));
				prioDirty = false;
			}

			var toRender = miniaturesToRender.pop();

			// Check thumbnail cache
			var thumbPath = getThumbPath(toRender.path).toString();
			var metaPath = thumbPath + ".meta";
			var shouldGenerate = true;
			if (!Ide.inst.ideConfig.filebrowserDebugIgnoreThumbnailCache && sys.FileSystem.exists(thumbPath) && sys.FileSystem.exists(metaPath)) {
				var savedHash = sys.io.File.getContent(metaPath);
				var hash = getThumbnailHash(toRender.path);
				if (hash == savedHash) {
					shouldGenerate = false;
					sendSuccess(toRender.path, thumbPath);
					continue;
				}
			}

			var ext = toRender.path.split(".").pop().toLowerCase();
			switch(ext) {
				case "prefab" | "fbx" | "l3d" | "fx" | "shgraph":
					handleModel(toRender);
				case "jpg" | "jpeg" | "png":
					handleTexture(toRender);
				default:
					toRender.cb(null);
			}
		}

		if (miniaturesToRender.length > 0) {
			haxe.Timer.delay(processMiniature, 1);
		}
	}
}
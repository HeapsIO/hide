package hide;

class ThumbnailGeneratorApp extends hxd.App {

	var generator : ThumbnailGenerator;

	public static function tryStart() : Bool {
		var args = Sys.args();
		if(args[0] != "--thumbnail")
			return false;

		hl.UI.closeConsole();

		hxd.System.createWindow = () -> {
			new hxd.Window("HideHL - Thumbnail Generator", 256,256,{fixed: true, hidden: true});
		}

		hxd.Res.initLocal();
		hrt.ui.HuiRes.init();

		new ThumbnailGeneratorApp(args[1]);
		return true;
	}

	function new(path: String) {
		super();
		var ide = new hide.Ide();
		ide.isThumbnailMode = true;
		ide.readOnlyConfig = true;
		@:privateAccess ide.setProject(path);
	}

	override function init() {
		super.init();

		generator = @:privateAccess new ThumbnailGenerator();
	}

	override function update(dt: Float) {
		super.update(dt);
	}
}


typedef RenderInfo = {path: String, cb: hrt.tools.FileManager.MiniatureReadyCallback, priority: Int};
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

@:access(hrt.tools.FileManager)
class ThumbnailGenerator {
	var miniaturesToRender : Array<RenderInfo> = [];
	var prioDirty = false;
	var renderTexture : h3d.mat.Texture;
	static final renderRes = 512;
	var jpegWriter: format.jpg.Writer;

	var s2d: h2d.Scene;

	var s3d: h3d.scene.Scene;
	var waitingAsyncLoad = false;

	var sceneRoot : h3d.scene.Object;

	var socket : hxd.net.Socket = null;

	function sendSuccess(originalPath: String, finalPath: String) {
		var message = {
			type: hrt.tools.FileManager.GenToManagerCommand.success,
			data: ({
				originalPath: originalPath,
				thumbnailPath: finalPath,
			}:hrt.tools.FileManager.GenToManagerSuccessMessage)
		};
		var serialized = haxe.Json.stringify(message);
		socket.out.writeString(serialized + "\n");
	}

	var bufferedData : haxe.io.Bytes;
	var bufferSize = 0;
	static final maxBufferSize = 16384;

	function new() {
		/*if (Ide.inst.ideConfig.filebrowserDebugShowWindow) {
			nw.Window.get().show(true);
		} else {
			untyped nw.Window.get().hide();
		}
		nw.Window.get().resizeTo(128,128);*/

		if (Ide.inst.ideConfig.filebrowserDebugServerCommands)
			trace("verbose output enabled");
		else
			trace("no verbose output");

		bufferedData = haxe.io.Bytes.alloc(maxBufferSize);

		socket = new hxd.net.Socket();
		socket.timeout = 5000;

		// Destroy the generator if any error occurs
		socket.onError = (msg) -> {
			trace('Error: $msg. Closing generator');
			hxd.Window.getInstance().close();
		}

		renderTexture = new h3d.mat.Texture(renderRes,renderRes, [Target]);

		new h2d.Bitmap(h2d.Tile.fromTexture(renderTexture), s2d);

		resetScene();


		socket.connect(hrt.tools.FileManager.thumbnailGeneratorUrl, hrt.tools.FileManager.thumbnailGeneratorPort, () -> {
			trace("Connected to main Hide");

			var handler = new MessageHandler(socket, handleCommand);
		});

		jpegWriter = new format.jpg.Writer(null);
	}

	function handleCommand(command: String) {
		var message : Dynamic = {};
		try {
			message = haxe.Json.parse(command);
		} catch (e) {
			return;
		}
		switch((message.type:hrt.tools.FileManager.ManagerToGenCommand)) {
			case queue:
				if (Ide.inst.ideConfig.filebrowserDebugServerCommands)
					trace('queue ${message.path}');
				renderMiniature(message.path, sendSuccess.bind(message.path));
			case clear:
				if (Ide.inst.ideConfig.filebrowserDebugServerCommands)
					trace('clear');
				miniaturesToRender = [];
			case prio:
				if (Ide.inst.ideConfig.filebrowserDebugServerCommands)
					trace('prio ${message.path} ->  ${message.prio}');
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
	public function renderMiniature(path: String, onReady: hrt.tools.FileManager.MiniatureReadyCallback) {
		miniaturesToRender.push({path: path, cb: onReady, priority: 0});
		if (!queued) {
			haxe.Timer.delay(processMiniature, 1);
		}
	}

	public static final thumbRoot = ".tmp/";
	public static final thumbExt = "jpg";

	static function getThumbnailPath(basePath: String) : haxe.io.Path {
		var hash = getThumbnailHash(basePath);
		basePath = StringTools.replace(basePath, hide.Ide.inst.resourceDir, "");
		var path = new haxe.io.Path(haxe.io.Path.join([hide.Ide.inst.resourceDir, thumbRoot, basePath]));
		path.file += "." + path.ext + "_thumb_" + hash;
		path.ext = thumbExt;
		return path;
	}

	static function getRenderProps(filePath: String, config: Config) : String {
		// var renderPropsPath = config.getLocal("thumbnail.renderProps");
		// if (renderPropsPath == null) {
		// 	var renderPropsList = hide.comp.ScenePreview.listRenderPropsStatic(config);
		// 	if (renderPropsList.length > 0) {
		// 		renderPropsPath =  renderPropsList[0].value;
		// 	}
		// }
		// return renderPropsPath;
		return "";
	}

	static function getThumbnailHash(filePath: String) : String {
		var config = Config.loadForFile(Ide.inst, filePath);
		var toHash = "";
		toHash += getRenderProps(filePath, config);
		toHash += sys.FileSystem.stat(filePath).mtime.getTime();
		if (filePath.split(".").pop().toLowerCase() == "fbx") {
			var matInfo = try getMaterialInfo(filePath) catch(e) "__error__";
			toHash += matInfo;
		}
		return haxe.crypto.Md5.encode(toHash);
	}

	static function getMaterialInfo(filePath: String) : String {
		var string = "";

		var dir = filePath.split("/");
		dir.pop();
		dir.push("materials.props");

		var materialsPropsPath = dir.join("/");
		if (sys.FileSystem.exists(materialsPropsPath)) {
			string += sys.FileSystem.stat(materialsPropsPath).mtime.getTime();
		}

		var model = hxd.res.Loader.currentInstance.load(Ide.inst.getRelPath(filePath)).toModel();
		var hmd = model.toHmd();

		var libTimes : Map<String, Float> = [];
		for (materialDef in hmd.header.materials) {
			var mat = h3d.mat.MaterialSetup.current.createMaterial();
			mat.name = materialDef.name;
			mat.model = model;
			mat.blendMode = materialDef.blendMode;
			var props = h3d.mat.MaterialSetup.current.loadMaterialProps(mat);
			var ref = props != null ? (props:Dynamic).__ref : null;
			if (ref != null) {
				var refPath = Ide.inst.getPath(ref);
				if (sys.FileSystem.exists(refPath))
					string += hrt.tools.MapUtils.getOrPut(libTimes, ref, sys.FileSystem.stat(refPath).mtime.getTime());
			}
		}

		return string;
	}

	function handleModel(toRender: RenderInfo, thumbnailPath: String) {
		s3d.removeChildren();
		s2d.removeChildren();

		var config = Config.loadForFile(Ide.inst, toRender.path);
		var renderPropsPath = getRenderProps(toRender.path, config);

		/*if (renderPropsPath != null)
			renderCanvas.setRenderProps(renderPropsPath);*/

		sceneRoot = new h3d.scene.Object(s3d);

		var engine = h3d.Engine.getCurrent();

		var ctx = new hrt.prefab.ContextShared(null, sceneRoot);

		var ext = toRender.path.split(".").pop().toLowerCase();

		var abort = false;
		var cut = StringTools.replace(toRender.path, hide.Ide.inst.resourceDir + "/", "");

		if (ext == "fbx") {
			try {
				var model = new hrt.prefab.Model(null, null);
				model.source = cut;
				model.make(ctx);
			} catch(e) {
				trace('miniature render fail for ${toRender.path} : $e');
				abort = true;
			}
		} else if (ext == "prefab" || ext == "l3d" || ext == "fx") {
			try {
				var prefab = hxd.res.Loader.currentInstance.load(cut).toPrefab().loadBypassCache();

				// Remove all editor only prefabs
				var toRemove = prefab.findAll(hrt.prefab.Prefab, (p) -> p.editorOnly == true, true);
				for (r in toRemove) {
					r.remove();
				}

				var prefab = prefab.make(ctx);

				if (ext == "fx") {
					var fx = prefab.find(hrt.prefab.fx.FX, true, false);
					if (fx != null) {
						var fxAnim = Std.downcast(fx.local3d, hrt.prefab.fx.FX.FXAnimation);
						// Forward the animations a little bit to show something more usefull
						if (fxAnim != null) {
							var duration = fxAnim.duration;
							fxAnim.seek(duration * 0.25);
						}
					}
				}

			} catch (e) {
				trace('miniature render fail for ${toRender.path} : $e');
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
				ctx = new hrt.prefab.ContextShared(null, sphere);
				shgraph.makeShader();
				for (m in sphere.getMaterials()) {
					@:privateAccess shgraph.applyShader(sphere, m, shgraph.shader);
				}
			} catch(e) {
				trace('miniature render fail for ${toRender.path} : $e');
				abort = true;
			}
		}
		if (!abort) {
			try {
				s3d.camera.setFovX(25, 1.0);
				var downscale = 1.0;
				// FX have usually large bounds. Scale them down
				var fx = sceneRoot.find((f) -> Std.downcast(f, hrt.prefab.fx.FX.FXAnimation));
				if (fx != null)
					downscale = 0.5;
				//renderCanvas.resetCamera2(sceneRoot, downscale, 1000.0);

				resetCam(sceneRoot);

				renderTexture.clear(0,0);

				s2d.setElapsedTime(0);
				s3d.setElapsedTime(0);

				engine.pushTarget(renderTexture);
				engine.clear();
				s3d.render(engine);
				engine.popTarget();

				s3d.removeChildren();
				s2d.removeChildren();

				var path = convertAndWriteThumbnail(toRender.path, thumbnailPath, renderTexture);
				toRender.cb(path);
			}
			catch (e) {
				trace('miniature render fail for ${toRender.path} : $e');
				abort = true;
			}
		}

		if (abort) {
			resetScene();
			toRender.cb(null);
		}
	}

	function resetCam(root: h3d.scene.Object) {
		var bnds = new h3d.col.Bounds();

		var objs = root.findAll((f) -> f);
		for(obj in objs) {
			bnds.add(obj.getBounds());
		}

		// var dbg = bnds.makeDebugObj();
		// root.addChild(dbg);
		var centroid = bnds.getCenter();

		var dist = 1.0;
		if (!bnds.isEmpty()) {
			var s = bnds.toSphere();
			dist = s.r * 4.5;
		}

		var tetha = 66.0 / 180.0 * hxd.Math.PI;
		var rho = 45.0 / 180.0 * hxd.Math.PI;

		var x = dist * hxd.Math.sin(tetha) * hxd.Math.cos(rho);
		var y = dist * hxd.Math.sin(tetha) * hxd.Math.sin(rho);
		var z = dist * hxd.Math.cos(tetha);

		s3d.camera.pos.set(x + centroid.x,y + centroid.y, z + centroid.z);
		s3d.camera.target.load(centroid);
		s3d.camera.update();
	}

	function resetScene() {
		s2d?.dispose();
		s3d?.dispose();

		s2d = new h2d.Scene();
		s3d = new h3d.scene.Scene();
	}

	function convertAndWriteThumbnail(basePath: String, thumbnailPath: String, texture: h3d.mat.Texture) {
		var path = thumbnailPath;
		path = StringTools.replace(path, "\\", "/");

		var dir = path.split("/");
		dir.pop();
		var dirPath = dir.join("/") + "/";
		if(!sys.FileSystem.isDirectory( hide.Ide.inst.getPath(dirPath)))
			sys.FileSystem.createDirectory( hide.Ide.inst.getPath(dirPath));

		var pixels = texture.capturePixels();
		//sys.io.File.saveBytes(path, renderTexture.capturePixels().toPNG());

		var len : Int = 0;
		var bytes = format.hl.Native.encodeJPG(pixels.bytes, texture.width, texture.height, texture.width * 4, RGBA, _422, 85, 0, hl.Ref.make(len));
		if (bytes == null)
			throw "Convert failed";

		sys.io.File.saveBytes(path, bytes.toBytes(len));

		return path;
	}

	function handleTexture(toRender: RenderInfo, thumbnailPath: String) {
		if (Ide.inst.ideConfig.filebrowserDebugServerCommands)
			trace('handleTexture ${toRender.path}');

		try {
			var cut = StringTools.replace(toRender.path, hide.Ide.inst.resourceDir + "/", "");
			var img = hxd.res.Loader.currentInstance.load(cut).toTexture();

			waitingAsyncLoad = true;
			img.waitLoad(() -> {
				try {
					if (Ide.inst.ideConfig.filebrowserDebugServerCommands)
						trace('handleTexture waitLoad finished (${toRender.path})');

					waitingAsyncLoad = false;
					var width = img.width;
					var height = img.height;

					final size = 512;
					s2d.scaleMode = Custom(size, size, 1, 1);

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

					s3d.removeChildren();
					s2d.removeChildren();

					var bg = new h2d.Bitmap(h2d.Tile.fromColor(0), s2d);
					bg.width = size;
					bg.height = size;

					var bmp = new h2d.Bitmap(h2d.Tile.fromTexture(img), s2d);
					bmp.width = width;
					bmp.height = height;
					bmp.x = 0;/*(size - width) / 2;*/
					bmp.y = 0;/*(size - height) / 2;*/

					bmp.blendMode = None;

					var shader = new hrt.shader.PreviewShaderAlpha();
					bmp.addShader(shader);

					var engine = h3d.Engine.getCurrent();

					renderTexture.clear(0,1.0);

					engine.pushTarget(renderTexture);
					engine.clear(0);
					s2d.render(engine);
					engine.popTarget();

					var path = convertAndWriteThumbnail(toRender.path, thumbnailPath, renderTexture);

					toRender.cb(path);

					if (Ide.inst.ideConfig.filebrowserDebugServerCommands)
						trace('handleTexture DONE (${toRender.path})');
				} catch (e) {
					waitingAsyncLoad = false;
					resetScene();
					toRender.cb(null);
					trace('handleTexture ERR : $e (${toRender.path})');
				}
			});
		} catch (e) {
			waitingAsyncLoad = false;
			toRender.cb(null);
			resetScene();
			trace('handleTexture ERR : $e (${toRender.path})');
		}

		//renderCanvas.s2d.removeChildren();
	}

	function processMiniature() {
		if (waitingAsyncLoad) {
			haxe.Timer.delay(processMiniature, 1);
			return;
		}

		if (miniaturesToRender.length == 0) {
			return;
		}

		queued = false;


		var startTime = haxe.Timer.stamp();

		// timeslice at 30 FPS
		while(haxe.Timer.stamp() - startTime < 0.5) {
			var benchstart = haxe.Timer.stamp();

			if (miniaturesToRender.length == 0) {
				return;
			}

			if (prioDirty) {
				miniaturesToRender.sort((a, b) -> Reflect.compare(a.priority, b.priority));
				prioDirty = false;
			}

			var toRender = miniaturesToRender.pop();

			// Check thumbnail cache

			var thumbnailPath = try getThumbnailPath(toRender.path) catch(e) null;
			if (thumbnailPath == null) {
				toRender.cb(null);
				continue;
			}
			var thumbnailPathString = thumbnailPath.toString();

			var shouldGenerate = true;
			if (!Ide.inst.ideConfig.filebrowserDebugIgnoreThumbnailCache && sys.FileSystem.exists(thumbnailPathString)) {
				shouldGenerate = false;
				sendSuccess(toRender.path, thumbnailPathString);
				continue;
			} else {
				// remove previous thumbnails for this file
				try {
					var filesDir = sys.FileSystem.readDirectory(thumbnailPath.dir);
					var commonPart = toRender.path.split("/").pop() + "_thumb_";

					for (file in filesDir) {
						if (StringTools.startsWith(file, commonPart)) {
							sys.FileSystem.deleteFile(thumbnailPath.dir + "/" + file);
						}
					}
				} catch(e) {

				}
			}

			var ext = toRender.path.split(".").pop().toLowerCase();
			switch(ext) {
				case "prefab" | "fbx" | "l3d" | "fx" | "shgraph":
					handleModel(toRender, thumbnailPathString);
				case "png" | "dds" | "jpg" | "jpeg":
					handleTexture(toRender, thumbnailPathString);
				default:
					toRender.cb(null);
			}
			var benchend = haxe.Timer.stamp();

			trace('rendered ${toRender.path} in ${(benchend - benchstart) * 1000.0}ms');

			if (waitingAsyncLoad) {
				break;
			}
		}

		if (miniaturesToRender.length > 0 || waitingAsyncLoad) {
			haxe.Timer.delay(processMiniature, 1);
		}
	}
}
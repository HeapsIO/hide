package hide.comp;

@:access(hide.comp.Scene)
class SceneLoader extends h3d.impl.Serializable.SceneSerializer {

	var ide : hide.ui.Ide;
	var scnPath : String;
	var projectPath : String;
	var scene : Scene;
	var shaderPath : Array<String>;
	var shaderCache = new Map<String, hxsl.SharedShader>();

	public function new(scnPath, scene) {
		ide = hide.ui.Ide.inst;
		super();
		this.scnPath = scnPath;
		this.scene = scene;
		shaderPath = ide.currentProps.get("haxe.classPath");
	}

	override function initSCNPaths(resPath:String, projectPath:String) {
		this.resPath = resPath.split("\\").join("/");
		this.projectPath = projectPath == null ? null : projectPath.split("\\").join("/");
	}

	override function loadShader(name:String) : hxsl.Shader {
		var s = loadSharedShader(name);
		if( s == null )
			return null;
		return new hxsl.DynamicShader(s);
	}

	function loadSharedShader( name : String ) {
		var s = shaderCache.get(name);
		if( s != null )
			return s;
		var e = loadShaderExpr(name);
		if( e == null )
			return null;
		var chk = new hxsl.Checker();
		chk.loadShader = function(iname) {
			var e = loadShaderExpr(iname);
			if( e == null )
				throw "Could not @:import " + iname + " (referenced from " + name+")";
			return e;
		};
		var s = new hxsl.SharedShader("");
		s.data = chk.check(name, e);
		@:privateAccess s.initialize();
		shaderCache.set(name, s);
		return s;
	}

	function loadShaderExpr( name : String ) : hxsl.Ast.Expr {
		var path = name.split(".").join("/")+".hx";
		for( s in shaderPath ) {
			var file = ide.projectDir + "/" + s + "/" + path;
			if( sys.FileSystem.exists(file) )
				return loadShaderString(file,sys.io.File.getContent(file));
		}
		if( StringTools.startsWith(name,"h3d.shader.") ) {
			var r = haxe.Resource.getString("shader/" + name.substr(11));
			if( r != null ) return loadShaderString(path, r);
		}
		return null;
	}

	function loadShaderString( file : String, content : String ) {
		var r = ~/var[ \t]+SRC[ \t]+=[ \t]+\{/;
		if( !r.match(content) )
			throw file+" does not contain shader SRC";
		var src = r.matchedRight();
		var count = 1;
		var pos = 0;
		while( pos < src.length ) {
			switch( src.charCodeAt(pos++) ) {
			case '{'.code: count++;
			case '}'.code: count--; if( count == 0 ) break;
			default:
			}
		}
		src = src.substr(0, pos - 1);
		var parser = new hscript.Parser();
		parser.allowTypes = true;
		parser.allowMetadata = true;
		parser.line = r.matchedLeft().split("\n").length;
		var e = parser.parseString(src, file);
		var e = new hscript.Macro({ min : 0, max : 0, file : file }).convert(e);
		return new hxsl.MacroParser().parseExpr(e);
	}

	override function loadHMD(path:String) {
		var path = resolvePath(path);
		if( path == null )
			throw "Missing HMD file " + path;
		return scene.loadHMD(path, false);
	}

	override function resolveTexture(path:String) {
		var path = resolvePath(path);
		if( path == null )
			return h3d.mat.Texture.fromColor(0xFF00FF);
		return scene.loadTexture(scnPath, path);
	}

	function resolvePath( path : String ) {
		var p = null;
		if( projectPath != null )
			p = scene.resolvePath(projectPath + resPath + "/" + scnPath.split("/").pop(), path);
		if( p == null )
			p = scene.resolvePath(scnPath, path);
		return p;
	}

}

class Scene extends Component implements h3d.IDrawable {

	static var UID = 0;

	var id = ++UID;
	var stage : hxd.Stage;
	var canvas : js.html.CanvasElement;
	var hmdCache = new Map<String, hxd.fmt.hmd.Library>();
	var texCache = new Map<String, h3d.mat.Texture>();
	var cleanup = new Array<Void->Void>();
	public var engine : h3d.Engine;
	public var width(get, never) : Int;
	public var height(get, never) : Int;
	public var s2d : h2d.Scene;
	public var s3d : h3d.scene.Scene;
	public var sevents : hxd.SceneEvents;

	public function new(root) {
		super(root);
		root.addClass("hide-scene-container");
		canvas = cast new Element("<canvas class='hide-scene' style='width:100%;height:100%'/>").appendTo(root)[0];
		canvas.addEventListener("mousemove",function(_) canvas.focus());
		canvas.addEventListener("mouseleave",function(_) canvas.blur());
		canvas.oncontextmenu = function(e){
			e.stopPropagation();
			e.preventDefault();
			return false;
		};
		untyped canvas.__scene = this;
		haxe.Timer.delay(delayedInit,0); // wait canvas added to window
	}

	public function dispose() {
		for( c in cleanup )
			c();
		cleanup = [];
		engine.dispose();
	}

	function delayedInit() {
		canvas.id = "webgl";
		stage = @:privateAccess new hxd.Stage(canvas);
		stage.setCurrent();
		engine = new h3d.Engine();
		engine.backgroundColor = 0xFF111111;
		canvas.id = null;
		engine.onReady = function() {
			new Element(canvas).on("resize", function() {
				@:privateAccess stage.checkResize();
			});
			engine.setCurrent();
			stage.setCurrent();
			s2d = new h2d.Scene();
			s3d = new h3d.scene.Scene();
			sevents = new hxd.SceneEvents(stage);
			sevents.addScene(s2d);
			sevents.addScene(s3d);
			onReady();
			onResize();
			sync();
			ide.registerUpdate(sync);
		};
		engine.onResized = function() {
			if( s2d == null ) return;
			s2d.setFixedSize(engine.width, engine.height);
			onResize();
		};
		engine.init();
	}

	function get_width() {
		return engine.width;
	}

	function get_height() {
		return engine.height;
	}

	public function init( props : hide.ui.Props, ?root : h3d.scene.Object ) {
		var autoHide : Array<String> = props.get("scene.autoHide");
		function initRec( obj : h3d.scene.Object ) {
			if( autoHide.indexOf(obj.name) >= 0 )
				obj.visible = false;
			for( o in obj )
				initRec(o);
		}
		if( root == null ) {
			root = s3d;
			engine.backgroundColor = Std.parseInt("0x"+props.get("scene.backgroundColor").substr(1)) | 0xFF000000;
		}
		initRec(root);
	}

	function setCurrent() {
		engine.setCurrent();
		stage.setCurrent();
	}

	function sync() {
		if( new Element(canvas).parents("html").length == 0 ) {
			stage.dispose();
			ide.unregisterUpdate(sync);
			return;
		}
		setCurrent();
		sevents.checkEvents();
		onUpdate(hxd.Timer.tmod);
		engine.render(this);
	}

	function loadTextureData( path : String, onReady : h3d.mat.Texture -> Void, ?target : h3d.mat.Texture ) {
		var path = ide.getPath(path);
		var img = new Element('<img src="file://$path"/>');
		img.on("load", function() {
			setCurrent();
			var bmp : js.html.ImageElement = cast img[0];
			var t;
			if( target == null )
				t = target = new h3d.mat.Texture(bmp.width, bmp.height);
			else {
				t = target;
				target.resize(bmp.width, bmp.height);
			}
			untyped bmp.ctx = { getImageData : function(_) return bmp, canvas : { width : 0, height : 0 } };
			engine.driver.uploadTextureBitmap(t, cast bmp, 0, 0);
			if( onReady != null ) {
				onReady(t);
				onReady = null;
			}
		});
		var w = js.node.Fs.watch(path, function(_, _) {
			img.attr("src", 'file://$path?t='+Date.now().getTime());
		});
		cleanup.push(w.close);
	}

	public function listAnims( path : String ) {
		var props = hide.ui.Props.loadForFile(ide, path);

		var dirs : Array<String> = props.get("hmd.animPaths");
		if( dirs == null ) dirs = [];
		dirs = [for( d in dirs ) ide.resourceDir + d];

		var parts = path.split("/");
		parts.pop();
		dirs.unshift(ide.getPath(parts.join("/")));

		var anims = [];

		var lib = loadHMD(path, false);
		if( lib.header.animations.length > 0 )
			anims.push(ide.getPath(path));

		for( dir in dirs )
			for( f in try sys.FileSystem.readDirectory(dir) catch( e : Dynamic ) [] )
				if( StringTools.startsWith(f,"Anim_") )
					anims.push(dir+"/"+f);
		return anims;
	}

	public function animationName( path : String ) {
		var name = path.split("/").pop();
		if( StringTools.startsWith(name, "Anim_") )
			name = name.substr(5);
		return name.substr(0, -4);
	}

	function initMaterials( obj : h3d.scene.Object, path : String ) {
		var res = hxd.res.Any.fromBytes(path, haxe.io.Bytes.alloc(0));
		for( m in obj.getMaterials() ) {
			if( m.name == null ) continue;
			m.model = res;
			h3d.mat.MaterialSetup.current.initModelMaterial(m);
		}
	}

	function loadSCN( path : String ) {
		var ctx = new SceneLoader(path,this);
		var fullPath = ide.getPath(path);
		var bytes = sys.io.File.getBytes(fullPath);
		var root = new h3d.scene.Object();
		for( o in ctx.loadSCN(bytes).content )
			root.addChild(o);
		initMaterials(root, path);
		return root;
	}

	public function loadModel( path : String ) {
		if( StringTools.endsWith(path.toLowerCase(), ".scn") )
			return loadSCN(path);
		var lib = loadHMD(path,false);
		var obj = lib.makeObject(loadTexture.bind(path));
		initMaterials(obj, path);
		return obj;
	}

	public function loadAnimation( path : String ) {
		var lib = loadHMD(path,true);
		return lib.loadAnimation();
	}

	function resolvePath( modelPath : String, filePath : String ) {
		inline function exists(path) return sys.FileSystem.exists(path);
		var fullPath = ide.getPath(filePath);
		if( exists(fullPath) )
			return fullPath;

		// swap drive letter
		if( fullPath.charAt(1) == ":" && fullPath.charAt(0) != ide.projectDir.charAt(0) ) {
			fullPath = ide.projectDir.charAt(0) + fullPath.substr(1);
			if( exists(fullPath) )
				return fullPath;
		}

		filePath = filePath.split("\\").join("/");
		modelPath = ide.getPath(modelPath);

		var path = modelPath.split("/");
		path.pop();
		var relToModel = path.join("/") + "/" + filePath.split("/").pop();
		if( exists(relToModel) )
			return relToModel;

		return null;
	}

	public function loadTexture( modelPath : String, texturePath : String, ?onReady : h3d.mat.Texture -> Void ) {
		var path = resolvePath(modelPath, texturePath);
		if( path == null ) {
			ide.error("Could not load texture " + { modelPath : modelPath, texturePath : texturePath });
			return null;
		}
		var t = texCache.get(path);
		if( t != null ) {
			if( onReady != null ) haxe.Timer.delay(onReady.bind(t), 1);
			return t;
		}
		var bytes = sys.io.File.getBytes(path);
		var size = hxd.res.Any.fromBytes(path, bytes).toImage().getSize();
		t = new h3d.mat.Texture(size.width,size.height);
		t.clear(0x102030);
		t.name = ide.makeRelative(path);
		texCache.set(path, t);
		if( onReady == null ) onReady = function(_) {};
		loadTextureData(path, onReady, t);
		return t;
	}

	function loadHMD( path : String, isAnimation : Bool ) {
		var fullPath = ide.getPath(path);
		var key = fullPath;
		var hmd = hmdCache.get(key);

		if( hmd != null )
			return hmd;

		var relPath = StringTools.startsWith(path, ide.resourceDir) ? path.substr(ide.resourceDir.length+1) : path;
		var e = try hxd.res.Loader.currentInstance.load(relPath) catch( e : hxd.res.NotFound ) null;
		if( e == null ) {
			var data = sys.io.File.getBytes(fullPath);
			if( data.get(0) != 'H'.code ) {
				var hmdOut = new hxd.fmt.fbx.HMDOut();
				hmdOut.absoluteTexturePath = true;
				hmdOut.loadTextFile(data.toString());
				var hmd = hmdOut.toHMD(null, !isAnimation);
				var out = new haxe.io.BytesOutput();
				new hxd.fmt.hmd.Writer(out).write(hmd);
				data = out.getBytes();
			}
			hmd = hxd.res.Any.fromBytes(path, data).toModel().toHmd();
		} else {
			hmd = e.toHmd();
		}

		hmdCache.set(key, hmd);
		return hmd;
	}

	public function resetCamera( ?obj : h3d.scene.Object, distanceFactor = 1. ) {
		if( obj == null ) obj = s3d;
		var b = obj.getBounds();
		var dx = Math.max(Math.abs(b.xMax),Math.abs(b.xMin));
		var dy = Math.max(Math.abs(b.yMax),Math.abs(b.yMin));
		var dz = Math.max(Math.abs(b.zMax),Math.abs(b.zMin));
		var dist = Math.max(Math.max(dx * 6, dy * 6), dz * 4) * distanceFactor;
		var ang = Math.PI / 4;
		var zang = Math.PI * 0.4;
		s3d.camera.pos.set(Math.sin(zang) * Math.cos(ang) * dist, Math.sin(zang) * Math.sin(ang) * dist, Math.cos(zang) * dist);
		s3d.camera.target.set(0, 0, (b.zMax + b.zMin) * 0.5);
	}

	public function render( e : h3d.Engine ) {
		s3d.render(e);
		s2d.render(e);
	}

	public dynamic function onUpdate(dt:Float) {
	}

	public dynamic function onReady() {
	}

	public dynamic function onResize() {
	}

	public static function getNearest( e : Element ) : Scene {
		while( e.length > 0 ) {
			var c : Dynamic = e.find("canvas")[0];
			if( c != null && c.__scene != null )
				return c.__scene;
			e = e.parent();
		}
		return null;
	}

}
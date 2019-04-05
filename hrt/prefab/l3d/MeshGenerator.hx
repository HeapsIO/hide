package hrt.prefab.l3d;

class Socket {

	public var type : String;
	public var name : String;

	public function new( ?type, ?name ) {
		this.type = type;
		this.name = name;
	}

}

class MeshPart {

	public var socket : Socket;
	public var meshPath : String;
	public var childParts : Array<MeshPart> = [];

	#if editor
	public var previewPos = false;
	#end

	public function new() {
		socket = new Socket();
	}

	public function save() {
		var o : Dynamic = {};
		o.socket = { type : socket.type, name : socket.name };
		o.meshPath = meshPath;

		if( childParts.length > 0 ) {
			var sp : Array<Dynamic> = [];
			for( mp in childParts )
				if( mp.meshPath != null )
					sp.push(mp.save());
			o.childParts = sp;
		}

		return o;
	}

	public function load( o : Dynamic ) {
		if( o.socket != null ) {
			socket.type = o.socket.type;
			socket.name = o.socket.name;
		}
		meshPath = o.meshPath == "none" ? null : o.meshPath;
		var ps : Array<Dynamic> = o.childParts;
		if( ps != null ) {
			for( p in ps ) {
				var mp = new MeshPart();
				mp.load(p);
				childParts.push(mp);
			}
		}
	}

	public function isRoot() : Bool {
		return socket.type == "Root";
	}

	public function getSocketFullName() : String {
		return socket.type + (socket.name == null ? "" : " " + socket.name);
	}
}

class MeshGenerator extends Object3D {

	public var root : MeshPart;

	#if editor
	static var filter : Array<String> = [];
	static var customScene : h3d.scene.Scene;
	#end

	override function save() {
		var obj : Dynamic = super.save();
		obj.root = root.save();
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		root = new MeshPart();
		root.load(obj.root);
	}

	override function makeInstance( ctx : Context ) : Context {
		ctx = ctx.clone(this);
		ctx.local3d = new h3d.scene.Object(ctx.local3d);
		ctx.local3d.name = name;

		var rootObject = new h3d.scene.Object(ctx.local3d);
		rootObject.name = "rootObject";

		if( root == null ) {
			root = new MeshPart();
			root.socket.type = "Root";
		}
		updateInstance(ctx);

		#if editor
		if( customScene == null ) {
			customScene = new h3d.scene.Scene(true, false);
			customScene.checkPasses = false;
		}
		#end

		return ctx;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx,propName);
		resetMesh(ctx);

		#if editor
		createEmptyMeshPart(ctx, root);
		#end

		createMeshPart(ctx, root, ctx.local3d.getObjectByName("rootObject"));
	}

	public function getSocket( obj : h3d.scene.Object, s : Socket ) : h3d.scene.Object {
		for( c in @:privateAccess obj.children ) {
			if( c.name == null ) continue;
			var nameInfos = c.name.split("_");
			if( nameInfos.length < 1 ) continue;
			if( nameInfos[0] == "Socket" ) {
				if( nameInfos.length < 2 ) continue;
				if( nameInfos[1] == s.type ) {
					if( s.name == null ) return c;
					else {
						if( nameInfos.length < 3 ) continue;
						if( nameInfos[2] == s.name ) return c;
					}
				}
			}
		}
		return null;
	}

	function createMeshPart( ctx : Context, mp : MeshPart, parent : h3d.scene.Object ) {
		if( mp.meshPath == null )
			return;

		var obj = ctx.loadModel(mp.meshPath);
		if( mp.isRoot() ) {
			parent.addChild(obj);
			#if editor
			if( mp.previewPos ) parent.addChild(createPreviewSphere());
			#end
		}
		else {
			var socket = getSocket(parent, mp.socket);
			if( socket != null ) {
				socket.addChild(obj);
				#if editor
				if( mp.previewPos ) socket.addChild(createPreviewSphere());
				#end
			}
		}

		for( cmp in mp.childParts )
			createMeshPart(ctx, cmp, obj);
	}

	function resetMesh( ctx : Context ) {
		ctx.local3d.getObjectByName("rootObject").removeChildren();
	}

	function getSocketMatFromHMD( hmd : hxd.fmt.hmd.Library, s : Socket ) : h3d.Matrix {
		if( hmd == null ) return null;
		for( m in @:privateAccess hmd.header.models ) {
			if( m.name == null ) continue;
			var nameInfos = m.name.split("_");
			if( nameInfos.length < 2 ) continue;
			if( nameInfos[0] == "Socket" && nameInfos[1] == s.type && ((s.name == null && nameInfos.length < 3) || (nameInfos.length >= 3 && s.name == nameInfos[2])) ) {
				return m.position.toMatrix();
			}
		}
		return null;
	}

	#if editor

	function createEmptyMeshPart( ctx : Context, mp : MeshPart ) {
		var sl = getSocketListFromHMD(getHMD(ctx, mp.meshPath));
		if( mp.childParts.length < sl.length ) {
			for( s in sl ) {
				var b = true;
				for( cmp in mp.childParts ){
					if ( cmp.socket.name == s.name && cmp.socket.type == s.type ){
						b = false;
						break;
					}
				}
				if( b ) {
					var cmp = new MeshPart();
					cmp.socket.name = s.name;
					cmp.socket.type = s.type;
					mp.childParts.push(cmp);
				}
			}
		}
		for( cmp in mp.childParts )
			createEmptyMeshPart(ctx, cmp);
	}

	var target : h3d.mat.Texture;
	function renderMeshThumbnail( ctx : Context, meshPath : String ) {

		if( target == null )
			target = new h3d.mat.Texture(256, 256, [Target], RGBA);

		if( meshPath == null )
			return;

		var obj = ctx.loadModel(meshPath);
		if( obj == null )
			return;

		for( m in obj.getMaterials() ) {
			m.mainPass.culling = None;
		}

		if(!sys.FileSystem.isDirectory(hide.Ide.inst.getPath(".tmp/meshGeneratorData")))
			sys.FileSystem.createDirectory(hide.Ide.inst.getPath(".tmp/meshGeneratorData"));

		var path = new haxe.io.Path("");
		path.dir = ".tmp/meshGeneratorData/";
		path.file =  extractMeshName(meshPath) + "_thumbnail";
		path.ext = "png";
		var file = hide.Ide.inst.getPath(path.toString());

		if(sys.FileSystem.exists(file))
			return;

		var mainScene = @:privateAccess ctx.local3d.getScene();
		@:privateAccess customScene.children = [];
		@:privateAccess customScene.children.push(obj);

		var cam = new h3d.Camera(45, 1.0, 1.0);
		obj.rotate(0, 0, hxd.Math.degToRad(45));
		var b = obj.getBounds();
		var s = b.toSphere();
		cam.pos.set(0, s.r * 1.8, s.r * 1.25);
		cam.target.set((b.xMax + b.xMin) * 0.5, (b.yMax + b.yMin) * 0.5, (b.zMax + b.zMin) * 0.5);

		customScene.camera = cam;
		var engine = h3d.Engine.getCurrent();
		engine.begin();
		engine.pushTarget(target);
		engine.clear(0,1,0);
		customScene.render(engine);
		engine.popTarget();
		customScene.camera = null;

		var pixels = target.capturePixels();
		var bytes = pixels.toPNG();

		sys.io.File.saveBytes(file, bytes);
	}

	function hasFilter( s : String ) {
		for( f in filter )
			if ( s == f )
				return true;
		return false;
	}

	function createPreviewSphere() {
		var m = new h3d.scene.Mesh( h3d.prim.Sphere.defaultUnitSphere());
		m.scale(0.1);
		m.name = "previewSphere";
		m.material.color.set(1,0,0,1);
		m.material.mainPass.depthTest = Always;
		m.material.mainPass.setPassName("overlay");
		return m;
	}

	function resetPreview( mp : MeshPart ) {
		mp.previewPos = false;
		for( cmp in mp.childParts )
			resetPreview(cmp);
	}

	override function getHideProps() : HideProps {
		return { icon : "paint-brush", name : "MeshGenerator" };
	}

	override function setSelected( ctx : Context, b : Bool ) {
		super.setSelected(ctx, b);

		if( !b ) {
			var previewSpheres = ctx.local3d.findAll(c -> if(c.name == "previewSphere") c else null);
			for( s in previewSpheres ) {
				s.remove();
			}
		}
	}

	function getHMD( ctx : Context, meshPath : String ) : hxd.fmt.hmd.Library {
		if( meshPath == null ) return null;
		return @:privateAccess ctx.shared.cache.loadLibrary(hxd.res.Loader.currentInstance.load(meshPath).toModel());
	}

	function createMeshParts( sl : Array<Socket> ) : Array<MeshPart> {
		var r : Array<MeshPart> = [];
		for( s in sl ){
			var mp = new MeshPart();
			mp.socket.name = s.name;
			mp.socket.type = s.type;
			r.push(mp);
		}
		return r;
	}

	function getSocketListFromHMD( hmd : hxd.fmt.hmd.Library ) : Array<Socket> {
		if( hmd == null ) return [];
		var r : Array<Socket> = [];
		for( m in @:privateAccess hmd.header.models ) {
			if( m.name == null ) continue;
			var nameInfos = m.name.split("_");
			if( nameInfos.length < 2 ) continue;
			if( nameInfos[0] == "Socket" ) {
				var s = new Socket();
				s.type = nameInfos[1];
				if( nameInfos.length >= 3 ) s.name = nameInfos[2];
				r.push(s);
			}
		}
		return r;
	}

	function extractMeshName( path : String ) : String {
		if( path == null ) return "None";
		var childParts = path.split("/");
		return childParts[childParts.length - 1].split(".")[0];
	}

	function getThumbnailPath( ctx : EditContext, meshPath : String ) : String {
		return ctx.ide.getPath(".tmp/meshGeneratorData/"+ extractMeshName(meshPath) +"_thumbnail.png");
	}

	function fillSelectMenu( ctx : EditContext, select : hide.Element, socket : Socket ) {
		for( f in filter ) {
			var meshList : Array<Dynamic> = ctx.scene.config.get("meshGenerator." + f);
			if( meshList == null ) continue;
			for( m in meshList ) {
				var sockets : Array<String> = m.socket;
				var available = false;
				if( sockets == null || sockets.length == 0 )
					available = true;
				else {
					for( s in sockets ) {
						if( s == socket.type ) {
							available = true;
							break;
						}
					}
				}
				if( available )
					new hide.Element('<option>').attr("value", m.path).text(extractMeshName(m.path)).appendTo(select);
			}
		}
	}

	function createMenu( ctx : EditContext, mp : MeshPart ) {

		if( mp.isRoot() ) {
			var rootElement = new hide.Element('
				<div class="group" name="Root">
					<dl>
						<dt>Mesh</dt><dd><select><option value="none">None</option></select>
					</dl>
				</div>
			');
			var select = rootElement.find("select");
			fillSelectMenu(ctx, select, mp.socket);
			if( mp.meshPath != null && select.find('option[value="${mp.meshPath}"]').length == 0 )
				new hide.Element('<option>').attr("value", mp.meshPath).text(extractMeshName(mp.meshPath)).appendTo(select);
			select.change(function(_) {
				var val = select.val();
				mp.meshPath = val == "none" ? null : val;
				mp.childParts = createMeshParts(getSocketListFromHMD(getHMD(ctx.rootContext, mp.meshPath)));
				ctx.onChange(this, null);
				ctx.rebuildProperties();
			});
			select.val(mp.meshPath);

			ctx.properties.add(rootElement, mp, function(pname) {});
		}

		var socketList = getSocketListFromHMD(getHMD(ctx.rootContext, mp.meshPath));
		if( mp.meshPath != null && socketList.length != 0 ) {
			var s = '<div class="group" name="${extractMeshName(mp.meshPath)}">';
			s += '<div align="center"><div class="meshGenerator-thumbnail"></div></div><dl>';
			for( cmp in mp.childParts )
				s += '<dt>${cmp.getSocketFullName()}</dt><dd><select class="${mp.childParts.indexOf(cmp)}"><option value="none">None</option></select>';
			s += '</dl></div>';
			var rootElement = new hide.Element(s);
			for( cmp in mp.childParts ) {
				var select = rootElement.find('.${mp.childParts.indexOf(cmp)}');
				fillSelectMenu(ctx, select, cmp.socket);
				if( cmp.meshPath != null && select.find('option[value="${cmp.meshPath}"]').length == 0 )
					new hide.Element('<option>').attr("value", cmp.meshPath).text(extractMeshName(cmp.meshPath)).appendTo(select);
				select.change(function(_) {
					var mp = mp.childParts[mp.childParts.indexOf(cmp)];
					var val = select.val();
					mp.meshPath = val == "none" ? null : val;
					mp.childParts = createMeshParts(getSocketListFromHMD(getHMD(ctx.rootContext, cmp.meshPath)));
					ctx.onChange(this, null);
					ctx.rebuildProperties();
				});
				select.val(cmp.meshPath);

				select.on("mouseover", function(_) {
					resetPreview(root);
					cmp.previewPos = true;
					ctx.onChange(this, null);
				});
				select.on("mouseleave", function(_) {
					resetPreview(root);
					ctx.onChange(this, null);
				});
			}

			renderMeshThumbnail(ctx.rootContext, mp.meshPath);
			rootElement.find('.meshGenerator-thumbnail').css("background-image", 'url("file://${getThumbnailPath(ctx, mp.meshPath)}")');

			ctx.properties.add(rootElement, mp, function(pname) {});

			for( cmp in mp.childParts ) {
				createMenu(ctx, cmp);
			}
		}
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var families : Array<Dynamic> = ctx.scene.config.get("meshGenerator.families");
		var s = '<div class="group" name="Filter"><dl>';
		for( f in families )
			s += '<dt>${f}</dt><dd><input type="checkbox" class="${families.indexOf(f)}"/></dd>';
		s += '</dl></div>';
		var props = new hide.Element(s);
		for( f in families ) {
			var checkBox = props.find('.${families.indexOf(f)}');
			checkBox.prop("checked", hasFilter(f));
			checkBox.change(function(_) {
				var checked : Bool = checkBox.prop("checked");
				checked ? filter.push(f) : filter.remove(f);
				ctx.rebuildProperties();
			});
		}
		ctx.properties.add(props, this, function(pname) {});

		createMenu(ctx, root);
	}
	#end

	static var _ = Library.register("meshGenerator", MeshGenerator);
}
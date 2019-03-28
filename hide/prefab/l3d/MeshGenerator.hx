package hide.prefab.l3d;

class Socket {
	public var type : String;
	public var name : String;
	public function new() {}
}

class MeshPart {

	public var socketType : String;
	public var socketName : String;
	public var mesh : String;
	public var parts : Array<MeshPart> = [];

	#if editor
	public var previewPos = false;
	#end

	public function new() {
		mesh = "none";
	}

	public function load( o : Dynamic ) {
		socketType = o.socketType;
		socketName = o.socketName;
		mesh = o.mesh == null ? "none" : o.mesh;
		var ps : Array<Dynamic> = o.parts;
		if( ps != null ) {
			for( p in ps ) {
				var mp = new MeshPart();
				mp.load(p);
				parts.push(mp);
			}
		}
	}

	public function isRoot() : Bool {
		return socketType == "Root";
	}

	public function getSocketFullName() : String {
		return socketType + (socketName == null ? "" : " " + socketName);
	}
}

class MeshGenerator extends Object3D {

	var root : MeshPart;

	#if editor
	static var filter : Array<String> = [];
	#end

	override function save() {
		var obj : Dynamic = super.save();
		obj.root = root;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		root = new MeshPart();
		root.load(obj.root);
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		ctx.local3d = new h3d.scene.Object(ctx.local3d);
		ctx.local3d.name = name;

		if( root == null ) {
			root = new MeshPart();
			root.socketType = "Root";
		}
		updateInstance(ctx);

		return ctx;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx,propName);
		resetMesh(ctx);
		generateMesh(ctx);
	}

	function generateMesh( ctx : Context ) {
		if( root != null )
			createMeshPart(ctx, root, ctx.local3d);
	}

	function getSocket( obj : h3d.scene.Object, type: String , name : String ) : h3d.scene.Object {
		for( c in @:privateAccess obj.children ) {
			if( c.name == null ) continue;
			var nameInfos = c.name.split("_");
			if( nameInfos.length < 1 ) continue;
			if( nameInfos[0] == "Socket" ) {
				if( nameInfos.length < 2 ) continue;
				if( nameInfos[1] == type ) {
					if( name == null ) return c;
					else {
						if( nameInfos.length < 3 ) continue;
						if( nameInfos[2] == name ) return c;
					}
				}
			}
		}
		return null;
	}

	function createMeshPart( ctx : Context, mp : MeshPart, parent : h3d.scene.Object ) {

		var obj : h3d.scene.Object = null;
		if( mp.mesh != "none" ){
			obj = ctx.loadModel(mp.mesh);
		}

		if( mp.isRoot() ) {
			if( obj != null ) parent.addChild(obj);
			#if editor
			if( mp.previewPos ) parent.addChild(createPreviewSphere());
			#end
		}
		else {
			var socket = getSocket(parent, mp.socketType, mp.socketName);
			if( socket != null ) {
				if( obj != null ) socket.addChild(obj);
				#if editor
				if( mp.previewPos ) socket.addChild(createPreviewSphere());
				#end
			}
		}

		for( cmp in mp.parts )
			createMeshPart(ctx, cmp, obj);
	}

	function resetMesh( ctx : Context ) {
		ctx.local3d.removeChildren();
	}

	#if editor

	function hasFilter( s : String ){
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
		for( cmp in mp.parts )
			resetPreview(cmp);
	}

	override function getHideProps() : HideProps {
		return { icon : "paint-brush", name : "MeshGenerator" };
	}

	override function setSelected( ctx : Context, b : Bool ) {
		super.setSelected(ctx, b);
	}

	function getHMD( ctx : Context, path : String ) : hxd.fmt.hmd.Library {
		if( path == null || path == "none" ) return null;
		return @:privateAccess ctx.shared.cache.loadLibrary(hxd.res.Loader.currentInstance.load(path).toModel());
	}

	function createMeshParts( sl : Array<Socket> ) : Array<MeshPart> {
		var r : Array<MeshPart> = [];
		for( s in sl ){
			var mp = new MeshPart();
			mp.socketName = s.name;
			mp.socketType = s.type;
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
		var parts = path.split("/");
		return parts[parts.length - 1].split(".")[0];
	}

	function fillSelectMenu( ctx : EditContext, select : hide.Element, socketType : String ) {
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
						if( s == socketType ) {
							available = true;
							break;
						}
					}
				}
				if( available ) {
					new hide.Element('<option>').attr("value", m.path ).text(extractMeshName(m.path)).appendTo(select);
				}
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
			fillSelectMenu(ctx, select, mp.socketType);
			if(select.find('option[value="${mp.mesh}"]').length == 0)
				new hide.Element('<option>').attr("value", mp.mesh).text(extractMeshName(mp.mesh)).appendTo(select);
			select.change(function(_) {
				mp.mesh = select.val();
				mp.parts = createMeshParts(getSocketListFromHMD(getHMD(ctx.rootContext, mp.mesh)));
				ctx.onChange(this, null);
				ctx.rebuildProperties();
			});
			select.val(mp.mesh);

			ctx.properties.add(rootElement, mp, function(pname) {});
		}
		var socketList = getSocketListFromHMD(getHMD(ctx.rootContext, mp.mesh));
		if( mp.mesh != "none" && socketList.length != 0 ) {
			var s = '<div class="group" name="${extractMeshName(mp.mesh)}"><dl>';
			for( cmp in mp.parts )
				s += '<dt>${cmp.getSocketFullName()}</dt><dd><select class="${mp.parts.indexOf(cmp)}"><option value="none">None</option></select>';
			s += '</dl></div>';
			var rootElement = new hide.Element(s);
			for( cmp in mp.parts ) {
				var select = rootElement.find('.${mp.parts.indexOf(cmp)}');
				fillSelectMenu(ctx, select, cmp.socketType);
				if(select.find('option[value="${cmp.mesh}"]').length == 0)
					new hide.Element('<option>').attr("value", cmp.mesh).text(extractMeshName(cmp.mesh)).appendTo(select);
				select.change(function(_) {
					var mp = mp.parts[mp.parts.indexOf(cmp)];
					mp.mesh = select.val();
					mp.parts = createMeshParts(getSocketListFromHMD(getHMD(ctx.rootContext, cmp.mesh)));
					ctx.onChange(this, null);
					ctx.rebuildProperties();
				});
				select.val(cmp.mesh);

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
			ctx.properties.add(rootElement, mp, function(pname) {});

			for( cmp in mp.parts ) {
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
		ctx.properties.add(props, this, function(pname) { });

		createMenu(ctx, root);
	}
	#end

	static var _ = hxd.prefab.Library.register("meshGenerator", MeshGenerator);
}
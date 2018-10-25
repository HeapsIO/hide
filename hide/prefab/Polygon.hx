package hide.prefab;

/*class Polygon extends Object3D {

	#if editor
	public var editor : PolygonEditor;
	var debugColor : Int;
	var debugMesh : h3d.scene.Mesh;
	#end

	public var points : h2d.col.Polygon = [];
	public var primitive : h3d.prim.Polygon;
	public var mesh : h3d.scene.Mesh;

	override function load( obj : Dynamic ) {
		super.load(obj);
		points = obj.points != null ? obj.points : [];
		debugColor = obj.debugColor != null ? obj.debugColor : 0xFFFFFF;
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.points = points;
		obj.debugColor = debugColor;
		return obj;
	}

	override function makeInstance( ctx : Context ) : Context {
		ctx = ctx.clone(this);
		mesh = new h3d.scene.Mesh(null, null, ctx.local3d);
		ctx.local3d = mesh;
		ctx.local3d.name = name;
		#if editor
		debugMesh = new h3d.scene.Mesh(null, null, ctx.local3d);
		debugMesh.name = "debugMesh";
		debugMesh.material.props = h3d.mat.MaterialSetup.current.getDefaults("ui");
		debugMesh.material.blendMode = Alpha;
		debugMesh.material.mainPass.culling = None;
		debugMesh.material.color = h3d.Vector.fromColor(debugColor);
		debugMesh.material.color.a = 0.7;
		#end
		generatePolygon();
		mesh.primitive = primitive;
		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance( ctx : Context, ?propName : String ) {
		super.updateInstance(ctx, null);
		#if editor
		if(editor != null)
			editor.update(propName, ctx);
		if(propName == "debugColor") {
			debugMesh.material.color = h3d.Vector.fromColor(debugColor);
			debugMesh.material.color.a = 0.7;
		}
		#end
	}

	public function generatePolygon(){
		if(primitive != null) primitive.dispose();
		if(points != null){
			var indexes = points.fastTriangulate();
			var idx : hxd.IndexBuffer = new hxd.IndexBuffer();
			for( i in indexes ) if(i != null) idx.push(i);
			var pts = [for( p in points) new h3d.col.Point(p.x, p.y, 0)];
			primitive = new h3d.prim.Polygon(pts, idx);
			primitive.addNormals();
			primitive.addUVs();
			primitive.addTangents() ;
			primitive.alloc(h3d.Engine.getCurrent());
		}
		mesh.primitive = primitive;
		#if editor
		debugMesh.primitive = primitive;
		#end
	}


	#if editor

	override function setSelected( ctx : Context, b : Bool ) {
		if( editor != null ) editor.setSelected(ctx, b);
	}

	override function getHideProps() : HideProps {
		return { icon : "object-ungroup", name : "polyditor" };
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		var props = new hide.Element('<div></div>');
		//if( editor == null ) editor = new PolygonEditor(this, ctx.properties.undo);
		//editor.editContext = ctx;
		//editor.setupUI(props, ctx);
		props.append('
		<div class="group" name="Polygon">
				<dt>Color</dt><dd><input type="color" field="debugColor"/></dd>
		</div>');

		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = hxd.prefab.Library.register("polyditor", hide.prefab.Polygon);
}*/
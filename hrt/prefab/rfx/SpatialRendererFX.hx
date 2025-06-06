package hrt.prefab.rfx;

class SPRFXObject extends h3d.scene.Object {
	public var sprfx : SpatialRendererFX;
	var renderer : h3d.scene.Renderer;

	public function new(sprfx : SpatialRendererFX, ?parent : h3d.scene.Object) {
		super(parent);
		this.sprfx = sprfx;
	}

	override function sync(ctx : h3d.scene.RenderContext) {
		super.sync(ctx);

		#if !editor
		if (renderer == null) {
			this.renderer = ctx.scene.renderer;
			this.renderer.effects.push(@:privateAccess sprfx.instance);
		}
		#end
	}

	override function onRemove() {
		super.onRemove();
		this.renderer?.effects?.remove(sprfx);
	}
}

typedef SPRFXDebug = {
	var color : Int;
	var mesh : h3d.scene.Mesh;
}

enum SPRFXShape {
	Sphere(radius : Float);
	Box(width : Float, height: Float);
}

class SpatialRendererFX extends Object3D implements h3d.impl.RendererFX {
	@:c public var innerShape : SPRFXShape;
	@:c public var outerShape : SPRFXShape;

	@:s var enableInEditor = true;

	var cam : h3d.Camera;

	// Debug
	@:s var debug : Bool = false;
	var innerShapeDebug = { color : 0xFFFF00FF, mesh : null };
	var outerShapeDebug = { color : 0xFF00EEFF, mesh : null };

	var instance : SpatialRendererFX;

	public function new(parent:Prefab, contextShared: ContextShared) {
		super(parent, contextShared);
		this.innerShape = Sphere(1);
		this.outerShape = Sphere(1);
	}

	override function load(data: Dynamic) {
		super.load(data);

		function loadShape(shape : Dynamic) : SPRFXShape {
			if (shape == null)
				return Sphere(1);

			return switch (shape.shape) {
				case 0:
					return Sphere(shape.radius);
				case 1:
					return Box(shape.width, shape.height);
				default:
					throw "not implemented";
			};
		}

		this.innerShape = loadShape(data.innerShape);
		this.outerShape = loadShape(data.outerShape);
	}

	override function copy(data: Dynamic) : Void {
		super.copy(data);

		var s : SpatialRendererFX = cast data;
		this.load(s.save());
	}

	override function save() : Dynamic {
		var obj = super.save();

		function saveShape(shape : SPRFXShape) : Dynamic {
			if (shape == null)
				return { shape: 0, radius: 1 };

			return switch (shape) {
				case Sphere(radius):
					{ shape: 0, radius: radius };
				case Box(width, height):
					{ shape: 1, width: width, height: height };
				default:
					throw { shape: 0, radius: 1 };
			};
		}

		obj.innerShape = saveShape(this.innerShape);
		obj.outerShape = saveShape(this.outerShape);
		return obj;
	}


	public function start( r : h3d.scene.Renderer ) {
	}

	public function begin( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
	}

	public function end( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
	}

	inline function checkEnabled() {
		return enabled #if editor && enableInEditor && !inGameOnly #end;
	}

	override function make( ?sh:hrt.prefab.Prefab.ContextMake ) : Prefab {
		instance = cast this.clone();
		// unlink this.props and instance.props for ScreenShaderGraph
		// because props is cloned by ref
		instance.props = {};

		if (!shouldBeInstanciated())
			return this;

		makeInstance();
		for (c in children)
			makeChild(c);
		postMakeInstance();
		updateInstance();

		return this;
	}

	override function makeObject(parent3d: h3d.scene.Object) {
		var o = new SPRFXObject(this, parent3d);
		return o;
	}

	override function updateInstance(?propName : String) {
		if (instance != null) {
			if (propName != null && propName != "props") {
				Reflect.setField(instance, propName, Reflect.field(this, propName));
				return;
			}

			for (f in Reflect.fields(this)) {
				if (f != "props")
					Reflect.setField(instance, f, Reflect.field(this, f));
			}
		}

		function createPrim(shape : SPRFXShape) : h3d.prim.Primitive {
			switch(shape) {
				case Sphere(radius):
					var prim = new h3d.prim.Sphere(radius, 64, 64);
					prim.addNormals();
					prim.addUVs();
					return prim;
				case Box(width, height):
					var prim = new h3d.prim.Cube(width);
					prim.addNormals();
					prim.addUVs();
					return prim;
			}
		}

		function applyDebug(sprDebug : SPRFXDebug, shape : SPRFXShape) {
			if (sprDebug != null) {
				sprDebug.mesh.remove();
				sprDebug.mesh = null;
			}

			if (!debug) return;

			sprDebug.mesh = new h3d.scene.Mesh(createPrim(shape), local3d);
			sprDebug.mesh.name = "SpatialRendererFXDebug";
			sprDebug.mesh.material.mainPass.depth(true, LessEqual);
			var s = new h3d.shader.AlphaMult();
			s.alpha = 0.3;
			sprDebug.mesh.material.mainPass.addShader(s);
			sprDebug.mesh.material.blendMode = Alpha;
			sprDebug.mesh.material.mainPass.setPassName("overlay");
			sprDebug.mesh.ignoreParentTransform = false;
			var c = hrt.impl.ColorSpace.Color.fromInt(sprDebug.color);
			hrt.impl.ColorSpace.iRGBtofRGB(c, sprDebug.mesh.material.color);
		}

		applyDebug(innerShapeDebug, this.innerShape);
		applyDebug(outerShapeDebug, this.outerShape);
	}

	override function dispose() {
		if (this.instance != null) {
			var scene = this.instance.shared.root3d?.getScene();

			if(scene != null)
				scene.renderer.effects.remove(this.instance);

			var i = this.instance;
			this.instance = null;
			i.dispose();
		}

		super.dispose();
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return { name : Type.getClassName(Type.getClass(this)).split(".").pop(), icon : "plus-circle" };
	}

	override function edit(ctx:hide.prefab.EditContext) {
		var e = new hide.Element('
		<div class="group" name="Spatial Renderer FX">
			<dl>
				<dt>Debug</dt><dd><input type="checkbox" field="debug"/></dd>
				<dt>Shape</dt><dd><select id="shape-sel"></select></dd>
				<div id="params">
				</div>
			</dl>
		</div>
		');

		var shapeSel = e.find("#shape-sel");
		for (idx => el in Type.getEnumConstructs(SPRFXShape))
			shapeSel.append(new hide.Element('<option value="$el" ${ Type.enumIndex(this.innerShape) == idx ? 'selected' : ''}>$el</option>'));
		shapeSel.on("change", function(e) {
			var prevInner = this.innerShape;
			var prevOuter = this.outerShape;

			switch (shapeSel.val()) {
				case "Sphere":
					this.innerShape = Sphere(10);
					this.outerShape = Sphere(15);
				case "Box":
					this.innerShape = Box(10, 10);
					this.outerShape = Box(15, 15);
				default:
			}

			var newInner = this.innerShape;
			var newOuter = this.outerShape;

			ctx.properties.undo.change(Custom(function(undo) {
				this.innerShape = undo ? prevInner : newInner;
				this.outerShape = undo ? prevOuter : newOuter;
				ctx.rebuildProperties();
			}));

			ctx.rebuildProperties();
		});

		var paramsEl = e.find("#params");
		var param : hide.Element = null;
		function onChange() {
			var prevInner = this.innerShape;
			var prevOuter = this.outerShape;

			switch (this.innerShape) {
				case Sphere(_):
					this.innerShape = Sphere(Std.parseFloat(param.find('#innerRadius').val()));
					this.outerShape = Sphere(Std.parseFloat(param.find('#outerRadius').val()));
				case Box(_):
			}

			var newInner = this.innerShape;
			var newOuter = this.outerShape;

			ctx.properties.undo.change(Custom(function(undo) {
				this.innerShape = undo ? prevInner : newInner;
				this.outerShape = undo ? prevOuter : newOuter;
				ctx.rebuildProperties();
				this.updateInstance();
			}));

			this.updateInstance();
		}
		switch ([this.innerShape, this.outerShape]) {
			case [Sphere(r1), Sphere(r2)]:
				param = new hide.Element('<div>
					<dt>Inner radius</dt><dd><input type="number" id="innerRadius"/></dd>
					<dt>Outer Radius</dt><dd><input type="number" id="outerRadius"/></dd>
				</div>');

				function setup(e : hide.Element, value : Dynamic) {
					e.val(value);
					e.on("change", () -> onChange());
				}
				setup(param.find('#innerRadius'), r1);
				setup(param.find('#outerRadius'), r2);

			default:
				param = new hide.Element('<div><dt></dt><dd><p>Not supported</p></dd></div>');
		}
		paramsEl.append(param);
		ctx.properties.add(e, this);
	}
	#end

	public function getFactor() : Float {
		if (cam == null)
			cam = local3d.getScene().camera;
		var distance = (local3d.getAbsPos().getPosition() - cam.pos).length();

		switch ([innerShape, outerShape]) {
			case [Sphere(r1), Sphere(r2)]:
				if (distance < r1) return 1;
				if (distance > r2) return 0;
				return 1 - hxd.Math.clamp((distance - r1) / (r2 - r1), 0, 1);
			default:
				return 0.;
		}
	}
}
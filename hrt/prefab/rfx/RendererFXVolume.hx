package hrt.prefab.rfx;

typedef DebugVolume = {
	var color : Int;
	var mesh : h3d.scene.Mesh;
}

class RendererFXVolume extends Object3D {
	@:s public var priority : Int;
	@:c public var innerShape : h3d.impl.RendererFXVolume.Shape;
	@:c public var outerShape : h3d.impl.RendererFXVolume.Shape;

	@:s var debug : Bool = false;
	var innerShapeDebug = { color : 0xFFFF00FF, mesh : null };
	var outerShapeDebug = { color : 0xFF00EEFF, mesh : null };

	override function load(data: Dynamic) {
		super.load(data);

		function loadShape(shape : Dynamic) : h3d.impl.RendererFXVolume.Shape {
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

		var s : RendererFXVolume = cast data;
		this.load(s.save());
	}

	override function save() : Dynamic {
		var obj = super.save();

		function saveShape(shape : h3d.impl.RendererFXVolume.Shape) : Dynamic {
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

	override function makeObject(parent3d: h3d.scene.Object) {
		var o = new h3d.impl.RendererFXVolume(parent3d);
		o.innerShape = this.innerShape;
		o.outerShape = this.outerShape;
		o.priority = this.priority;

		return o;
	}

	override function postMakeInstance() {
		var o : h3d.impl.RendererFXVolume = cast local3d;
		var rendererFxs : Array<RendererFX> = cast findAll((p) -> { return Std.isOfType(p, RendererFX) && p.enabled; });
		o.effects = [];
		for (r in rendererFxs)
			o.effects.push(@:privateAccess r.instance);
	}

	override function updateInstance(?propName : String) {
		super.updateInstance(propName);

		var volume : h3d.impl.RendererFXVolume = cast local3d;
		volume.innerShape = this.innerShape;
		volume.outerShape = this.outerShape;
		volume.priority = this.priority;

		function applyDebug(sprDebug : DebugVolume, shape : h3d.impl.RendererFXVolume.Shape) {
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

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return { name : Type.getClassName(Type.getClass(this)).split(".").pop(), icon : "cubes" };
	}

	override function edit(ctx:hide.prefab.EditContext) {
		var e = new hide.Element('
		<div class="group" name="Spatial Renderer FX">
			<dl>
				<dt>Debug</dt><dd><input type="checkbox" field="debug"/></dd>
				<dt>Priority</dt><dd><input type="range" min="0" max="10" step="1" field="priority"/></dd>
				<dt>Shape</dt><dd><select id="shape-sel"></select></dd>
				<div id="params">
				</div>
			</dl>
		</div>
		');

		var volume : h3d.impl.RendererFXVolume = cast local3d;
		var shapeSel = e.find("#shape-sel");
		for (idx => el in Type.getEnumConstructs(h3d.impl.RendererFXVolume.Shape))
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

	function createPrim(shape : h3d.impl.RendererFXVolume.Shape) : h3d.prim.Primitive {
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

	public function getFactor() : Float {
		if (local3d == null) return 0.;
		return cast(local3d, h3d.impl.RendererFXVolume).getFactor();
	}

	static var _ = Prefab.register("RendererFXVolume", RendererFXVolume);
}
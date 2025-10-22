package hide.comp;

enum Shape {
	Box(center : h3d.col.Point, x : Float, y : Float, z : Float);
	Sphere(center : h3d.col.Point, radius : Float);
	Capsule(center: h3d.col.Point, radius : Float, height : Float);
	Cylinder(center: h3d.col.Point, radius : Float, height : Float);
}

typedef ShapeEditorOptions = {
	@:optional var shapesAllowed : Array<String>;
	@:optional var disableShapeEdition : Bool;
}

class ShapeEditor extends Component {
	var parentObj : h3d.scene.Object;
	var interactive : h3d.scene.Object;

	var shape : Shape;

	public function new(parentObj : h3d.scene.Object, ?shape: Shape, ?options : ShapeEditorOptions, ?parent: Element) {
		this.parentObj = parentObj;
		this.shape = shape;

		// Set default value if not passed in constructor
		if (shape == null)
			this.shape = Box(new h3d.col.Point(0, 0, 0), 1, 1, 1);

		var allowedShapes = options.shapesAllowed ?? Type.getEnumConstructs(Shape);
    	super(parent, new Element('<div id="shape-editor">
			<div id="params">
				<label>Shape</label>
				<select id="shape-type">
					${[for (s in allowedShapes) '<option value="${Shape.createByName(s, []).getIndex()}">${s}</option>'].join("")}
				</select>
				<label class="edition">Edit Shape</label>
				<button class="edition"><div class="icon ico ico-pencil"></div></button>
			</div>
			<div id="extra-params edition"></div>
		</div>'));

		var extraParams = element.find("#extra-params");
		var shapeTypeSelector = element.find("#shape-type");
		shapeTypeSelector.on("change", function() {
			var center = new h3d.col.Point(0, 0, 0);
			this.shape = switch(Shape.createByIndex(Std.parseInt(shapeTypeSelector.val()), [])) {
				case Box(_,_,_):
					Box(center, 1, 1, 1);
				case Sphere(_):
					Sphere(center, 1);
				case Capsule(_,_):
					Capsule(center, 1, 1);
				case Cylinder(_,_):
					Cylinder(center, 1, 1);
			}

			extraParams.empty();
			extraParams.append(getExtraParamsEdit());

			interactive?.remove();
			interactive = getShapeInteractive();
			onChange();
		});

		extraParams.append(getExtraParamsEdit());
		interactive = getShapeInteractive();

		if (options?.disableShapeEdition)
			element.find(".edition").hide();
	}

	override function remove() {
		super.remove();
		interactive?.remove();
	}

	public function getValue() : Shape {
		return this.shape;
	}


	function getExtraParams() : Array<Dynamic> {
		var params : Array<Dynamic> = [];
		var extraParam = element.find("#extra-params");
		var inputs = extraParam.find("input");

		var idx = 0;
		while (idx < inputs.length) {
			var input = new Element(inputs[idx]);
			if (input.parent().hasClass("vector")) {
					var vec = new h3d.Vector(Std.parseFloat(new Element(inputs[idx]).val()),
				Std.parseFloat(new Element(inputs[idx + 1]).val()),
				Std.parseFloat(new Element(inputs[idx + 2]).val()));
				params.push(vec);
				idx += 3;
			}
			else {
				params.push(Std.parseFloat(input.val()));
				idx++;
			}
		}

		return params;
	}

	function getExtraParamsEdit() : Element {
		function paramChanged() {
			this.shape = Shape.createByIndex(this.shape.getIndex(), getExtraParams());
			interactive?.remove();
			interactive = getShapeInteractive();
			onChange();
		}

		return switch (getValue()) {
			case Box(center, x, y, z):
				var e = new Element('
					<label>Center</label>
					<div class="inlined vector"><input type="number" id="x" value="${center.x}"/><input type="number" id="y" value="${center.y}"/><input type="number" id="z" value="${center.z}"/></div>
					<label>Size</label>
					<div class="inlined"><input type="number" min="0" id="size-x" value="$x"/><input type="number" min="0" id="size-y" value="$y"/><input type="number" min="0" id="size-z" value="$z"/></div>
				');
				e.find("input").on("change", paramChanged);
				e;

			case Sphere(center, radius):
				var e = new Element('
					<label>Center</label>
					<div class="vector"><input type="number" id="x" value="${center.x}"/><input type="number" id="y" value="${center.y}"/><input type="number" id="z" value="${center.z}"/></div>
					<label>Radius</label>
					<div><input type="number" min="0" id="radius" value="$radius"/></div>
				');
				e.find("input").on("change", paramChanged);
				e;

			case Capsule(center, radius, height), Cylinder(center, radius, height):
				var e = new Element('
					<label>Center</label>
					<div class="vector"><input type="number" id="x" value="${center.x}"/><input type="number" id="y" value="${center.y}"/><input type="number" id="z" value="${center.z}"/></div>
					<label>Radius</label>
					<div><input type="number" min="0" id="radius" value="$radius"/></div>
					<label>Height</label>
					<div><input type="number" min="0" id="height" value="$height"/></div>
				');
				e.find("input").on("change", paramChanged);
				e;
		}
	}


	function getShapeInteractive() : h3d.scene.Mesh {
		var offset = new h3d.Vector(0, 0, 0);
		var prim : h3d.prim.Primitive = switch (shape) {
			case Box(center, x, y, z):
				var b = new h3d.prim.Cube(x, y, z, true);
				offset.load(center);
				b.addNormals();
				b;
			case Sphere(center, radius):
				var s = new h3d.prim.Sphere(radius);
				offset.load(center);
				s.addNormals();
				s;
			case Capsule(center, radius, height):
				var c = new h3d.prim.Capsule(radius, height, 8, Z);
				offset.load(center);
				c.addNormals();
				c;
			case Cylinder(center, radius, height):
				var c = new h3d.prim.Cylinder(16, radius, height, true);
				offset.load(center);
				c.addNormals();
				c;
		}

		var mesh = new h3d.scene.Mesh(prim, null, parentObj);
		mesh.setPosition(offset.x, offset.y, offset.z);
		var s = new h3d.shader.AlphaMult();
		s.alpha = 0.3;
		mesh.material.mainPass.addShader(s);
		mesh.material.blendMode = Alpha;
		mesh.material.mainPass.setPassName("overlay");
		var p = mesh.material.allocPass("highlight");
		p.culling = None;
		p.depthWrite = false;
		p.depthTest = LessEqual;
		p.addShader(new h3d.shader.FixedColor(0xffffff));

		return mesh;
	}

	public dynamic function onChange() {}
}

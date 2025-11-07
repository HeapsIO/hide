package hide.comp;

// Shapes center and rotation are defined relative to parent
enum Shape {
	Box(center : h3d.col.Point, rotation : h3d.Vector, sizeX : Float, sizeY : Float, sizeZ : Float);
	Sphere(center : h3d.col.Point, radius : Float);
	Capsule(center: h3d.col.Point, rotation : h3d.Vector, radius : Float, height : Float);
	Cylinder(center: h3d.col.Point, rotation : h3d.Vector, radius : Float, height : Float);
}

typedef ShapeEditorOptions = {
	@:optional var shapesAllowed : Array<String>;
	@:optional var disableShapeEdition : Bool;
	@:optional var multipleShapes : Bool;
}

class ShapeEditor extends Component {
	static var DEFAULT_COLOR = 0x55FFFFFF;
	static var SELECTED_COLOR = 0x553185CE;
	static var INTERSECTION_COLOR = 0x55FF0000;
	static var SELECTED_INTERSECTION_COLOR = 0x99FF0000;

	public var rootDebugObj(default, set) : h3d.scene.Object;
	var shapes : Array<Shape> = [];

	var interactives : Array<h3d.scene.Mesh> = [];
	var selectedShapeIdx : Int = -1;
	var isInShapeEdition = false;
	var gizmo : hrt.tools.Gizmo;
	var scene : Scene;

	public function new(scene : Scene, rootDebugObj : h3d.scene.Object, ?shapes : Array<Shape>, ?options : ShapeEditorOptions, ?parent: Element) {
		this.scene = scene;
		this.rootDebugObj = rootDebugObj;
		this.shapes = shapes;

		// Set default value if not passed in constructor
		if (this.shapes == null)
			this.shapes = [];

		var allowedShapes = options?.shapesAllowed ?? Type.getEnumConstructs(Shape);
    	super(parent, new Element('<div id="shape-editor">
			<div id="shape-list">
			</div>
			<div id="buttons">
				<div id="btn-add" class="icon ico ico-plus"></div>
				<div id="btn-remove" class="icon ico ico-minus"></div>
			</div>
			<div id="shape-inspector">
				<label>Shape</label>
				<select id="shape-type">
					${[for (s in allowedShapes) '<option value="${Shape.createByName(s, []).getIndex()}">${s}</option>'].join("")}
				</select>
				<label class="edition">Edit Shape</label>
				<button id="edit-btn" class="edition"><div class="icon ico ico-pencil"></div></button>
			</div>
			<div id="extra-params" class="edition"></div>
		</div>'));

		if (options != null && options?.disableShapeEdition)
			element.find(".edition").hide();

		element.find("#btn-add").on("click", function(e) {
			this.shapes.push(Box(new h3d.col.Point(0, 0, 0), new h3d.Vector(0, 0, 0), 1, 1, 1));
			updateShapeList();
			var i = getInteractive(this.shapes[this.shapes.length - 1], (this.shapes.length - 1) == selectedShapeIdx, rootDebugObj);
			interactives.push(i);
			onChange();
			e.preventDefault();
			e.stopPropagation();
		});

		element.find("#btn-remove").on("click", function(e) {
			if (selectedShapeIdx == -1) {
				this.shapes.pop();
				var i = interactives.pop();
				i.remove();
			}
			else {
				this.shapes.remove(this.shapes[selectedShapeIdx]);
				var i = interactives[selectedShapeIdx];
				i.remove();
				interactives.remove(i);
			}

			selectedShapeIdx = -1;
			uninspect();
			updateShapeList();
			onChange();
			e.preventDefault();
			e.stopPropagation();
		});

		element.find("#edit-btn").on("click", function() {
			if (isInShapeEdition)
				stopShapeEditing();
			else
				startShapeEditing();
		});

		uninspect();
		updateShapeList();
		createAllInteractives();
	}

	public function refresh(?shapes : Array<Shape>) {
		this.shapes = shapes;
		if (this.shapes == null)
			this.shapes = [];

		updateShapeList();
		removeAllInteractives();
		createAllInteractives();
		if (selectedShapeIdx != -1 && selectedShapeIdx < this.shapes.length) {
			inspect(this.shapes[selectedShapeIdx]);
			gizmo?.setTransform(interactives[selectedShapeIdx].getAbsPos());
		}
		else {
			stopShapeEditing();
		}
	}

	override function remove() {
		super.remove();
		uninspect();
		selectedShapeIdx = -1;
		for (i in interactives)
			i.remove();
	}

	public function getValue() : Array<Shape> {
		return this.shapes;
	}

	public dynamic function onChange() {}


	function startShapeEditing() {
		isInShapeEdition = true;
		element.find("#edit-btn").toggleClass("activated", true);

		var lclOffsetPosition = new h3d.Vector(0, 0, 0);
		var lclOffsetRotation = new h3d.Vector(0, 0, 0);
		var lclOffsetScale = new h3d.Vector(0, 0, 0);

		var initialShape = this.shapes[selectedShapeIdx];
		var initialRelPos = new h3d.Matrix();

		@:privateAccess scene.editor.showGizmo = false;
		gizmo = new hrt.tools.Gizmo(scene.s3d, scene.s2d);
		gizmo.allowNegativeScale = true;

		gizmo.setTransform(interactives[selectedShapeIdx].getAbsPos());

		gizmo.onStartMove = function(mode : hrt.tools.Gizmo.TransformMode) {
			lclOffsetPosition.set(0, 0, 0);
			lclOffsetRotation.set(0, 0, 0);
			lclOffsetScale.set(1, 1, 1);

			initialShape = shapes[selectedShapeIdx];
			initialRelPos.load(interactives[selectedShapeIdx].getTransform());

			gizmo.setTransform(interactives[selectedShapeIdx].getAbsPos());
		}

		gizmo.onMove = function(position: h3d.Vector, rotation: h3d.Quat, scale: h3d.Vector) {
			var interactive = interactives[selectedShapeIdx];

			var relPos = gizmo.getAbsPos().multiplied(interactive.parent.getAbsPos().getInverse());
			interactive.setTransform(relPos);
			var curRelPos = interactive.getTransform();

			if (position != null)
				lclOffsetPosition.load(curRelPos.getPosition() - initialRelPos.getPosition());

			if (rotation != null)
				lclOffsetRotation.load(curRelPos.getEulerAngles() - initialRelPos.getEulerAngles());

			if (scale != null)
				lclOffsetScale.load(scale);

			// Update interactive
			switch (initialShape) {
				case Box(center, rotation, x, y, z):
					if (lclOffsetScale != null) {
						curRelPos.prependScale(1 / x, 1 / y, 1 / z);
						curRelPos.prependScale(x + lclOffsetScale.x - 1, y + lclOffsetScale.y - 1, z + lclOffsetScale.z - 1);
					}

				case Sphere(center, radius):
					if (lclOffsetScale != null) {
						var offsetRadius = lclOffsetScale.x != 1 ? lclOffsetScale.x : lclOffsetScale.y != 1 ? lclOffsetScale.y : lclOffsetScale.z;
						offsetRadius -= 1;
						curRelPos.prependScale(1 / radius, 1 / radius, 1 / radius);
						curRelPos.prependScale(radius + offsetRadius, radius + offsetRadius, radius + offsetRadius);
					}

				case Capsule(center, rotation, radius, height):
					if (lclOffsetScale != null) {
						if (lclOffsetScale.x == lclOffsetScale.y && lclOffsetScale.x == lclOffsetScale.z) {
							var radiusOffset = lclOffsetScale.x == 1 ? lclOffsetScale.y : lclOffsetScale.x;
							radiusOffset -= 1;
							curRelPos.prependScale(1 / radius, 1 / radius, 1 / height);
							curRelPos.prependScale(radius + radiusOffset, radius + radiusOffset, height + lclOffsetScale.z - 1);
						}
						else {
							// We need to recreate the capsule prim if scale isn't uniform
							var radiusOffset = lclOffsetScale.x == 1 ? lclOffsetScale.y : lclOffsetScale.x;
							radiusOffset -= 1;
							var newShape = Capsule(curRelPos.getPosition(), curRelPos.getEulerAngles(), radius + radiusOffset, height + lclOffsetScale.z - 1);
							shapes[selectedShapeIdx] = newShape;
							interactives[selectedShapeIdx].remove();
							interactives[selectedShapeIdx] = getInteractive(newShape, true, rootDebugObj);
						}
					}

				case Cylinder(center, rotation, radius, height):
					if (lclOffsetScale != null) {
						var radiusOffset = lclOffsetScale.x == 1 ? lclOffsetScale.y : lclOffsetScale.x;
						radiusOffset -= 1;
						curRelPos.prependScale(1 / radius, 1 / radius, 1 / height);
						curRelPos.prependScale(radius + radiusOffset, radius + radiusOffset, height + lclOffsetScale.z - 1);
					}

				default:
			}

			interactive.setTransform(curRelPos);
		}

		gizmo.onFinishMove = function() {
			var newShape = switch(shapes[selectedShapeIdx]) {
				case Box(center, rotation, sizeX, sizeY, sizeZ):
					Box(center + lclOffsetPosition, rotation + lclOffsetRotation, sizeX + lclOffsetScale.x - 1, sizeY + lclOffsetScale.y - 1, sizeZ + lclOffsetScale.z - 1);
				case Sphere(center, radius):
					var offsetRadius = lclOffsetScale.x != 1 ? lclOffsetScale.x : lclOffsetScale.y != 1 ? lclOffsetScale.y : lclOffsetScale.z;
					offsetRadius -= 1;
					Sphere(center + lclOffsetPosition, radius + offsetRadius);
				case Capsule(center, rotation, radius, height):
					if (lclOffsetScale.x == lclOffsetScale.y && lclOffsetScale.x == lclOffsetScale.z) {
						var radiusOffset = lclOffsetScale.x == 1 ? lclOffsetScale.y : lclOffsetScale.x;
						radiusOffset -= 1;
						Capsule(center + lclOffsetPosition, rotation + lclOffsetRotation, radius + radiusOffset, height + lclOffsetScale.z - 1);
					}
					else {
						Capsule(center, rotation, radius, height);
					}
				case Cylinder(center, rotation, radius, height):
					var radiusOffset = lclOffsetScale.x == 1 ? lclOffsetScale.y : lclOffsetScale.x;
					radiusOffset -= 1;
					Cylinder(center + lclOffsetPosition, rotation + lclOffsetRotation, radius + radiusOffset, height + lclOffsetScale.z - 1);
			}

			shapes[selectedShapeIdx] = newShape;
			interactives[selectedShapeIdx].remove();
			interactives[selectedShapeIdx] = getInteractive(newShape, true, rootDebugObj);
			inspect(newShape);
			onChange();
		}

		@:privateAccess scene.editor.gizmo.onChangeMode = (mode) -> {
			switch (mode) {
				case Translation:
					gizmo.translationMode();
				case Rotation:
					gizmo.rotationMode();
				case Scaling:
					gizmo.scalingMode();
			}
		}

		var el = new Element(element[0].ownerDocument.body);
		el.on("mousemove.shapeeditor", (e) -> {
			gizmo.update(0, true);
			e.stopPropagation();
			e.preventDefault();
		});
	}

	function stopShapeEditing() {
		isInShapeEdition = false;
		element.find("#edit-btn").toggleClass("activated", false);

		@:privateAccess scene.editor.showGizmo = true;
		var el = new Element(element[0].ownerDocument.body);
		el.off("mousemove.shapeeditor");
		gizmo.remove();
		gizmo = null;
		@:privateAccess scene.editor.gizmo.onChangeMode = (mode) -> {};
	}


	function inspect(shape : Shape) {
		var shapeSelect = element.find("#shape-type");
		var extraParams = element.find("#extra-params");

		function updateShape() {
			var selIdx = Std.parseInt(shapeSelect.val());
			if (this.shapes[selectedShapeIdx].getIndex() != selIdx)
				this.shapes[selectedShapeIdx] = getDefaultShape(Shape.createByIndex(selIdx, getExtraParams()));
			else
				this.shapes[selectedShapeIdx] = Shape.createByIndex(selIdx, getExtraParams());

			var i = interactives[selectedShapeIdx];
			i.remove();
			interactives[selectedShapeIdx] = getInteractive(this.shapes[selectedShapeIdx], true, rootDebugObj);

			gizmo?.setTransform(interactives[selectedShapeIdx].getTransform());
			updateShapeList();
			inspect(this.shapes[selectedShapeIdx]);
			onChange();
		}

		element.find("#extra-params").empty();
		element.find("#shape-inspector").show();

		shapeSelect.val(shape.getIndex());
		shapeSelect.on("change", function(e) {
			updateShape();
			e.preventDefault();
			e.stopPropagation();
		});

		switch (shape) {
			case Box(center, rotation, x, y, z):
				var e = new Element('
					<label>Center</label>
					<div class="inlined vector"><input type="number" id="x" value="${center.x}"/><input type="number" id="y" value="${center.y}"/><input type="number" id="z" value="${center.z}"/></div>
					<label>Rotation (Radians)</label>
					<div class="inlined vector"><input type="number" id="rotation-x" value="${rotation.x}"/><input type="number" id="rotation-y" value="${rotation.y}"/><input type="number" id="rotation-z" value="${rotation.z}"/></div>
					<label>Size</label>
					<div class="inlined"><input type="number" min="0" id="size-x" value="$x"/><input type="number" min="0" id="size-y" value="$y"/><input type="number" min="0" id="size-z" value="$z"/></div>
				');
				e.find("input").on("change", updateShape);
				e.appendTo(extraParams);

			case Sphere(center, radius):
				var e = new Element('
					<label>Center</label>
					<div class="inlined vector"><input type="number" id="x" value="${center.x}"/><input type="number" id="y" value="${center.y}"/><input type="number" id="z" value="${center.z}"/></div>
					<label>Radius</label>
					<div><input type="number" min="0" id="radius" value="$radius"/></div>
				');
				e.find("input").on("change", updateShape);
				e.appendTo(extraParams);

			case Capsule(center, rotation, radius, height), Cylinder(center, rotation, radius, height):
				var e = new Element('
					<label>Center</label>
					<div class="inlined vector"><input type="number" id="x" value="${center.x}"/><input type="number" id="y" value="${center.y}"/><input type="number" id="z" value="${center.z}"/></div>
					<label>Rotation (Radians)</label>
					<div class="inlined vector"><input type="number" id="rotation-x" value="${rotation.x}"/><input type="number" id="rotation-y" value="${rotation.y}"/><input type="number" id="rotation-z" value="${rotation.z}"/></div>
					<label>Radius</label>
					<div><input type="number" min="0" id="radius" value="$radius"/></div>
					<label>Height</label>
					<div><input type="number" min="0" id="height" value="$height"/></div>
				');
				e.find("input").on("change", updateShape);
				e.appendTo(extraParams);
		}
	}

	function uninspect() {
		stopShapeEditing();
		element.find("#shape-inspector").hide();
		element.find("#extra-params").empty();
	}


	public static function getInteractive(shape : Shape, highlight : Bool, parent : h3d.scene.Object) : h3d.scene.Mesh {
		var offset = new h3d.Vector(0, 0, 0);
		var offsetRotation = new h3d.Vector(0, 0, 0);
		var prim : h3d.prim.Primitive = switch (shape) {
			case Box(center, rotation, x, y, z):
				var b = new h3d.prim.Cube(x, y, z, true);
				offset.load(center);
				offsetRotation.load(rotation);
				b.addNormals();
				b;
			case Sphere(center, radius):
				var s = new h3d.prim.Sphere(radius, 20, 20);
				offset.load(center);
				s.addNormals();
				s;
			case Capsule(center, rotation, radius, height):
				var c = new h3d.prim.Capsule(radius, height, 20, Z);
				offset.load(center);
				offsetRotation.load(rotation);
				c.addNormals();
				c;
			case Cylinder(center, rotation, radius, height):
				var c = new h3d.prim.Cylinder(20, radius, height, true);
				offset.load(center);
				offsetRotation.load(rotation);
				c.addNormals();
				c;
		}

		var shapeColor = highlight ? SELECTED_COLOR : DEFAULT_COLOR;
		var intersectionColor = highlight ? SELECTED_INTERSECTION_COLOR : INTERSECTION_COLOR;

		var mesh = new h3d.scene.Mesh(prim, null, parent);
		mesh.setPosition(offset.x, offset.y, offset.z);
		mesh.setRotation(offsetRotation.x, offsetRotation.y, offsetRotation.z);
		mesh.material.castShadows = false;
		mesh.material.blendMode = Alpha;
		mesh.material.color.setColor(shapeColor);
		mesh.material.mainPass.setPassName("afterTonemapping");

		var meshWireframe = new h3d.scene.Mesh(prim, null, mesh);
		meshWireframe.name = "wireframe";
		meshWireframe.material.mainPass.wireframe = true;
		meshWireframe.material.castShadows = false;
		meshWireframe.material.color.setColor(shapeColor);
		meshWireframe.material.mainPass.setPassName("afterTonemapping");

		var meshIntersection = new h3d.scene.Mesh(prim, null, mesh);
		meshIntersection.name = "intersection";
		meshIntersection.material.castShadows = false;
		meshIntersection.material.blendMode = Alpha;
		meshIntersection.material.mainPass.culling = Front;
		meshIntersection.material.mainPass.depth(false, GreaterEqual);
		meshIntersection.material.color.setColor(intersectionColor);
		meshIntersection.material.mainPass.setPassName("afterTonemapping");

		return mesh;
	}

	public function createAllInteractives() {
		removeAllInteractives();
		for (idx in 0...shapes.length)
			this.interactives[idx] = getInteractive(this.shapes[idx], idx == selectedShapeIdx, rootDebugObj);
	}

	public function removeAllInteractives() {
		for (i in this.interactives)
			i.remove();
		this.interactives = [];
	}

	function updateShapeList() {
		var list = element.find("#shape-list");
		list.empty();

		for (idx => s in shapes) {
			var el = new Element('<div class="shape-list-entry ${idx == selectedShapeIdx ? "selected" : ""}">${s.getName()}</div>');

			el.on("click", function() {
				var interactive = interactives[selectedShapeIdx];
				var interactiveMaterial = interactive?.material;
				var intersectionMaterial = cast (interactive?.getObjectByName("intersection"), h3d.scene.Mesh)?.material;
				if (selectedShapeIdx != -1) {
					interactiveMaterial.color.setColor(DEFAULT_COLOR);
					intersectionMaterial.color.setColor(INTERSECTION_COLOR);
				}

				selectedShapeIdx = idx;

				interactive = interactives[selectedShapeIdx];
				interactiveMaterial = interactive.material;
				intersectionMaterial = cast (interactive.getObjectByName("intersection"), h3d.scene.Mesh).material;

				list.find(".selected").removeClass("selected");
				el.addClass("selected");
				inspect(s);
				gizmo?.setTransform(interactives[selectedShapeIdx].getAbsPos());
				interactiveMaterial.color.setColor(SELECTED_COLOR);
				intersectionMaterial.color.setColor(SELECTED_INTERSECTION_COLOR);
			});

			el.appendTo(list);
		}
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

	function getDefaultShape(shape : Shape) : Shape {
		return switch (shape) {
			case Box(_):
				Box(new h3d.col.Point(0, 0, 0), new h3d.Vector(0, 0, 0), 1., 1., 1.);
			case Sphere(_):
				Sphere(new h3d.col.Point(0, 0, 0), 1.);
			case Capsule(_):
				Capsule(new h3d.col.Point(0, 0, 0), new h3d.Vector(0, 0, 0), 1., 1.);
			case Cylinder(_):
				Cylinder(new h3d.col.Point(0, 0, 0), new h3d.Vector(0, 0, 0), 1., 1.);
		}
	}

	function set_rootDebugObj(v : h3d.scene.Object) {
		this.rootDebugObj = v;
		if (interactives.length > 0) {
			removeAllInteractives();
			createAllInteractives();
		}
		return this.rootDebugObj;
	}
}

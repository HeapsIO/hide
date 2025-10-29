package hide.comp;

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
	static var DEFAULT_COLOR = 0xFFFFFF;
	static var SELECTED_COLOR = 0x3185CE;

	var parentObj : h3d.scene.Object;
	var shapes : Array<Shape> = [];

	var interactives : Array<h3d.scene.Mesh> = [];
	var selectedShapeIdx : Int = -1;
	var isInShapeEdition = false;
	var gizmo : hrt.tools.Gizmo;
	var scene : Scene;

	public function new(scene : Scene, parentObj : h3d.scene.Object, ?shapes : Array<Shape>, ?options : ShapeEditorOptions, ?parent: Element) {
		this.scene = scene;
		this.parentObj = parentObj;
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

		element.find("#btn-add").on("click", function() {
			var prevShapes = this.shapes.copy();
			this.shapes.push(Box(new h3d.col.Point(0, 0, 0), new h3d.Vector(0, 0, 0), 1, 1, 1));
			updateShapeList();
			var newShapes = this.shapes.copy();
			var i = getInteractive(this.shapes[this.shapes.length - 1]);
			interactives.push(i);
			registerUndo(prevShapes, newShapes);
			onChange();
		});

		element.find("#btn-remove").on("click", function() {
			var prevShapes = this.shapes.copy();
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
			var newShapes = this.shapes.copy();
			registerUndo(prevShapes, newShapes);

			selectedShapeIdx = -1;
			uninspect();
			updateShapeList();
			onChange();
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

		var offsetPosition = new h3d.Vector(0, 0, 0);
		var offsetRotation = new h3d.Quat();
		var offsetScale = new h3d.Vector(0, 0, 0);

		var initialShape = this.shapes[selectedShapeIdx];
		var initialAbsPos = new h3d.Matrix();

		@:privateAccess scene.editor.showGizmo = false;
		gizmo = new hrt.tools.Gizmo(scene.s3d, scene.s2d);
		gizmo.allowNegativeScale = true;
		gizmo.setTransform(this.interactives[selectedShapeIdx].getAbsPos());
		gizmo.onStartMove = function(mode : hrt.tools.Gizmo.TransformMode) {
			offsetPosition.set(0, 0, 0);
			offsetRotation.identity();
			offsetScale.set(1, 1, 1);

			initialShape = shapes[selectedShapeIdx];
			initialAbsPos.load(interactives[selectedShapeIdx].getAbsPos());
			gizmo.setTransform(initialAbsPos);
		}

		gizmo.onMove = function(position: h3d.Vector, rotation: h3d.Quat, scale: h3d.Vector) {
			var interactive = interactives[selectedShapeIdx];
			var absPos = initialAbsPos.clone();

			if (position != null)
				offsetPosition.load(position);

			if (rotation != null)
				offsetRotation.load(rotation);

			if (scale != null)
				offsetScale.load(scale);

			// Update interactive
			switch (initialShape) {
				case Box(center, rotation, x, y, z):
					if (offsetPosition != null)
						absPos.translate(offsetPosition.x, offsetPosition.y, offsetPosition.z);
					if (offsetScale != null) {
						absPos.prependScale(1 / x, 1 / y, 1 / z);
						absPos.prependScale(x + offsetScale.x - 1, y + offsetScale.y - 1, z + offsetScale.z - 1);
					}
					if (offsetRotation != null) {
						var eulers = offsetRotation.toEuler();
						absPos.prependRotation(eulers.x, eulers.y, eulers.z);
					}

				case Sphere(center, radius):
					if (offsetPosition != null)
						absPos.translate(offsetPosition.x, offsetPosition.y, offsetPosition.z);
					if (offsetScale != null) {
						var offsetRadius = offsetScale.x != 1 ? offsetScale.x : offsetScale.y != 1 ? offsetScale.y : offsetScale.z;
						offsetRadius -= 1;
						absPos.prependScale(1 / radius, 1 / radius, 1 / radius);
						absPos.prependScale(radius + offsetRadius, radius + offsetRadius, radius + offsetRadius);
					}

				case Capsule(center, rotation, radius, height):
					if (offsetPosition != null)
						absPos.translate(offsetPosition.x, offsetPosition.y, offsetPosition.z);
					if (offsetScale != null) {
						if (offsetScale.x == offsetScale.y && offsetScale.x == offsetScale.z) {
							var radiusOffset = offsetScale.x == 1 ? offsetScale.y : offsetScale.x;
							radiusOffset -= 1;
							absPos.prependScale(1 / radius, 1 / radius, 1 / height);
							absPos.prependScale(radius + radiusOffset, radius + radiusOffset, height + offsetScale.z - 1);
						}
						else {
							// We need to recreate the capsule prim if scale isn't uniform
							var radiusOffset = offsetScale.x == 1 ? offsetScale.y : offsetScale.x;
							radiusOffset -= 1;
							var newShape = Capsule(center + offsetPosition, rotation + offsetRotation.toEuler(), radius + radiusOffset, height + offsetScale.z - 1);
							shapes[selectedShapeIdx] = newShape;
							interactives[selectedShapeIdx].remove();
							interactives[selectedShapeIdx] = getInteractive(newShape);
						}
					}
					if (offsetRotation != null) {
						var eulers = offsetRotation.toEuler();
						absPos.prependRotation(eulers.x, eulers.y, eulers.z);
					}

				case Cylinder(center, rotation, radius, height):
					if (offsetPosition != null)
						absPos.translate(offsetPosition.x, offsetPosition.y, offsetPosition.z);
					if (offsetScale != null) {
						var radiusOffset = offsetScale.x == 1 ? offsetScale.y : offsetScale.x;
						radiusOffset -= 1;
						absPos.prependScale(1 / radius, 1 / radius, 1 / height);
						absPos.prependScale(radius + radiusOffset, radius + radiusOffset, height + offsetScale.z - 1);
					}
					if (offsetRotation != null) {
						var eulers = offsetRotation.toEuler();
						absPos.prependRotation(eulers.x, eulers.y, eulers.z);
					}

				default:
			}

			@:privateAccess interactive.absPos.load(absPos);
		}

		gizmo.onFinishMove = function() {
			var prevShapes = this.shapes.copy();
			var newShape = switch(shapes[selectedShapeIdx]) {
				case Box(center, rotation, sizeX, sizeY, sizeZ):
					Box(center + offsetPosition, rotation + offsetRotation.toEuler(), sizeX + offsetScale.x - 1, sizeY + offsetScale.y - 1, sizeZ + offsetScale.z - 1);
				case Sphere(center, radius):
					var offsetRadius = offsetScale.x != 1 ? offsetScale.x : offsetScale.y != 1 ? offsetScale.y : offsetScale.z;
					offsetRadius -= 1;
					Sphere(center + offsetPosition, radius + offsetRadius);
				case Capsule(center, rotation, radius, height):
					if (offsetScale.x == offsetScale.y && offsetScale.x == offsetScale.z) {
						var radiusOffset = offsetScale.x == 1 ? offsetScale.y : offsetScale.x;
						radiusOffset -= 1;
						Capsule(center + offsetPosition, rotation + offsetRotation.toEuler(), radius + radiusOffset, height + offsetScale.z - 1);
					}
					else {
						Capsule(center, rotation, radius, height);
					}
				case Cylinder(center, rotation, radius, height):
					var radiusOffset = offsetScale.x == 1 ? offsetScale.y : offsetScale.x;
					radiusOffset -= 1;
					Cylinder(center + offsetPosition, rotation + offsetRotation.toEuler(), radius + radiusOffset, height + offsetScale.z - 1);
			}

			shapes[selectedShapeIdx] = newShape;
			interactives[selectedShapeIdx].remove();
			interactives[selectedShapeIdx] = getInteractive(newShape);
			inspect(newShape);
			onChange();

			var newShapes = this.shapes.copy();
			registerUndo(prevShapes, newShapes);
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
			var prevShapes = this.shapes.copy();
			var selIdx = Std.parseInt(shapeSelect.val());
			if (this.shapes[selectedShapeIdx].getIndex() != selIdx)
				this.shapes[selectedShapeIdx] = getDefaultShape(Shape.createByIndex(selIdx, getExtraParams()));
			else
				this.shapes[selectedShapeIdx] = Shape.createByIndex(selIdx, getExtraParams());

			var newShapes = this.shapes.copy();

			var i = interactives[selectedShapeIdx];
			i.remove();
			interactives[selectedShapeIdx] = getInteractive(this.shapes[selectedShapeIdx]);

			updateShapeList();
			inspect(this.shapes[selectedShapeIdx]);
			onChange();

			scene.editor.properties.undo.change(Custom((undo) -> {
				this.shapes = undo ? prevShapes : newShapes;
				inspect(this.shapes[this.selectedShapeIdx]);
				for (idx in 0...shapes.length) {
					this.interactives[idx].remove();
					this.interactives[idx] = getInteractive(this.shapes[idx]);
				}
				updateShapeList();
				onChange();
			}));
		}

		element.find("#extra-params").empty();
		element.find("#shape-inspector").show();

		shapeSelect.val(shape.getIndex());
		shapeSelect.on("change", updateShape);

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
					<div class="vector"><input type="number" id="x" value="${center.x}"/><input type="number" id="y" value="${center.y}"/><input type="number" id="z" value="${center.z}"/></div>
					<label>Radius</label>
					<div><input type="number" min="0" id="radius" value="$radius"/></div>
				');
				e.find("input").on("change", updateShape);
				e.appendTo(extraParams);

			case Capsule(center, rotation, radius, height), Cylinder(center, rotation, radius, height):
				var e = new Element('
					<label>Center</label>
					<div class="vector"><input type="number" id="x" value="${center.x}"/><input type="number" id="y" value="${center.y}"/><input type="number" id="z" value="${center.z}"/></div>
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


	function getInteractive(shape : Shape) : h3d.scene.Mesh {
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
				var s = new h3d.prim.Sphere(radius);
				offset.load(center);
				s.addNormals();
				s;
			case Capsule(center, rotation, radius, height):
				var c = new h3d.prim.Capsule(radius, height, 8, Z);
				offset.load(center);
				offsetRotation.load(rotation);
				c.addNormals();
				c;
			case Cylinder(center, rotation, radius, height):
				var c = new h3d.prim.Cylinder(16, radius, height, true);
				offset.load(center);
				offsetRotation.load(rotation);
				c.addNormals();
				c;
		}

		var mesh = new h3d.scene.Mesh(prim, null, parentObj);
		mesh.setPosition(offset.x, offset.y, offset.z);
		mesh.setRotation(offsetRotation.x, offsetRotation.y, offsetRotation.z);

		var s = new h3d.shader.AlphaMult();
		s.alpha = 0.3;
		mesh.material.mainPass.addShader(s);
		mesh.material.blendMode = Alpha;

		var fixedColor = new h3d.shader.FixedColor(this.shapes.indexOf(shape) == selectedShapeIdx ? SELECTED_COLOR : DEFAULT_COLOR);
		fixedColor.USE_ALPHA = false;
		@:privateAccess mesh.material.mainPass.addSelfShader(fixedColor);

		mesh.material.mainPass.setPassName("overlay");

		var p = mesh.material.allocPass("highlight");
		p.culling = None;
		p.depthWrite = false;
		p.depthTest = LessEqual;

		return mesh;
	}

	function createAllInteractives() {
		removeAllInteractives();
		for (idx in 0...shapes.length)
			this.interactives[idx] = getInteractive(this.shapes[idx]);
	}

	function removeAllInteractives() {
		for (i in this.interactives)
			i.remove();
		this.interactives = [];
	}


	function registerUndo(prevShapes : Array<Shape>, newShapes : Array<Shape>) {
		scene.editor.properties.undo.change(Custom((undo) -> {
			this.shapes = undo ? prevShapes : newShapes;
			if (this.selectedShapeIdx == -1 || this.selectedShapeIdx >= this.shapes.length)
				uninspect();
			else
				inspect(this.shapes[this.selectedShapeIdx]);
			for (i in this.interactives)
				i.remove();
			this.interactives = [];
			for (idx in 0...shapes.length)
				this.interactives[idx] = getInteractive(this.shapes[idx]);
			if (this.selectedShapeIdx != -1)
				gizmo?.setTransform(this.interactives[this.selectedShapeIdx].getAbsPos());
			updateShapeList();
			onChange();
		}));
	}

	function updateShapeList() {
		var list = element.find("#shape-list");
		list.empty();

		for (idx => s in shapes) {
			var el = new Element('<div class="shape-list-entry ${idx == selectedShapeIdx ? "selected" : ""}">${s.getName()}</div>');

			el.on("click", function() {
				if (selectedShapeIdx != -1)
					interactives[selectedShapeIdx].material.mainPass.getShader(h3d.shader.FixedColor).color.setColor(DEFAULT_COLOR);

				selectedShapeIdx = idx;
				list.find(".selected").removeClass("selected");
				el.addClass("selected");
				inspect(s);
				gizmo?.setTransform(interactives[selectedShapeIdx].getAbsPos());
				interactives[selectedShapeIdx].material.mainPass.getShader(h3d.shader.FixedColor).color.setColor(SELECTED_COLOR);
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
}

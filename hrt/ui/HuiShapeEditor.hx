package hrt.ui;

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

class HuiShapeEditor extends HuiElement {
	static var SRC =
		<hui-shape-editor>
			<hui-element id="shape-list">
			</hui-element>
			<hui-element id="buttons">
				<hui-button id="add-btn"><hui-icon("add")/></hui-button>
				<hui-button id="remove-btn"><hui-icon("remove")/></hui-button>
			</hui-element>
			<hui-element id="shape-inspector">
				<hui-element class="horizontal">
					<hui-text("Shape") class="label"/><hui-select id="shape-select-el" class="value"/>
				</hui-element>
				<hui-element id="edition-el" class="vertical">
					<hui-element class="horizontal">
						<hui-text("Edit Shape") class="label"/><hui-button class="value" id="edit-btn"><hui-icon("edit")/></hui-button>
					</hui-element>
					<hui-element class="horizontal">
						<hui-text("Center") class="label"/>
						<hui-element class="horizontal value group">
							<hui-input-box class="value" id="center-x"/>
							<hui-input-box class="value" id="center-y"/>
							<hui-input-box class="value" id="center-z"/>
						</hui-element>
					</hui-element>
					<hui-element class="horizontal" id="rotationEl">
						<hui-text("Rotation (degrees)") class="label"/>
						<hui-element class="horizontal value group">
							<hui-input-box class="value" id="rot-x"/>
							<hui-input-box class="value" id="rot-y"/>
							<hui-input-box class="value" id="rot-z"/>
						</hui-element>
					</hui-element>
					<hui-element class="horizontal" id="sizeEl">
						<hui-text("Size") class="label"/>
						<hui-element class="horizontal value group">
							<hui-input-box class="value" id="size-x"/>
							<hui-input-box class="value" id="size-y"/>
							<hui-input-box class="value" id="size-z"/>
						</hui-element>
					</hui-element>
					<hui-element class="horizontal">
						<hui-text("Radius") class="label"/><hui-input-box class="value" id="radius-el"/>
					</hui-element>
					<hui-element class="horizontal">
						<hui-text("Height") class="label"/><hui-input-box class="value" id="height-el"/>
					</hui-element>
				</hui-element>
			</hui-element>
		</hui-shape-editor>

	static var DEFAULT_COLOR = 0x55FFFFFF;
	static var SELECTED_COLOR = 0x553185CE;
	static var INTERSECTION_COLOR = 0x55FF0000;
	static var SELECTED_INTERSECTION_COLOR = 0x99FF0000;

	public var rootDebugObj(default, set) : h3d.scene.Object;
	function set_rootDebugObj(v : h3d.scene.Object) {
		this.rootDebugObj = v;
		if (interactives.length > 0) {
			removeAllInteractives();
			createAllInteractives();
		}
		return this.rootDebugObj;
	}

	var shapes : Array<Shape> = [];

	var interactives : Array<h3d.scene.Mesh> = [];
	var selectedShapeIdx : Int = -1;
	var isInShapeEdition = false;
	var gizmo : hrt.tools.Gizmo;

	public function new(rootDebugObj : h3d.scene.Object, ?shapes : Array<Shape>, ?options : ShapeEditorOptions, ?parent) {
		super(parent);
		initComponent();

		gizmo = new hrt.tools.Gizmo(rootDebugObj.getScene());

		registerCommand(hrt.tools.Gizmo.gizmoSwitchModeCommand, View, gizmo.switchMode);
		registerCommand(hrt.tools.Gizmo.gizmoTranslateCommand, View, gizmo.translationMode);
		registerCommand(hrt.tools.Gizmo.gizmoRotateCommand, View, gizmo.rotationMode);
		registerCommand(hrt.tools.Gizmo.gizmoScaleCommand, View, gizmo.scalingMode);

		this.rootDebugObj = rootDebugObj;
		this.shapes = shapes;

		// Set default value if not passed in constructor
		if (this.shapes == null)
			this.shapes = [];

		var allowedShapes = options?.shapesAllowed ?? Type.getEnumConstructs(Shape);
		shapeSelectEl.items = [for (idx => s in allowedShapes) { value: idx, label: '${s}' }];
		shapeSelectEl.value = 0;

		if (options != null && options?.disableShapeEdition)
			editBtn.parent.visible = false;

		addBtn.onClick = (e) -> {
			this.shapes.push(Box(new h3d.col.Point(0, 0, 0), new h3d.Vector(0, 0, 0), 1, 1, 1));
			updateShapeList();
			var i = getInteractive(this.shapes[this.shapes.length - 1], (this.shapes.length - 1) == selectedShapeIdx, rootDebugObj);
			interactives.push(i);
			onChange();
		}

		removeBtn.onClick = (e) -> {
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
		}

		editBtn.onClick = (e) -> {
			if (isInShapeEdition)
				stopShapeEditing();
			else
				startShapeEditing();
		}

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

	override function onRemove() {
		super.onRemove();
		uninspect();
		selectedShapeIdx = -1;
		for (i in interactives)
			i.remove();
	}

	override function sync(ctx) {
		super.sync(ctx);
		gizmo?.update(ctx.elapsedTime);
	}

	public function getValue() : Array<Shape> {
		return this.shapes;
	}

	public dynamic function onChange() {}


	function startShapeEditing() {
		isInShapeEdition = true;
		editBtn.dom.toggleClass("activated", true);

		var lclOffsetPosition = new h3d.Vector(0, 0, 0);
		var lclOffsetRotation = new h3d.Vector(0, 0, 0);
		var lclOffsetScale = new h3d.Vector(0, 0, 0);

		var initialShape = this.shapes[selectedShapeIdx];
		var initialRelPos = new h3d.Matrix();

		gizmo.visible = true;
		gizmo.isLocalTransform = true;
		gizmo.moveToObjects([interactives[selectedShapeIdx]]);
		gizmo.onStartMove = function(_) {
			lclOffsetPosition.set(0, 0, 0);
			lclOffsetRotation.set(0, 0, 0);
			lclOffsetScale.set(1, 1, 1);

			initialShape = shapes[selectedShapeIdx];
			initialRelPos.load(interactives[selectedShapeIdx].getTransform());

			gizmo.moveToObjects([interactives[selectedShapeIdx]]);

			// gizmo.snap = scene.editor.gizmoSnap;
		}

		gizmo.onMove = function(position: h3d.Vector, rotation: h3d.Quat, scale: h3d.Vector) {
			var interactive = interactives[selectedShapeIdx];

			var rel = gizmo.getAbsPos().multiplied(interactive.parent.getAbsPos().getInverse());
			var p = rel.getPosition();
			var r = rel.getEulerAngles();
			interactive.setPosition(p.x, p.y, p.z);
			interactive.setRotation(r.x, r.y, r.z);
			interactive.setScale(1);
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
	}

	function stopShapeEditing() {
		isInShapeEdition = false;
		editBtn.dom.toggleClass("activated", false);

		gizmo.visible = false;
	}

	function inspect(shape : Shape) {
		shapeInspector.visible = true;

		function updateShape() {
			var selIdx = shapeSelectEl.value;
			if (this.shapes[selectedShapeIdx].getIndex() != selIdx)
				this.shapes[selectedShapeIdx] = getDefaultShape(Shape.createByIndex(selIdx, getExtraParams(selIdx)));
			else
				this.shapes[selectedShapeIdx] = Shape.createByIndex(selIdx, getExtraParams(selIdx));

			var i = interactives[selectedShapeIdx];
			i.remove();
			interactives[selectedShapeIdx] = getInteractive(this.shapes[selectedShapeIdx], true, rootDebugObj);

			gizmo?.setTransform(interactives[selectedShapeIdx].getTransform());
			updateShapeList();
			inspect(this.shapes[selectedShapeIdx]);
			onChange();
		}

		shapeSelectEl.value = shape.getIndex();
		shapeSelectEl.onValueChanged = () -> {
			updateShape();
		}

		centerX.onChange = (isTemp) -> { if (isTemp) return; updateShape(); }
		centerY.onChange = (isTemp) -> { if (isTemp) return; updateShape(); }
		centerZ.onChange = (isTemp) -> { if (isTemp) return; updateShape(); }
		rotX.onChange = (isTemp) -> { if (isTemp) return; updateShape(); }
		rotY.onChange = (isTemp) -> { if (isTemp) return; updateShape(); }
		rotZ.onChange = (isTemp) -> { if (isTemp) return; updateShape(); }
		sizeX.onChange = (isTemp) -> { if (isTemp) return; updateShape(); }
		sizeY.onChange = (isTemp) -> { if (isTemp) return; updateShape(); }
		sizeZ.onChange = (isTemp) -> { if (isTemp) return; updateShape(); }
		heightEl.onChange = (isTemp) -> { if (isTemp) return; updateShape(); }
		radiusEl.onChange = (isTemp) -> { if (isTemp) return; updateShape(); }

		switch (shape) {
			case Box(center, rotation, x, y, z):
				centerX.text = '${center.x}';
				centerY.text = '${center.y}';
				centerZ.text = '${center.z}';

				rotationEl.visible = true;
				rotX.text = '${rotation.x}';
				rotY.text = '${rotation.y}';
				rotZ.text = '${rotation.z}';

				sizeEl.visible = true;
				sizeX.text = '${x}';
				sizeY.text = '${y}';
				sizeZ.text = '${z}';

				radiusEl.parent.visible = heightEl.parent.visible = false;

			case Sphere(center, radius):
				centerX.text = '${center.x}';
				centerY.text = '${center.y}';
				centerZ.text = '${center.z}';

				radiusEl.parent.visible = true;
				radiusEl.text = '$radius';

				rotationEl.visible = false;
				sizeEl.visible = false;
				heightEl.parent.visible = false;

			case Capsule(center, rotation, radius, height), Cylinder(center, rotation, radius, height):
				centerX.text = '${center.x}';
				centerY.text = '${center.y}';
				centerZ.text = '${center.z}';

				rotationEl.visible = true;
				rotX.text = '${rotation.x}';
				rotY.text = '${rotation.y}';
				rotZ.text = '${rotation.z}';

				radiusEl.parent.visible = true;
				radiusEl.text = '$radius';

				heightEl.parent.visible = true;
				heightEl.text = '$height';

				sizeEl.visible = false;
		}
	}

	function uninspect() {
		stopShapeEditing();
		shapeInspector.visible = false;
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
		mesh.material.name = "$collider";
		mesh.material.castShadows = false;
		mesh.material.blendMode = Alpha;
		mesh.material.color.setColor(shapeColor);
		mesh.material.mainPass.setPassName("afterTonemapping");

		var meshWireframe = new h3d.scene.Mesh(prim, null, mesh);
		meshWireframe.name = "wireframe";
		meshWireframe.material.name = "$collider";
		meshWireframe.material.mainPass.wireframe = true;
		meshWireframe.material.castShadows = false;
		meshWireframe.material.color.setColor(shapeColor);
		meshWireframe.material.mainPass.setPassName("afterTonemapping");

		var meshIntersection = new h3d.scene.Mesh(prim, null, mesh);
		meshIntersection.name = "intersection";
		meshIntersection.material.name = "$collider";
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
		shapeList.removeChildren();

		for (idx => s in shapes) {
			var shapeEl = new HuiElement(shapeList);
			shapeEl.dom.addClass("shape-list-entry");
			shapeEl.dom.toggleClass("selected", idx == selectedShapeIdx);
			new HuiText(s.getName(), shapeEl);

			shapeEl.onClick = (e) -> {
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

				for (e in shapeList.children)
					e.dom.toggleClass("selected", false);
				shapeEl.dom.addClass("selected");
				inspect(s);
				gizmo?.setTransform(interactives[selectedShapeIdx].getAbsPos());
				interactiveMaterial.color.setColor(SELECTED_COLOR);
				intersectionMaterial.color.setColor(SELECTED_INTERSECTION_COLOR);

				if (e.button == 1) {
					uiBase.contextMenu([{ label : "Clone", click: () -> {
						shapes.insert(selectedShapeIdx, shapes[selectedShapeIdx]);
						updateShapeList();
						var i = getInteractive(this.shapes[selectedShapeIdx], true, rootDebugObj);
						interactives.push(i);
						onChange();
					} }]);
				}
			}
		}
	}

	function getExtraParams(idx : Int) : Array<Dynamic> {
		switch (idx) {
			case 0:
				return [new h3d.Vector(Std.parseFloat(centerX.text), Std.parseFloat(centerY.text), Std.parseFloat(centerZ.text)),
				new h3d.Vector(Std.parseFloat(rotX.text), Std.parseFloat(rotY.text), Std.parseFloat(rotZ.text)),
				Std.parseFloat(sizeX.text), Std.parseFloat(sizeY.text), Std.parseFloat(sizeZ.text)];
			case 1:
				return [new h3d.Vector(Std.parseFloat(centerX.text), Std.parseFloat(centerY.text), Std.parseFloat(centerZ.text)),
				Std.parseFloat(radiusEl.text)];
			case 2, 3:
				return [new h3d.Vector(Std.parseFloat(centerX.text), Std.parseFloat(centerY.text), Std.parseFloat(centerZ.text)),
				new h3d.Vector(Std.parseFloat(rotX.text), Std.parseFloat(rotY.text), Std.parseFloat(rotZ.text)),
				Std.parseFloat(radiusEl.text),
				Std.parseFloat(heightEl.text)];
			default:
				throw "Not a known shape index";
		}
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

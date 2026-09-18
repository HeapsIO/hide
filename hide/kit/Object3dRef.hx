package hide.kit;

#if domkit

/**
	Allow the user to reference an object in the h3d scene
**/
class Object3dRef extends Widget<String> {

	/**
		Optional filter to remove certains object from the scene
	**/
	var filter: (h3d.scene.Object) -> Bool = null;

	/**
		Include joints in parts list
	**/
	var joints: Bool = true;


	#if js
	var select: NativeElement;
	var text: NativeElement;
	var dropdown = null;
	#elseif hui
	var select: hrt.ui.HuiSelect;
	#end

	function makeInput():NativeElement {
		#if js
		function valueChanged(newValue: String) {
			value = newValue;
			broadcastValueChange(false);
		}

		select = js.Browser.document.createElement("kit-select");
		text = js.Browser.document.createSpanElement();
		select.addChild(text);

		var entries = getNamedObjects();

		select.get().onclick = (e: js.html.MouseEvent) -> {
			var selectEntries: Array<hide.comp.ContextMenu.MenuItem> = [for (i => entry in entries) {label: entry.label, click: valueChanged.bind(entry.value)}];
			if (dropdown == null) {
				dropdown = hide.comp.ContextMenu.createDropdown(select, selectEntries);
				dropdown.onClose = () -> {
					dropdown = null;
				}
			} else {
				dropdown.close();
			}
		}

		hide.tools.DragAndDrop.makeDropTarget(select, (event: hide.tools.DragAndDrop.DropEvent, data: hide.tools.DragAndDrop.DragData) -> {
			switch(event) {
				case Enter, Move, Leave:
					if (data.data.get("drag/scenetree") != null)
						data.dropTargetValidity = AllowDrop;
					select.toggleClass("fancy-drag-drop-target", event != Leave);
				case Drop: {
					var objects : Array<hrt.prefab.Prefab> = cast data.data.get("drag/scenetree");
					if (objects == null || objects.length == 0)
						return;

					var object3d = objects[0].findFirstLocal3d();
					var name = "";
					while (object3d != null && object3d != @:privateAccess root.prefab.shared.root3d) {
						if (name.length > 0)
							name = "." + name ;
						name = object3d.name + name;
						object3d = object3d.parent;
					}

					if (@:privateAccess root.prefab.locateObject(name) != objects[0].findFirstLocal3d()) {
						root.editor.quickError("Fail");
					} else {
						value = name;
						broadcastValueChange(false);
					}
				}

			}
		});

		return select;
		#elseif hui
		select = new hrt.ui.HuiSelect();

		var options = getNamedObjects();

		select.items = options;
		select.onValueChanged = () -> {
			value = select.value;
			broadcastValueChange(false);
		}

		var overlay = new hrt.ui.HuiDropOverlay(select);
		bindDragOperations(select, overlay);

		return select;
		#else
		return null;
		#end
	}

	#if hui
	function validateDrop(op: hrt.ui.HuiDragOp) : Null<hrt.prefab.Prefab> {
		if (op.type == hide.view.Prefab.SCENE_TREE_DRAG_DROP) {
			var prefabs : Array<hrt.prefab.Prefab> = cast op.data;
			if (prefabs.length > 0) {
				return prefabs[0];
			}
		}
		return null;
	}

	public function bindDragOperations(element: hrt.ui.HuiSelect, overlay: hrt.ui.HuiDropOverlay) {
		element.onAnyDragStart = (op: hrt.ui.HuiDragOp) -> {
			if (validateDrop(op) != null) {
				overlay.acceptAny = true;
			}
		}

		element.onAnyDragEnd = (op: hrt.ui.HuiDragOp) -> {
			overlay.reset();
		}

		element.onDragOver = (op:hrt.ui.HuiDragOp) -> {
			if (validateDrop(op) != null) {
				overlay.accept = true;
				op.acceptDrop = true;
			}
		}

		element.onDragOut = (op:hrt.ui.HuiDragOp) -> {
			overlay.accept = false;
		}

		element.onDrop = (op:hrt.ui.HuiDragOp) -> {
			var prefab = validateDrop(op);
			if (prefab == null)
				return;

			var newName = getUniquerName(prefab);
			var oldName = prefab.name;
			if (prefab.name == newName) {
				newName = null;
			}

			root.change({
				callback: () -> {
					if (newName != null) {
						prefab.name = newName;
						Ide.showInfo('Renamed $oldName to $newName so it could be referenced with an unique name');
					}
					value = prefab.getAbsPath(false, true);					
					changeBehaviorInternal(false);
				},
				sideEffects: (isUndo) -> {
					if (newName != null) {
						prefab.name = isUndo ? oldName : newName;
						prefab.updateInstance();
						root.editor.rebuildTree(prefab);
					}
				},
				isTemporaryEdit: false,
				recordUndo: true,
			});
		}
	}

	/**
		Different than prefab.getUniqueName because prefab.getUniqueName is kinda broken and
		doesn't really ensures that the name is really unique
	**/
	function getUniquerName(prefab: hrt.prefab.Prefab) {
		var name = prefab.name;
		var suffix = 0;
		if (prefab.parent != null) {
			var siblingNames = [for (sibling in prefab.parent.children) if (sibling != prefab) sibling.name => true];
			while(siblingNames.get(name)) {
				suffix ++;
				name = prefab.name + "-" + suffix;
			}
		}
		return name;
	}
	#end

	function stringToValue(str: String) : Null<String> {return value;};

	function getDefaultFallback() : String {return null;};

	override function syncValueUI() {
		#if js
		if (text == null)
			return;
		var label = "--- Select ---";
		if (value != null)
			label = value.split(".").pop();
		text.get().innerText = label;
		#elseif hui
		select.items = getNamedObjects();
		select.value = value;
		#end
	}

	function getNamedObjects() {
		var out = [];

		function formatName(path: Array<String>) {
			var name = "";
			for (p in 0...path.length-1) {
				#if js
				name += "&nbsp;&nbsp;";
				#else
				name += "  ";
				#end
			}
			name += path[path.length-1];
			return name;
		}

		function getJoint(path:Array<String>,j:h3d.anim.Skin.Joint) {
			path.push(j.name);
			out.push({label: formatName(path), value: path.join(".")});
			for( j in j.subs )
				getJoint(path, j);
			path.pop();
		}

		function getRec(path:Array<String>,o:h3d.scene.Object) {
			if (o.name == null) return;
			if (filter != null && !filter(o)) return;
			path.push(o.name);
			out.push({label: formatName(path), value: path.join(".")});
			for( c in o )
				getRec(path, c);
			var sk = Std.downcast(o, h3d.scene.Skin);
			if( sk != null && joints) {
				var j = sk.getSkinData();
				for( j in j.rootJoints )
					getJoint(path, j);
			}
			path.pop();
		}

		for( o in root.editor.getRootObjects3d())
			getRec([], o);

		return out;
	}
}

#end
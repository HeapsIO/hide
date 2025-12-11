package hrt.prefab.l3d;

class Constraint extends Prefab {

	@:s public var object(default,null) : String;
	@:s public var target(default,null) : String;
	@:s public var positionOnly(default,null) : Bool;

	public function apply(root : h3d.scene.Object) : Bool {
		var binds = getBindedObjects(root);
		if( binds.object != null && binds.target != null ){
			#if editor
			var p = binds.target;
			while(p != null) {
				if (p == binds.object) {
					target = null;
					return false;
				}
				p = p.follow ?? p.parent;
			}
			#end
			binds.object.follow = binds.target;
			binds.object.followPositionOnly = positionOnly;
		}
		return true;
	}

	function getBindedObjects(root : h3d.scene.Object) : { object : h3d.scene.Object, target : h3d.scene.Object } {
		var res = { object : null, target : null };
		if (object != null)
			res.object = root.getObjectByName(object.split(".").pop());
		if (target != null)
				res.target = root.getObjectByName(target.split(".").pop());
		return res;
	}

	override function makeInstance() {
		apply(shared.root3d);
	}

	override function edit2(ctx: hrt.prefab.EditContext2) {
		function checkLoop(_:Bool) {
			var curObj = getRoot().locateObject(object);
			if( curObj != null ) curObj.follow = null;
			if (!apply(shared.root3d)) {
				ctx.quickError("Loop detected in constraints");
				ctx.rebuildInspector();
			}

			ctx.rebuildTree(this);
		}

		ctx.build(
			<category("Constraint")>
				<object-3d-ref field={object} onValueChange={checkLoop}/>
				<object-3d-ref field={target} onValueChange={checkLoop}/>
				<checkbox field={positionOnly}/>
			</category>
		);
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return {
			icon : "lock",
			name : "Constraint",
			applyTreeStyle: (p : hrt.prefab.Prefab, element : js.html.Element) -> {
				var binds = getBindedObjects(shared.root3d);
				if (binds.object != null && binds.target != null) {
					element.classList.remove("warning");
					element.title = this.name;
					return;
				}
				element.classList.add("warning");
				element.title = "Constraint should have 2 objects binded to work!";
			}
		};
	}

	override function edit(ctx:hide.prefab.EditContext) {
		var curObj = getRoot().locateObject(object);
		var props = ctx.properties.add(new hide.Element('
			<dl>
				<dt title="Object to constraint">Object</dt><dd><select field="object"><option value="">-- Choose --</option></select>
				<dt title="Destination object or joint to constraint to">Target</dt><dd><select field="target"><option value="">-- Choose --</option></select>
				<dt>Position Only</dt><dd><input type="checkbox" field="positionOnly"/></dd>
			</dl>
		'),this, function(_) {
			if( curObj != null ) curObj.follow = null;
			if (!apply(shared.root3d)) {
				hide.Ide.inst.quickError("Loop detected in constraints");
				ctx.rebuildProperties();
			}
			curObj = getRoot().locateObject(object);

			var itemData = @:privateAccess ctx.scene.editor.sceneTree.getTreeItemData(this);
			if (itemData != null)
				@:privateAccess ctx.scene.editor.sceneTree.applyStyle(this, itemData.element);
		});

		for( select in [props.find("[field=object]"), props.find("[field=target]")] ) {
			for( path in ctx.getNamedObjects() ) {
				var parts = path.split(".");
				var opt = new hide.Element("<option>").attr("value", path).html([for( p in 1...parts.length ) "&nbsp; "].join("") + parts.pop());
				select.append(opt);
			}
			select.val(Reflect.field(this, select.attr("field")));
		}
	}
	#end

	static var _ = Prefab.register("constraint", Constraint);

}
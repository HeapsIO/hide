package hrt.prefab2.l3d;

class Constraint extends Prefab {

	@:s public var object(default,null) : String;
	@:s public var target(default,null) : String;
	@:s public var positionOnly(default,null) : Bool;

	public function apply( root : h3d.scene.Object ) {
		var srcObj = root.getObjectByName(object.split(".").pop());
		var targetObj = root.getObjectByName(target.split(".").pop());
		if( srcObj != null && targetObj != null ){
			srcObj.follow = targetObj;
			srcObj.followPositionOnly = positionOnly;
		}
		return srcObj;
	}

	override function makeInstance(ctx: hrt.prefab2.Prefab.InstanciateParams) {
		if(!enabled) return;
		var srcObj = locateObject(object);
		var targetObj = locateObject(target);
		if( srcObj != null && targetObj != null ){
			srcObj.follow = targetObj;
			srcObj.followPositionOnly = positionOnly;
		}
	}

	#if editor
	override function getHideProps() : hide.prefab2.HideProps {
		return { icon : "lock", name : "Constraint" };
	}

	override function edit(ctx:hide.prefab2.EditContext) {
		var curObj = getRoot().locateObject(object);
		var props = ctx.properties.add(new hide.Element('
			<dl>
				<dt title="Object to constraint">Object</dt><dd><select field="object"><option value="">-- Choose --</option></select>
				<dt title="Destination object or joint to constraint to">Target</dt><dd><select field="target"><option value="">-- Choose --</option></select>
				<dt>Position Only</dt><dd><input type="checkbox" field="positionOnly"/></dd>
			</dl>
		'),this, function(_) {
			if( curObj != null ) curObj.follow = null;
			make(getRoot());
			curObj = getRoot().locateObject(object);
		});

		for( select in [props.find("[field=object]"), props.find("[field=target]")] ) {
			for( path in ctx.getNamedObjects(getRoot().getLocal3d()) ) {
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
package hide.prefab;

class Model extends Object3D {

	var animation : Null<String>;
	var lockAnimation : Bool = false;

	override function save() {
		var obj : Dynamic = super.save();
		if( animation != null ) obj.animation = animation;
		if( lockAnimation ) obj.lockAnimation = lockAnimation;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		animation = obj.animation;
		lockAnimation = obj.lockAnimation;
	}

	override function makeInstance(ctx:Context):Context {
		if( source == null)
			return super.makeInstance(ctx);
		ctx = ctx.clone(this);
		try {
			var obj = ctx.loadModel(source);
			obj.name = name;
			applyPos(obj);
			ctx.local3d.addChild(obj);
			ctx.local3d = obj;

			if( animation != null )
				obj.playAnimation(ctx.loadAnimation(animation));

			return ctx;
		} catch( e : hxd.res.NotFound ) {
			ctx.onError(e);
		}
		ctx.local3d = new h3d.scene.Object(ctx.local3d);
		ctx.local3d.name = name;
		applyPos(ctx.local3d);
		return ctx;
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		#if editor
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Animation">
				<dl>
					<dt>Animation</dt><dd><select><option value="">-- Choose --</option></select>
					<dt title="Don\'t save animation changes">Lock</dt><dd><input type="checkbox" field="lockAnimation"></select>
				</dl>
			</div>
		'),this);

		var select = props.find("select");
		var anims = ctx.scene.listAnims(source);
		for( a in anims )
			new hide.Element('<option>').attr("value", ctx.ide.makeRelative(a)).text(ctx.scene.animationName(a)).appendTo(select);
		if( animation != null )
			select.val(animation);
		select.change(function(_) {
			var v = select.val();
			var prev = animation;
			var obj = ctx.getContext(this).local3d;
			if( v == "" ) {
				animation = null;
				obj.stopAnimation();
			} else {
				obj.playAnimation(ctx.rootContext.loadAnimation(v)).loop = true;
				if( lockAnimation ) return;
				animation = v;
			}
			var newValue = animation;
			ctx.properties.undo.change(Custom(function(undo) {
				var obj = ctx.getContext(this).local3d;
				animation = undo ? prev : newValue;
				if( animation == null ) {
					obj.stopAnimation();
					select.val("");
				} else {
					obj.playAnimation(ctx.rootContext.loadAnimation(animation)).loop = true;
					select.val(v);
				}
			}));
		});
		#end
	}

	override function getHideProps() {
		return { icon : "cube", name : "Model", fileSource : ["fbx","hmd"] };
	}

	static var _ = Library.register("model", Model);

}
package hide.prefab;

class Settings extends Prefab {

	var modelType : String;
	var ignoredFields : Array<String> = [];
	public var data : Dynamic = {};

	override function save() {
		var o = Reflect.copy(data);
		o.modelType = modelType;
		if( ignoredFields.length > 0 )
			o.ignoredFields = ignoredFields;
		return o;
	}

	override function load( o : Dynamic ) {
		this.data = o;
		modelType = o.modelType;
		ignoredFields = o.ignoredFields;
		if( ignoredFields == null ) ignoredFields = [];
		Reflect.deleteField(o, "modelType");
		Reflect.deleteField(o, "ignoredFields");
	}

	override function getHideProps() : HideProps {
		return { icon : "cogs", name : "Settings" };
	}

	override function edit( ctx : EditContext ) {
		#if editor
		var props = ctx.properties.add(new hide.Element('
			<dl>
				<dt>Model</dt><dd><select><option value="">-- Choose --</option></select>
			</dl>
			<br/>
		'),this);
		var select = props.find("select");
		var models = ctx.ide.typesCache.getModels();
		for( m in models )
			new hide.Element('<option>').attr("value", m.id).text(ctx.ide.typesCache.getModelName(m)).appendTo(select);
		var modelDef = null;
		if( modelType != null ) {
			modelDef = ctx.ide.typesCache.get(modelType, true);
			if( modelDef == null )
				new hide.Element('<option>').attr("value", modelType).text("?"+modelType).appendTo(select);
			select.val(modelType);
		}
		select.change(function(_) {
			var prev = save();
			var type = select.val();
			load({ modelType : type });
			ctx.rebuild();
			ctx.properties.undo.change(Custom(function(undo) {
				if( undo )
					load(prev);
				else
					load({ modelType : type });
				ctx.rebuild();
			}));
		});

		if( modelDef == null ) {
			ctx.properties.add(new hide.Element('$modelType was not found in source definitions'));
			return;
		}

		var fields = Reflect.fields(data);
		fields.remove("type");
		fields.remove("modelType");
		fields.remove("ignoredFields");
		var changed = false;
		for( f in modelDef.fields )
			if( !fields.remove(f.name) ) {
				if( f.def == null ) continue;
				changed = true;
				Reflect.setField(data, f.name, f.def);
			}
		for( f in fields ) {
			changed = true;
			Reflect.deleteField(data, f);
		}
		if( changed )
			ctx.view.modified = true;

		ctx.properties.addProps(modelDef.fields, this.data);
		var rebuild = ctx.rebuild;
		ctx.ide.typesCache.watch(rebuild);
		ctx.cleanups.push(ctx.ide.typesCache.unwatch.bind(rebuild));
		#end
	}

	static var _ = Library.register("settings", Settings);

}
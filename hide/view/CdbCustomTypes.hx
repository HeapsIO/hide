package hide.view;

class CdbCustomTypes extends hide.ui.View<{}> {

	var script : hide.comp.CodeEditor;
	var types : Array<cdb.Data.CustomType>;
	var modified(default, set) : Bool;

	override function onDisplay() {
		element.addClass("script-editor");

		var tl = [];
		for( t in ide.database.getCustomTypes() )
			tl.push("enum " + t.name + " {\n" + ide.database.typeCasesToString(t, "\t") + "\n}");

		var typesStr = tl.join("\n\n");
		script = new hide.comp.CodeEditor(typesStr, "hx", element);
		script.onSave = function() {
			if( !modified ) return;
			if( types == null ) {
				ide.error("Can't save with errors");
				return;
			}

			var base = ide.database;
			var tpairs = base.makePairs(base.getCustomTypes(), types);
			// check if we can remove some types used in sheets
			for( p in tpairs )
				if( p.b == null ) {
					var t = p.a;
					for( s in base.sheets )
						for( c in s.columns )
							switch( c.type ) {
							case TCustom(name) if( name == t.name ):
								ide.error("Type "+name+" used by " + s.name + "@" + c.name+" cannot be removed");
								return;
							default:
							}
				}
			// add new types
			for( t in types )
				if( !Lambda.exists(tpairs,function(p) return p.b == t) )
					base.getCustomTypes().push(t);
			// update existing types
			for( p in tpairs ) {
				if( p.b == null )
					base.getCustomTypes().remove(p.a);
				else
					try base.updateType(p.a, p.b) catch( msg : String ) {
						ide.error("Error while updating " + p.b.name + " : " + msg);
						return;
					}
			}
			base.sync();

			// full rebuild
			modified = false;
			types = null;
			rebuild();
			ide.saveDatabase();
		};
		script.onChanged = function() {
			var nstr = script.code;
			script.clearError();
			var errors = [];
			var base = ide.database;
			var t = StringTools.trim(nstr);
			var r = ~/^enum[ \r\n\t]+([A-Za-z0-9_]+)[ \r\n\t]*\{([^}]*)\}/;
			var oldTMap = @:privateAccess base.tmap;
			var descs = [];
			var tmap = new Map();
			@:privateAccess base.tmap = tmap;
			types = [];
			while( r.match(t) ) {
				var name = r.matched(1);
				var desc = r.matched(2);
				if( tmap.get(name) != null )
					errors.push("Duplicate type " + name);
				var td = { name : name, cases : [] } ;
				tmap.set(name, td);
				descs.push(desc);
				types.push(td);
				t = StringTools.trim(r.matchedRight());
			}
			for( t in types ) {
				try
					t.cases = base.parseTypeCases(descs.shift())
				catch( msg : Dynamic )
					errors.push(msg);
			}
			@:privateAccess base.tmap = oldTMap;
			if( t != "" )
				errors.push("Invalid " + StringTools.htmlEscape(t));
			if( errors.length > 0 ) {
				script.setError(errors.join("\n"),1,0,0);
				types = null;
			}
			modified = typesStr != nstr;
		};
	}

	function set_modified(b) {
		if( modified == b )
			return b;
		modified = b;
		syncTitle();
		return b;
	}

	override function getTitle() {
		return "CDB Types" + (modified ?" *" : "");
	}

	static var _ = hide.ui.View.register(CdbCustomTypes);

}
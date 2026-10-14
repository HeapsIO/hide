package hrt.prefab.fx;

typedef ParamDef = {
	> hrt.prefab.Props.PropDef,
	?animate: Bool,
	?instance: Bool,
	?groupName: String
}

class EmitterHelper {
	#if editor
	public static function generateEdit(params : Array<ParamDef>, props : Dynamic, properties : hide.comp.PropsEditor, onChange : (?pname : String) -> Void) {
		var groupNames : Array<String> = [];
		for( p in params )
			if( groupNames.indexOf(p.groupName) < 0 )
				groupNames.push(p.groupName);
		for( gn in groupNames ) {
			var group = new hide.Element('<div class="group" name="$gn"></div>');
			group.append(hide.comp.PropsEditor.makePropsList(params.filter(p -> p.groupName == gn)));
			properties.add(group, props, onChange);
		}
	}
	#end
}

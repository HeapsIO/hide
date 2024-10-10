package hide.tools;

class CdbAccess<T,Kind> {

	public var all(get,never) : cdb.Types.ArrayRead<T>;
	var map : Map<String,T> = [];
	var lines : Array<T>;

	public function new( sheet : String ) {
		lines = hide.Ide.inst.getCDBContent(sheet);
		var s = hide.Ide.inst.database.getSheet(sheet);
		if( s.idCol != null ) {
			for( l in lines ) {
				var id : String = Reflect.field(l, s.idCol.name);
				if( id != null && id != "" )
					map.set(id, l);
			}
		}
	}

	function get_all() : cdb.Types.ArrayRead<T> {
		return lines;
	}

	public function get( kind : Kind ) : T {
		return map.get(cast kind);
	}

}
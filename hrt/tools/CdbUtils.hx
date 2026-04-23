package hrt.tools;

enum PathPart {
	Id(idCol:String, name:String, ?targetCol: String);
	Prop(name: String);
	Line(lineNo:Int, ?targetCol: String);
	Script(lineNo:Int);
}

typedef Path = Array<PathPart>;

class CdbUtils {
	public static function splitPath(rs: {s:Array<{s:cdb.Sheet, c:String, id:Null<String>}>, o:{path:Array<Dynamic>, indexes:Array<Int>}}) {
		var path = [];
		var coords = [];
		for( i in 0...rs.s.length ) {
			var s = rs.s[i];
			var oid = Reflect.field(rs.o.path[i], s.id);
			var idx = rs.o.indexes[i];
			if( oid == null || oid == "" )
				path.push(s.s.name.split("@").pop() + (idx < 0 ? "" : "[" + idx +"]"));
			else {
				path.push(oid);
			}
			if (i == rs.s.length - 1 && s.c != "" && s.c != null) {
				path.push(s.c);
			}
		}
		var coords = [];
		var curIdx = 0;
		while(curIdx < rs.o.indexes.length) {
			var sheet = rs.s[curIdx];
			var isSheet = !sheet.s.props.isProps;
			if (isSheet) {
				var oid = Reflect.field(rs.o.path[curIdx], sheet.id);
				var next = sheet.c;
				if (oid != null) {
					coords.push(Id(sheet.id, oid, next));
				}
				else {
					coords.push(Line(rs.o.indexes[curIdx], next));
				}
			}
			else {
				coords.push(Prop(rs.s[curIdx].c));
			}

			curIdx += 1;
		}

		return {pathNames: path, pathParts: coords};
	}
}
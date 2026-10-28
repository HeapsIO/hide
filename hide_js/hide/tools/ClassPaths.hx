package hide.tools;

class ClassPaths {

	/**
		Absolute class paths of the compilation, longest first, lower case with `/` separators and a trailing `/`.
	**/
	public static macro function get() {
		var paths = [];
		for( cp in haxe.macro.Context.getClassPath() ) {
			var dir = cp == "" ? "." : cp;
			if( !sys.FileSystem.exists(dir) )
				continue;
			var p = sys.FileSystem.fullPath(dir).split("\\").join("/").toLowerCase();
			paths.push(StringTools.endsWith(p, "/") ? p : p + "/");
		}

		paths.sort((a, b) -> b.length - a.length);
		return macro $v{paths};
	}
}

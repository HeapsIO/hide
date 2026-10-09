package hlemu;

/** HL String methods used by native code (calls are redirected here by hlemu.Macros) **/
class StringExt {
	/** null-terminated UTF-8 copy in native memory. Like small GC allocations in HL, it is never freed. **/
	public static function toUtf8( s : Dynamic ) : Dynamic {
		if( js.Syntax.typeof(s) != "string" ) return s.toUtf8();
		var b = haxe.io.Bytes.ofString(s);
		var out = new Bytes(b.length + 1);
		out.blit(0, b, 0, b.length);
		out.setUI8(b.length, 0);
		return out;
	}
}

/**
	Single-precision float, as in HL (StdTypes only defines it for java, hl and cpp).
	A JS number at runtime, 4 bytes in emulated structs.
**/
@:notNull abstract Single(Float) from Float to Float {}

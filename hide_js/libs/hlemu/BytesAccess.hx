package hlemu;

/**
	JS emulation of `hl.BytesAccess<T>` : typed access to an hl.Bytes. Each element type
	generates its own abstract over hlemu.Bytes (see hlemu.Macros.bytesAccess).
**/
@:genericBuild(hlemu.Macros.bytesAccess())
class BytesAccess<T> {}

package dx;

#if macro
import haxe.macro.Expr;

class Dx12Macros {

	/**
		HL passes the address of the caller's `size` local variable : write the result
		back to it after the call.
	**/
	public static function serializeRootSignature( desc : Expr, version : Expr, size : Expr ) : Expr {
		return macro {
			var __size = new hl.Ref<Int>(0);
			var __bytes = @:privateAccess dx.Dx12.serializeRootSignatureRef($desc, $version, __size);
			$size = __size.get();
			__bytes;
		};
	}
}
#end

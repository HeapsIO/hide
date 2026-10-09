// Generates lib/dx/Dx12.hx (JS) from hldx's dx/Dx12.hx (HL).
//
// The API stays identical: only the bodies that use HashLink internals (String.bytes,
// haxe.io.Bytes internals, window handles) are replaced. Every replacement must match
// exactly, so that a change in hldx is noticed.
//
// usage: node native/gen-dx12-hx.js [path/to/hldx] (default : $HASHLINK_SRC/libs/directx)
const fs = require('fs');
const path = require('path');

if( !process.argv[2] && !process.env.HASHLINK_SRC ) throw new Error("HASHLINK_SRC is not set : it must point to the hashlink src directory");
const hldx = process.argv[2] || path.join(process.env.HASHLINK_SRC, 'libs/directx');
const src = path.join(hldx, 'dx/Dx12.hx');
const dst = path.join(__dirname, '../../dx/Dx12.hx');
let s = fs.readFileSync(src, 'utf8').replace(/\r\n/g, '\n');

function rep(from, to) {
	const n = s.split(from).length - 1;
	if (n !== 1) throw new Error(`expected exactly one match (found ${n}) for:\n${from}`);
	s = s.replace(from, () => to);
}

// String -> UTF-16 native copy
rep(`	public inline function setName( name : String ) {
		set_name(@:privateAccess name.bytes);
	}`, `	public inline function setName( name : String ) {
		var b = hl.Bytes.ofUcs2(name);
		set_name(b);
		b.free();
	}`);

// display the emulated swapchain after present
rep(`	public function present( vsync : Bool ) {}`, `	public function present( vsync : Bool ) {
		present_native(vsync);
		dx.Display.present();
	}
	@:hlNative("dx12","command_queue_present")
	function present_native( vsync : Bool ) {}`);

// GPU addresses are JS numbers (exact below 2^53)
rep(`abstract Address(Int64) from Int64 {

	public var value(get,never) : Int64;

	public inline function new( v : Int64 ) {
		this = v;
	}

	inline function get_value() return this;

	public inline function offset( delta : Int ) : Address {
		return cast this + delta;
	}
}`, `abstract Address(hl.I64) {

	public var value(get,never) : Int64;

	public inline function new( v : Int64 ) {
		this = hl.I64.ofInt64(v);
	}

	inline function get_value() return hl.I64.toInt64(this);

	public inline function offset( delta : Int ) : Address {
		return cast ((this : Float) + delta);
	}

	@:from static inline function fromInt64( v : Int64 ) : Address {
		return new Address(v);
	}
}`);

rep(`	public function compile( source : String, profile : String, args : Array<String> ) : haxe.io.Bytes {
		var outLen = 0;
		var nargs = new hl.NativeArray(args.length);
		for( i in 0...args.length )
			nargs[i] = @:privateAccess args[i].bytes;
		/*
			Compiling source can trigger a validation error if DXCOMPILER.DLL is missing
		*/
		var bytes = do_compile(cast this, @:privateAccess source.bytes, @:privateAccess profile.bytes, nargs, outLen);
		return @:privateAccess new haxe.io.Bytes(bytes, outLen);
	}`, `	public function compile( source : String, profile : String, args : Array<String> ) : haxe.io.Bytes {
		var outLen = new hl.Ref<Int>(0);
		var nargs = new hl.NativeArray<hl.Bytes>(args.length);
		for( i in 0...args.length )
			nargs[i] = hl.Bytes.ofUcs2(args[i]);
		var src = hl.Bytes.ofUcs2(source), prof = hl.Bytes.ofUcs2(profile);
		function free() {
			src.free();
			prof.free();
			for( b in nargs ) b.free();
		}
		/*
			Compiling source can trigger a validation error if DXCOMPILER.DLL is missing
		*/
		var bytes = try do_compile(cast this, src, prof, nargs, outLen) catch( e : Dynamic ) { free(); throw e; }
		free();
		var out = bytes.toBytes(outLen.get());
		bytes.free();
		return out;
	}`);

rep(`	public static function create( win : Window, flags : DriverInitFlags, ?deviceName : String ) {
		return dxCreate(@:privateAccess win.win, flags, deviceName == null ? null : @:privateAccess deviceName.bytes);
	}`, `	public static function create( win : Window, flags : DriverInitFlags, ?deviceName : String ) {
		// no name : the high performance GPU, as Chromium takes it (force_high_performance_gpu) to share the back buffers
		// (an addon older than the package, a client not updated yet, has no js_high_performance_device : the default GPU)
		if( deviceName == null && js.Syntax.code("typeof __dx12.js_high_performance_device == 'function'") ) {
			var index : Int = js.Syntax.code("__dx12.js_high_performance_device()");
			if( index >= 0 ) deviceName = listDevices()[index];
		}
		var name = hl.Bytes.ofUcs2(deviceName);
		var d = dxCreate(null, flags, name);
		if( name != null ) name.free();
		dx.Display.init(win);
		return d;
	}`);

rep(`	public static function resize( directQueue : CommandQueue, width : Int, height : Int, bufferCount : Int, format : DxgiFormat ) {
	}`, `	public static function resize( directQueue : CommandQueue, width : Int, height : Int, bufferCount : Int, format : DxgiFormat ) {
		resizeNative(directQueue, width, height, bufferCount, format);
		dx.Display.resize(width, height);
	}

	@:hlNative("dx12", "resize")
	static function resizeNative( directQueue : CommandQueue, width : Int, height : Int, bufferCount : Int, format : DxgiFormat ) {
	}`);

// see Dx12Macros : JS can't take the address of the size local variable
rep(`	public static function serializeRootSignature( desc : RootSignatureDesc, version : Int, size : hl.Ref<Int> ) : hl.Bytes {
		return null;
	}`, `	public static macro function serializeRootSignature( desc, version, size ) {
		return dx.Dx12Macros.serializeRootSignature(desc, version, size);
	}

	@:hlNative("dx12", "serialize_root_signature")
	static function serializeRootSignatureRef( desc : RootSignatureDesc, version : Int, size : hl.Ref<Int> ) : hl.Bytes {
		return null;
	}`);

// device names are malloc'ed UTF-16 strings
rep(`		return @:privateAccess String.fromUCS2(dxGetDeviceName());`, `		return dxGetDeviceName().toUcs2();`);
rep(`			out.push(@:privateAccess String.fromUCS2(arr[i]));`, `			out.push(arr[i].toUcs2());`);

// GPU crash dumps call back into Haxe : not supported in JS
rep(`	@:hlNative("dx12", "set_gpu_crash_handler")
	public static function setGpuCrashHandler( f : (name : hl.Bytes, bytes : hl.Bytes, size : Int, lastFile : Bool) -> Void ) {
	}`, `	public static function setGpuCrashHandler( f : (name : hl.Bytes, bytes : hl.Bytes, size : Int, lastFile : Bool) -> Void ) {
		return;
	}`);

// the class body is typed in the macro context too (for serializeRootSignature)
rep(`package dx;
`, `package dx;

// GENERATED by jsdx/native/gen-dx12-hx.js from hldx's dx/Dx12.hx : do not edit.
// JS version of the hldx DirectX 12 API, implemented by the dx12 Node-API addon.

#if !macro
`);
s = s.replace(/\n*$/, `

#else

class Dx12 {
	public static macro function serializeRootSignature( desc, version, size ) {
		return dx.Dx12Macros.serializeRootSignature(desc, version, size);
	}
}

#end
`);

// --remap hl:hlemu loses constant type parameters (Haxe 5 preview) : use hlemu directly
s = s.split('hl.Abstract<').join('hlemu.Abstract<');

fs.writeFileSync(dst, s);
console.log('written', dst);

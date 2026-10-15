package dx;

import dx.Dx12;

private class Target {
	public var width : Int;
	public var height : Int;
	public var textures : Array<GpuResource> = [];
	public var imports : Array<Dynamic> = [];
	public var current = -1;
	public function new( width, height ) {
		this.width = width;
		this.height = height;
	}
}

/**
	Displays the scenes in the page : each scene renders into its own texture (see hide.comp.Scene),
	copied into one of the two textures of its canvas shared with Chromium, imported once with
	Electron's sharedTexture module and drawn with WebGPU into the canvas.
**/
class Display {

	static var device : Dynamic;
	static var pipeline : Dynamic;
	static var sampler : Dynamic;
	static var format : String;

	public static function init( tries = 5 ) {
		var gpu : Dynamic = js.Syntax.code("navigator.gpu");
		if( gpu == null ) {
			js.Browser.console.error("DX12 display : no WebGPU in this page, nothing is shown");
			return;
		}
		// the GPU of the addon (Dx12.create) : the shared textures do not cross adapters
		gpu.requestAdapter({ powerPreference : "high-performance" }).then(function( adapter : Dynamic ) {
			// none while the GPU process (re)starts, after a reload of the page : asked again
			if( adapter == null ) {
				if( tries > 1 ) js.Browser.window.setTimeout(() -> init(tries - 1), 200);
				else js.Browser.console.error("DX12 display : no WebGPU adapter, nothing is shown");
				return null;
			}
			return adapter.requestDevice();
		}).then(function( dev : Dynamic ) {
			if( dev == null ) return;
			device = dev;
			format = gpu.getPreferredCanvasFormat();
			var module = device.createShaderModule({ code : "
				struct V { @builtin(position) pos : vec4f, @location(0) uv : vec2f };
				@vertex fn vs( @builtin(vertex_index) i : u32 ) -> V {
					let p = vec2f(f32((i << 1u) & 2u), f32(i & 2u));
					return V(vec4f(p * 2.0 - 1.0, 0.0, 1.0), vec2f(p.x, 1.0 - p.y));
				}
				@group(0) @binding(0) var s : sampler;
				@group(0) @binding(1) var t : texture_external;
				@fragment fn fs( v : V ) -> @location(0) vec4f { return textureSampleBaseClampToEdge(t, s, v.uv); }
			" });
			pipeline = device.createRenderPipeline({
				layout : "auto",
				vertex : { module : module, entryPoint : "vs" },
				fragment : { module : module, entryPoint : "fs", targets : [{ format : format }] },
			});
			sampler = device.createSampler({ magFilter : "nearest", minFilter : "nearest" });
		});
	}

	/** before the present : records the copy of `tex` into a shared texture of the canvas, (re)created when its size changes **/
	public static function copy( canvas : js.html.CanvasElement, tex : h3d.mat.Texture ) {
		var target : Target = (cast canvas).__dxTarget;
		if( target == null || target.width != tex.width || target.height != tex.height ) {
			release(canvas);
			target = new Target(tex.width, tex.height);
			(cast canvas).__dxTarget = target;
			var sharedTexture : Dynamic = js.Syntax.code("require('electron').sharedTexture");
			try {
				for( i in 0...2 ) {
					var res : GpuResource = js.Syntax.code("__dx12.js_shared_texture_create({0}, {1})", tex.width, tex.height);
					target.textures.push(res);
					var handle : Float = js.Syntax.code("__dx12.js_shared_texture_handle({0})", res);
					var buf = new js.lib.DataView(new js.lib.ArrayBuffer(8));
					hlemu.Struct.setNum64(buf, 0, handle);
					var nodeBuf = js.Syntax.code("Buffer.from({0})", buf.buffer);
					target.imports.push(sharedTexture.subtle.importSharedTexture({
						pixelFormat : "rgba",
						codedSize : { width : tex.width, height : tex.height },
						handle : { ntHandle : nodeBuf },
					}));
				}
			} catch( e : Dynamic ) {
				release(canvas);
				js.Lib.rethrow();
			}
		}
		// alternated : the texture Chromium may still be drawing is not overwritten
		target.current = (target.current + 1) % target.textures.length;
		var driver = h3d.impl.DX12Driver.inst;
		@:privateAccess {
			driver.transition(tex.t, COPY_SOURCE);
			driver.flushTransitions();
			var dst = driver.tmp.dstTextureLocation;
			var src = driver.tmp.srcTextureLocation;
			dst.res = target.textures[target.current];
			dst.type = SUBRESOURCE_INDEX;
			dst.subResourceIndex = 0;
			src.res = tex.t.res;
			src.type = SUBRESOURCE_INDEX;
			src.subResourceIndex = 0;
			driver.frame.commandList.copyTextureRegion(dst, 0, 0, 0, src, null);
		}
	}

	static function getContext( canvas : js.html.CanvasElement ) : Dynamic {
		var context : Dynamic = (cast canvas).__dxContext;
		if( context == null ) {
			context = canvas.getContext("webgpu");
			context.configure({ device : device, format : format, alphaMode : "opaque" });
			(cast canvas).__dxContext = context;
		}
		return context;
	}

	/** after the present : draws the last copy into the canvas **/
	public static function draw( canvas : js.html.CanvasElement ) {
		var target : Target = (cast canvas).__dxTarget;
		if( device == null || target == null ) return;
		if( canvas.width != target.width ) canvas.width = target.width;
		if( canvas.height != target.height ) canvas.height = target.height;
		var context = getContext(canvas);
		var frame : Dynamic = target.imports[target.current].getVideoFrame();
		var ext = device.importExternalTexture({ source : frame });
		var bind = device.createBindGroup({ layout : pipeline.getBindGroupLayout(0), entries : [
			{ binding : 0, resource : sampler },
			{ binding : 1, resource : ext },
		] });
		var enc = device.createCommandEncoder();
		var pass = enc.beginRenderPass({ colorAttachments : [{
			view : context.getCurrentTexture().createView(), loadOp : "clear", storeOp : "store", clearValue : [0, 0, 0, 1],
		}] });
		pass.setPipeline(pipeline);
		pass.setBindGroup(0, bind);
		pass.draw(3);
		pass.end();
		device.queue.submit([enc.finish()]);
		frame.close();
	}

	public static function release( canvas : js.html.CanvasElement ) {
		var target : Target = (cast canvas).__dxTarget;
		if( target == null ) return;
		for( t in target.imports ) t.release();
		for( r in target.textures ) js.Syntax.code("__dx12.js_shared_texture_release({0})", r);
		(cast canvas).__dxTarget = null;
	}
}

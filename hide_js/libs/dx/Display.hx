package dx;

/**
	Displays the emulated swapchain in the page : the back buffers are shared textures
	created by the addon, imported once with Electron's sharedTexture module and drawn
	into the window canvas with WebGPU at each present.
**/
class Display {

	static var window : Window;
	static var textures : Array<Dynamic> = [];
	static var device : Dynamic;
	static var context : Dynamic;
	static var pipeline : Dynamic;
	static var sampler : Dynamic;
	static var format : String;
	static var pending = false;

	public static function init( win : Window, tries = 5 ) {
		window = win;
		var gpu : Dynamic = js.Syntax.code("navigator.gpu");
		if( gpu == null ) {
			js.Browser.console.error("DX12 display : no WebGPU in this page, nothing is shown");
			return;
		}
		// the GPU of the addon (Dx12.create) : the shared textures do not cross adapters
		gpu.requestAdapter({ powerPreference : "high-performance" }).then(function( adapter : Dynamic ) {
			// none while the GPU process (re)starts, after a reload of the page : asked again
			if( adapter == null ) {
				if( tries > 1 ) js.Browser.window.setTimeout(() -> init(win, tries - 1), 200);
				else js.Browser.console.error("DX12 display : no WebGPU adapter, nothing is shown");
				return null;
			}
			return adapter.requestDevice();
		}).then(function( dev : Dynamic ) {
			if( dev == null ) return;
			device = dev;
			context = window.canvas.getContext("webgpu");
			format = gpu.getPreferredCanvasFormat();
			context.configure({ device : device, format : format, alphaMode : "opaque" });
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

	/** called after the native resize : (re)imports the back buffers **/
	public static function resize( width : Int, height : Int ) {
		for( t in textures ) t.release();
		textures = [];
		var sharedTexture : Dynamic = js.Syntax.code("require('electron').sharedTexture");
		var count : Int = js.Syntax.code("__dx12.js_back_buffer_count()");
		for( i in 0...count ) {
			var handle : Float = js.Syntax.code("__dx12.js_back_buffer_handle({0})", i);
			var buf = new js.lib.DataView(new js.lib.ArrayBuffer(8));
			hlemu.Struct.setNum64(buf, 0, handle);
			var nodeBuf = js.Syntax.code("Buffer.from({0})", buf.buffer);
			textures.push(sharedTexture.subtle.importSharedTexture({
				pixelFormat : "rgba",
				codedSize : { width : width, height : height },
				handle : { ntHandle : nodeBuf },
			}));
		}
		window.canvas.width = width;
		window.canvas.height = height;
	}

	/** called after the native present : draws the presented buffer into the canvas **/
	public static function present() {
		if( device == null ) return;
		var index : Int = js.Syntax.code("__dx12.js_presented_buffer()");
		var tex = textures[index];
		if( tex == null ) return;
		var frame : Dynamic = tex.getVideoFrame();
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
}

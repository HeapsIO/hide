// Node-API build of hldx's dx12.cpp, compiled unmodified against the hl.h shim.
//
// On top of the original primitives:
// - the swapchain is emulated with shared textures, displayed by the page
//   (resize, get_back_buffer, get_current_back_buffer_index, command_queue_present)
// - js_* : access to the shared back buffers for the page
// - mem_* : raw memory access, used by hlemu.Bytes / structs on the JS side

#include "dx12.cpp"
#include <dxgi1_6.h>

#include <delayimp.h>

hl_type hlt_bytes, hlt_i32, hlt_bool, hlt_dyn, hlt_abstract;

// Electron exports Node-API from its own executable: redirect "node.exe" imports there
static FARPROC WINAPI loadExeHook( unsigned int event, DelayLoadInfo *info ) {
	if( event != dliNotePreLoadLibrary || _stricmp(info->szDll, "node.exe") != 0 ) return nullptr;
	return (FARPROC)GetModuleHandle(nullptr);
}
decltype(__pfnDliNotifyHook2) __pfnDliNotifyHook2 = loadExeHook;

// the pages of the renderer process share the addon : they use the same device

static dx_driver *js_create( HWND window, DriverInitFlag flags, uchar *dev_desc ) {
	if( static_driver && static_driver->device && static_driver->device->GetDeviceRemovedReason() == S_OK )
		return static_driver;
	return HL_NAME(create)(window, flags, dev_desc);
}

static hl_shim::Register js_reg_create("create", hl_shim::wrap<&js_create>());

// ---- swapchain emulation : one per command queue (driver), selected by resize / present

#define JS_MAX_BUFFERS 8

struct js_swapchain {
	ID3D12Device *device; // a queue address can be reused
	int count;
	int index;
	int presented;
	int presentCount;
	ID3D12Resource *buffers[JS_MAX_BUFFERS];
	HANDLE handles[JS_MAX_BUFFERS];
	ID3D12Fence *fence;
	UINT64 fenceValue;
};

static std::map<ID3D12CommandQueue*, js_swapchain> js_swaps;
static js_swapchain *js_cur = NULL;
static HANDLE js_event = NULL;

static void js_release_buffers( js_swapchain *sc ) {
	for( int i = 0; i < sc->count; i++ ) {
		if( sc->buffers[i] ) sc->buffers[i]->Release();
		if( sc->handles[i] ) CloseHandle(sc->handles[i]);
		sc->buffers[i] = NULL;
		sc->handles[i] = NULL;
	}
	sc->count = 0;
}

static js_swapchain *js_select( ID3D12CommandQueue *q ) {
	js_swapchain *sc = &js_swaps[q];
	if( sc->device != static_driver->device ) {
		js_release_buffers(sc);
		if( sc->fence ) sc->fence->Release();
		*sc = {};
		sc->device = static_driver->device;
		sc->presented = -1;
		CHKERR(sc->device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&sc->fence)));
	}
	js_cur = sc;
	return sc;
}

static js_swapchain *js_current() {
	if( js_cur == NULL ) hl_error("no swapchain");
	return js_cur;
}

static void js_resize( ID3D12CommandQueue *directQueue, int width, int height, int buffer_count, DXGI_FORMAT format ) {
	dx_driver *drv = static_driver;
	js_swapchain *sc = js_select(directQueue);
	if( buffer_count > JS_MAX_BUFFERS ) hl_error("too many back buffers");
	js_release_buffers(sc);
	D3D12_HEAP_PROPERTIES heap = {};
	heap.Type = D3D12_HEAP_TYPE_DEFAULT;
	D3D12_RESOURCE_DESC desc = {};
	desc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
	desc.Width = width;
	desc.Height = height;
	desc.DepthOrArraySize = 1;
	desc.MipLevels = 1;
	desc.Format = format;
	desc.SampleDesc.Count = 1;
	// simultaneous access: the texture stays in the COMMON layout (== PRESENT), readable
	// by Chromium's D3D11 device without a cross-API barrier
	desc.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET | D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS;
	for( int i = 0; i < buffer_count; i++ ) {
		CHKERR(drv->device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_SHARED, &desc, D3D12_RESOURCE_STATE_COMMON, NULL, IID_PPV_ARGS(&sc->buffers[i])));
		CHKERR(drv->device->CreateSharedHandle(sc->buffers[i], NULL, GENERIC_ALL, NULL, &sc->handles[i]));
		sc->buffers[i]->SetName(L"JS_BACKBUFFER");
	}
	sc->count = buffer_count;
	sc->index = 0;
	sc->presented = -1;
}

// like IDXGISwapChain::GetBuffer, the caller owns a reference
static ID3D12Resource *js_get_back_buffer( int index ) {
	js_swapchain *sc = js_current();
	if( index < 0 || index >= sc->count ) return NULL;
	sc->buffers[index]->AddRef();
	return sc->buffers[index];
}

static int js_get_current_back_buffer_index() {
	return js_current()->index;
}

// No shared fence with Chromium: wait for the GPU so that the page can display the
// buffer as soon as present returns.
static void js_command_queue_present( ID3D12CommandQueue *q, bool vsync ) {
	js_swapchain *sc = js_select(q);
	if( !js_event ) js_event = CreateEvent(NULL, FALSE, FALSE, NULL);
	CHKERR(q->Signal(sc->fence, ++sc->fenceValue));
	if( sc->fence->GetCompletedValue() < sc->fenceValue ) {
		sc->fence->SetEventOnCompletion(sc->fenceValue, js_event);
		WaitForSingleObject(js_event, INFINITE);
	}
	if( sc->count == 0 ) return;
	sc->presented = sc->index;
	sc->presentCount++;
	sc->index = (sc->index + 1) % sc->count;
}

static hl_shim::Register js_reg_resize("resize", hl_shim::wrap<&js_resize>());
static hl_shim::Register js_reg_get_back_buffer("get_back_buffer", hl_shim::wrap<&js_get_back_buffer>());
static hl_shim::Register js_reg_get_current_back_buffer_index("get_current_back_buffer_index", hl_shim::wrap<&js_get_current_back_buffer_index>());
static hl_shim::Register js_reg_command_queue_present("command_queue_present", hl_shim::wrap<&js_command_queue_present>());

// ---- page access to the back buffers

static int js_back_buffer_count() { return js_current()->count; }
static HANDLE js_back_buffer_handle( int index ) { js_swapchain *sc = js_current(); return index >= 0 && index < sc->count ? sc->handles[index] : NULL; }
static int js_presented_buffer() { return js_current()->presented; }
static int js_present_count() { return js_current()->presentCount; }

// The high performance GPU (as Chromium takes it with force_high_performance_gpu) : its index in
// list_devices (the hardware adapters in the order of DXGI), -1 when it is unknown. The page passes
// its name to the driver, so that the addon and Chromium share their textures on the same GPU.
static int js_high_performance_device() {
	IDXGIFactory6 *factory = NULL;
	if( FAILED(CreateDXGIFactory2(0, IID_PPV_ARGS(&factory))) ) return -1;
	IDXGIAdapter1 *adapter = NULL;
	int found = -1;
	if( SUCCEEDED(factory->EnumAdapterByGpuPreference(0, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE, IID_PPV_ARGS(&adapter))) ) {
		DXGI_ADAPTER_DESC1 best;
		adapter->GetDesc1(&best);
		adapter->Release();
		UINT index = 0;
		int write = 0;
		while( found < 0 && factory->EnumAdapters1(index++, &adapter) != DXGI_ERROR_NOT_FOUND ) {
			DXGI_ADAPTER_DESC1 desc;
			adapter->GetDesc1(&desc);
			if( (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) == 0 ) {
				if( desc.AdapterLuid.LowPart == best.AdapterLuid.LowPart && desc.AdapterLuid.HighPart == best.AdapterLuid.HighPart ) found = write;
				write++;
			}
			adapter->Release();
		}
	}
	factory->Release();
	return found;
}

static hl_shim::Register js_reg_high_performance_device("js_high_performance_device", hl_shim::wrap<&js_high_performance_device>());
static hl_shim::Register js_reg_back_buffer_count("js_back_buffer_count", hl_shim::wrap<&js_back_buffer_count>());
static hl_shim::Register js_reg_back_buffer_handle("js_back_buffer_handle", hl_shim::wrap<&js_back_buffer_handle>());
static hl_shim::Register js_reg_presented_buffer("js_presented_buffer", hl_shim::wrap<&js_presented_buffer>());
static hl_shim::Register js_reg_present_count("js_present_count", hl_shim::wrap<&js_present_count>());

// ---- raw memory

static void *mem_alloc( int size ) { return calloc(1, size > 0 ? size : 1); }
static void mem_free( void *p ) { free(p); }
static void mem_copy( vbyte *dst, vbyte *src, int size ) { memmove(dst, src, size); }
static void mem_fill( vbyte *dst, int value, int size ) { memset(dst, value, size); }
static int mem_get_ui8( vbyte *p ) { return *p; }
static void mem_set_ui8( vbyte *p, int v ) { *p = (vbyte)v; }
static int mem_get_ui16( vbyte *p ) { return *(unsigned short*)p; }
static void mem_set_ui16( vbyte *p, int v ) { *(unsigned short*)p = (unsigned short)v; }
static int mem_get_i32( vbyte *p ) { return *(int*)p; }
static void mem_set_i32( vbyte *p, int v ) { *(int*)p = v; }
static double mem_get_f32( vbyte *p ) { return *(float*)p; }
static void mem_set_f32( vbyte *p, double v ) { *(float*)p = (float)v; }
static double mem_get_f64( vbyte *p ) { return *(double*)p; }
static void mem_set_f64( vbyte *p, double v ) { *(double*)p = v; }
static int64 mem_get_i64( vbyte *p ) { return *(int64*)p; }
static void mem_set_i64( vbyte *p, int64 v ) { *(int64*)p = v; }
static int mem_ustrlen( uchar *p ) { return ustrlen(p); }

#define MEM_PRIM(name) static hl_shim::Register mem_reg_##name(#name, hl_shim::wrap<&name>());
MEM_PRIM(mem_alloc)
MEM_PRIM(mem_free)
MEM_PRIM(mem_copy)
MEM_PRIM(mem_fill)
MEM_PRIM(mem_get_ui8)
MEM_PRIM(mem_set_ui8)
MEM_PRIM(mem_get_ui16)
MEM_PRIM(mem_set_ui16)
MEM_PRIM(mem_get_i32)
MEM_PRIM(mem_set_i32)
MEM_PRIM(mem_get_f32)
MEM_PRIM(mem_set_f32)
MEM_PRIM(mem_get_f64)
MEM_PRIM(mem_set_f64)
MEM_PRIM(mem_get_i64)
MEM_PRIM(mem_set_i64)
MEM_PRIM(mem_ustrlen)

// mem_address(ArrayBuffer | TypedArray | DataView) : native address of the data.
// V8 never moves an ArrayBuffer backing store, the address stays valid while the
// buffer is alive.
static napi_value mem_address( napi_env env, napi_callback_info info ) {
	size_t argc = 1;
	napi_value argv[1];
	napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
	void *data = NULL;
	bool is;
	if( napi_is_arraybuffer(env, argv[0], &is) == napi_ok && is ) {
		size_t len;
		napi_get_arraybuffer_info(env, argv[0], &data, &len);
	} else if( napi_is_typedarray(env, argv[0], &is) == napi_ok && is ) {
		napi_typedarray_type type;
		size_t len, offset;
		napi_value ab;
		napi_get_typedarray_info(env, argv[0], &type, &len, &data, &ab, &offset);
	} else if( napi_is_dataview(env, argv[0], &is) == napi_ok && is ) {
		size_t len, offset;
		napi_value ab;
		napi_get_dataview_info(env, argv[0], &len, &data, &ab, &offset);
	} else {
		napi_throw_type_error(env, nullptr, "mem_address : ArrayBuffer, TypedArray or DataView expected");
		return nullptr;
	}
	return hl_shim::toJs<void*>(env, data);
}
static hl_shim::Register mem_reg_address("mem_address", &mem_address);

// ---- descriptor copies checked against the live heaps
//
// A copy from a released heap (or past the end of one) crashes in the GPU driver and takes the
// tool down. The live heaps are kept with their CPU range : a bad copy throws a JS exception
// instead, and is logged with its JS stack in %TEMP%\hide-dx12.log.

struct js_heap_range { uintptr_t start; size_t bytes; };
static std::map<ID3D12DescriptorHeap*, js_heap_range> js_heaps;
static std::map<uintptr_t, size_t> js_heap_starts;

static ID3D12DescriptorHeap *js_descriptor_heap_create( D3D12_DESCRIPTOR_HEAP_DESC *desc ) {
	ID3D12DescriptorHeap *heap = HL_NAME(descriptor_heap_create)(desc);
	if( heap ) {
		uintptr_t start = heap->GetCPUDescriptorHandleForHeapStart().ptr;
		size_t bytes = (size_t)desc->NumDescriptors * static_driver->device->GetDescriptorHandleIncrementSize(desc->Type);
		js_heaps[heap] = { start, bytes };
		js_heap_starts[start] = bytes;
	}
	return heap;
}

// a JS error, logged with its stack in %TEMP%\hide-dx12.log
static napi_value js_log( napi_env env, const char *msg ) {
	napi_value text, err, stack;
	napi_create_string_utf8(env, msg, NAPI_AUTO_LENGTH, &text);
	napi_create_error(env, nullptr, text, &err);
	char trace[12288] = "";
	size_t len;
	if( napi_get_named_property(env, err, "stack", &stack) == napi_ok )
		napi_get_value_string_utf8(env, stack, trace, sizeof(trace), &len);
	char file[MAX_PATH];
	DWORD n = GetTempPathA(MAX_PATH, file);
	FILE *f = NULL;
	if( n > 0 && n < MAX_PATH - 32 && strcat_s(file, "hide-dx12.log") == 0 && fopen_s(&f, file, "a") == 0 && f ) {
		SYSTEMTIME t;
		GetLocalTime(&t);
		fprintf(f, "%04d-%02d-%02d %02d:%02d:%02d.%03d %s\n\n", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond, t.wMilliseconds, trace);
		fclose(f);
	}
	return err;
}

static napi_value js_resource_release( napi_env env, napi_callback_info info ) {
	size_t argc = 1;
	napi_value argv[1];
	napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
	IUnknown *res = hl_shim::fromJs<IUnknown*>(env, argv[0]);
	if( res == NULL ) return nullptr;
	auto it = js_heaps.find((ID3D12DescriptorHeap*)res);
	if( res->Release() == 0 && it != js_heaps.end() ) {
		if( getenv("GS_DX12_TRACE") ) {
			char msg[160];
			snprintf(msg, sizeof(msg), "heap released 0x%llx (%zu bytes)", (unsigned long long)it->second.start, it->second.bytes);
			js_log(env, msg);
		}
		js_heap_starts.erase(it->second.start);
		js_heaps.erase(it);
	}
	return nullptr;
}

static bool js_heap_contains( uintptr_t p, size_t bytes ) {
	auto it = js_heap_starts.upper_bound(p);
	if( it == js_heap_starts.begin() ) return false;
	--it;
	return p + bytes <= it->first + it->second;
}

static napi_value js_copy_descriptors_simple( napi_env env, napi_callback_info info ) {
	size_t argc = 4;
	napi_value argv[4];
	napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
	int count = hl_shim::fromJs<int>(env, argv[0]);
	D3D12_CPU_DESCRIPTOR_HANDLE dst = hl_shim::fromJs<D3D12_CPU_DESCRIPTOR_HANDLE>(env, argv[1]);
	D3D12_CPU_DESCRIPTOR_HANDLE src = hl_shim::fromJs<D3D12_CPU_DESCRIPTOR_HANDLE>(env, argv[2]);
	D3D12_DESCRIPTOR_HEAP_TYPE type = hl_shim::fromJs<D3D12_DESCRIPTOR_HEAP_TYPE>(env, argv[3]);
	size_t bytes = (size_t)count * static_driver->device->GetDescriptorHandleIncrementSize(type);
	const char *bad = !js_heap_contains(src.ptr, bytes) ? "source" : !js_heap_contains(dst.ptr, bytes) ? "destination" : NULL;
	if( bad == NULL ) {
		static_driver->device->CopyDescriptorsSimple(count, dst, src, type);
		return nullptr;
	}
	char msg[2048];
	int pos = snprintf(msg, sizeof(msg), "copyDescriptorsSimple : the %s is not in a live descriptor heap (%d descriptors of type %d, src 0x%llx, dst 0x%llx)", bad, count, (int)type, (unsigned long long)src.ptr, (unsigned long long)dst.ptr);
	if( getenv("GS_DX12_TRACE") )
		for( auto &h : js_heap_starts )
			if( pos < (int)sizeof(msg) - 64 ) pos += snprintf(msg + pos, sizeof(msg) - pos, "\n  live 0x%llx +%zu", (unsigned long long)h.first, h.second);
	napi_throw(env, js_log(env, msg));
	return nullptr;
}

static hl_shim::Register js_reg_descriptor_heap_create("descriptor_heap_create", hl_shim::wrap<&js_descriptor_heap_create>());
static hl_shim::Register js_reg_resource_release("resource_release", &js_resource_release);
static hl_shim::Register js_reg_copy_descriptors_simple("copy_descriptors_simple", &js_copy_descriptors_simple);

// dxcompiler.dll loads dxil.dll (shader signing) by name, from the executable directory:
// preload it from the addon directory, otherwise unsigned shaders make PSO creation fail
static void js_preload_dxil() {
	HMODULE self = NULL;
	GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCWSTR)&js_preload_dxil, &self);
	wchar_t path[MAX_PATH];
	DWORD len = GetModuleFileNameW(self, path, MAX_PATH);
	while( len > 0 && path[len - 1] != L'\\' && path[len - 1] != L'/' ) len--;
	path[len] = 0;
	wcscat_s(path, L"dxil.dll");
	LoadLibraryW(path);
}

// Windows runs the page thread on the efficiency cores when the window is not in the foreground
// (FBX conversions, shader compilations... more than 1.5x slower) : full speed on the thread loading the addon
static void js_high_qos() {
	THREAD_POWER_THROTTLING_STATE s = {};
	s.Version = THREAD_POWER_THROTTLING_CURRENT_VERSION;
	s.ControlMask = THREAD_POWER_THROTTLING_EXECUTION_SPEED;
	SetThreadInformation(GetCurrentThread(), ThreadPowerThrottling, &s, sizeof(s));
}

NAPI_MODULE_INIT() {
	js_preload_dxil();
	js_high_qos();
	for( auto &p : hl_shim::registry() ) {
		napi_value f;
		napi_create_function(env, p.first.c_str(), NAPI_AUTO_LENGTH, p.second, nullptr, &f);
		napi_set_named_property(env, exports, p.first.c_str(), f);
	}
	return exports;
}

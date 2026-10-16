@echo off
rem Builds bin\jsdx\dx12.node from hldx's dx12.cpp and the heaps natives (mikktspace, meshoptimizer, V-HACD),
rem unmodified, with the hl.h shim.
rem Uses the hashlink "src" directory for the sources (libs\directx, libs\heaps, include) : HASHLINK_SRC, or found from the hashlink haxelib.
rem The shader compiler DLLs (dxcompiler.dll, dxil.dll) are installed in bin\jsdx by setup_jsdx.bat.
rem Requires Visual Studio with the C++ desktop workload (any edition or the Build Tools) and npm (node-api-headers, installed if missing).
setlocal

rem ---- paths and inputs
set ROOT=%~dp0..
set OUT=%~dp0..\..\..\..\bin\jsdx
set NODE_API=%~dp0..\node_modules\node-api-headers
if "%HASHLINK_SRC%"=="" (
	for /f "usebackq delims=" %%i in (`haxelib libpath hashlink`) do set HASHLINK_SRC=%%i..\..
)
set HLDX=%HASHLINK_SRC%\libs\directx
set HLHEAPS=%HASHLINK_SRC%\libs\heaps
set HLINC=%HASHLINK_SRC%\include
if not exist "%HLDX%\dx12.cpp" (
	echo "%HLDX%\dx12.cpp" not found : set HASHLINK_SRC to the hashlink "src" directory, or install the hashlink haxelib from git as in README.md
	exit /b 1
)
rem HIDE keeps dx12.node loaded : the link would fail
if exist "%OUT%\dx12.node" (
	2>nul ( >> "%OUT%\dx12.node" (call ) ) || (
		echo bin\jsdx\dx12.node is in use : close HIDE
		exit /b 1
	)
)
rem npm install runs no "build" script : no loop when called from "npm run build"
if not exist "%NODE_API%" (
	pushd "%ROOT%"
	call npm install || exit /b 1
	popd
)

rem ---- Visual Studio x64 environment (cl, lib, Windows SDK) : latest install with the C++ tools, found by vswhere
set VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
set VS=
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set VS=%%i
if "%VS%"=="" (
	echo Visual Studio with the C++ tools not found
	exit /b 1
)
call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>nul || exit /b 1
cd /d "%ROOT%"
if not exist "%OUT%" mkdir "%OUT%"
if not exist build\obj mkdir build\obj

rem ---- node.lib : import library of the Node-API functions exported by the executable
lib /nologo /def:"%NODE_API%\def\node_api.def" /name:node.exe /machine:x64 /out:build\obj\node.lib || exit /b 1

rem ---- compile and link dx12.node
rem lines : compiler flags, include directories, outputs, sources, linker flags, libraries
rem /Zi /DEBUG : dx12.pdb next to the addon, to read the minidumps of a crash
rem mikkt.c includes the C++ shim : compiled as C++ (/Tp)
rem /DELAYLOAD:node.exe : Node-API is resolved from the Electron executable (hook in dx12js.cpp)
cl /nologo /std:c++17 /O2 /Zi /EHsc /MT /LD /W1 ^
	/Inative /I"%NODE_API%\include" /I"%HLDX%" /I"%HLINC%\mikktspace" /I"%HLINC%\meshoptimizer" /I"%HLINC%\vhacd" ^
	/Fobuild\obj\ /Fdbuild\obj\ /Fe:"%OUT%\dx12.node" ^
	native\dx12js.cpp ^
	/Tp"%HLHEAPS%\mikkt.c" ^
	"%HLHEAPS%\meshoptimizer.cpp" ^
	"%HLHEAPS%\vhacd.cpp" ^
	"%HLINC%\mikktspace\mikktspace.c" ^
	"%HLINC%\meshoptimizer\*.cpp" ^
	/link /DEBUG /OPT:REF /OPT:ICF /IMPLIB:build\obj\dx12.lib /DELAYLOAD:node.exe ^
	build\obj\node.lib d3d12.lib dxgi.lib dxguid.lib dxcompiler.lib delayimp.lib || exit /b 1

echo OK

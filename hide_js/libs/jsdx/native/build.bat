@echo off
rem Builds bin\jsdx\dx12.node from hldx's dx12.cpp and the heaps natives (mikktspace, meshoptimizer, V-HACD),
rem unmodified, with the hl.h shim.
rem Uses HASHLINK_SRC (the hashlink "src" directory) for the sources (libs\directx, libs\heaps, include)
rem and the shader compiler DLLs (dxcompiler.dll, dxil.dll in the hashlink directory).
rem Requires Visual Studio 2026 and "npm install" in hide_js\libs\jsdx (node-api-headers).
setlocal
set ROOT=%~dp0..
set OUT=%~dp0..\..\..\..\bin\jsdx
set NODE_API=%~dp0..\node_modules\node-api-headers
if "%HASHLINK_SRC%"=="" (
	echo HASHLINK_SRC is not set : it must point to the hashlink "src" directory
	exit /b 1
)
set HLDX=%HASHLINK_SRC%\libs\directx
set HLHEAPS=%HASHLINK_SRC%\libs\heaps
set HLINC=%HASHLINK_SRC%\include
set HLBIN=%HASHLINK_SRC%\..
if not exist "%NODE_API%" (
	echo node-api-headers not found : run "npm install" in %ROOT%
	exit /b 1
)
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>nul || exit /b 1
cd /d "%ROOT%"
if not exist "%OUT%" mkdir "%OUT%"
if not exist build\obj mkdir build\obj
lib /nologo /def:"%NODE_API%\def\node_api.def" /name:node.exe /machine:x64 /out:build\obj\node.lib || exit /b 1
rem /Zi /DEBUG : dx12.pdb next to the addon, to read the minidumps of a crash
rem mikkt.c includes the C++ shim : compiled as C++ (/Tp)
cl /nologo /std:c++17 /O2 /Zi /EHsc /MT /LD /W1 /Inative /I"%NODE_API%\include" /I"%HLDX%" /I"%HLINC%\mikktspace" /I"%HLINC%\meshoptimizer" /I"%HLINC%\vhacd" ^
	native\dx12js.cpp /Tp"%HLHEAPS%\mikkt.c" "%HLHEAPS%\meshoptimizer.cpp" "%HLHEAPS%\vhacd.cpp" "%HLINC%\mikktspace\mikktspace.c" "%HLINC%\meshoptimizer\*.cpp" ^
	/Fobuild\obj\ /Fdbuild\obj\ /Fe:"%OUT%\dx12.node" ^
	/link /DEBUG /OPT:REF /OPT:ICF /IMPLIB:build\obj\dx12.lib build\obj\node.lib d3d12.lib dxgi.lib dxguid.lib dxcompiler.lib delayimp.lib /DELAYLOAD:node.exe || exit /b 1
rem the shader compiler DLLs are loaded from the addon directory
copy /y "%HLBIN%\dxcompiler.dll" "%OUT%\" >nul
copy /y "%HLBIN%\dxil.dll" "%OUT%\" >nul
echo OK

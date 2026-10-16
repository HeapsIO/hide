@echo off
rem Runs setup.bat, builds bin\jsdx\dx12.node and installs the shader compiler DLLs in bin\jsdx if missing,
rem then builds HIDE with DirectX 12 (hide_jsdx.hxml).
setlocal
set ROOT=%~dp0
set OUT=%~dp0bin\jsdx
set DXC_URL=https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.8.2505.1/dxc_2025_07_14.zip

call "%ROOT%setup.bat" --no-build || exit /b 1

set DX12=
set DXC=
set MISSING=
if not exist "%OUT%\dx12.node" set DX12=1
if not exist "%OUT%\dxcompiler.dll" set DXC=1
if not exist "%OUT%\dxil.dll" set DXC=1
if defined DX12 echo dx12.node not found in bin\jsdx
if defined DXC echo dxcompiler.dll / dxil.dll not found in bin\jsdx
if defined DX12 set MISSING=1
if defined DXC set MISSING=1
if defined MISSING (
	choice /c yn /m "Finish the setup"
	if errorlevel 2 exit /b 1
)

if defined DX12 (
	call "%ROOT%hide_js\libs\jsdx\native\build.bat" || exit /b 1
)
if defined DXC (
	echo Downloading %DXC_URL%
	%SystemRoot%\System32\curl.exe -fsSL -o "%TEMP%\dxc.zip" "%DXC_URL%" || exit /b 1
	if not exist "%OUT%" mkdir "%OUT%"
	%SystemRoot%\System32\tar.exe -xf "%TEMP%\dxc.zip" -C "%OUT%" --strip-components=2 bin/x64/dxcompiler.dll bin/x64/dxil.dll || exit /b 1
	del "%TEMP%\dxc.zip"
)

pushd "%ROOT%"
haxe hide_jsdx.hxml || exit /b 1
popd
echo OK

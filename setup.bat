@echo off
rem Checks Node.js and Haxe, installs Electron in bin\electron if missing, then builds HIDE (hide.hxml).
rem --no-build : skip the Haxe build
setlocal
set ROOT=%~dp0
set ELECTRON_URL=https://github.com/electron/electron/releases/download/v44.7.0/electron-v44.7.0-win32-x64.zip

where node >nul 2>nul || (
	echo Node.js not found : install it from https://nodejs.org
	exit /b 1
)
where haxe >nul 2>nul || (
	echo Haxe not found : install it from https://haxe.org
	exit /b 1
)

if not exist "%ROOT%bin\electron\electron.exe" (
	echo Electron not found in bin\electron
	choice /c yn /m "Finish the setup"
	if errorlevel 2 exit /b 1
	echo Downloading %ELECTRON_URL%
	%SystemRoot%\System32\curl.exe -fsSL -o "%TEMP%\electron.zip" "%ELECTRON_URL%" || exit /b 1
	if not exist "%ROOT%bin\electron" mkdir "%ROOT%bin\electron"
	%SystemRoot%\System32\tar.exe -xf "%TEMP%\electron.zip" -C "%ROOT%bin\electron" || exit /b 1
	del "%TEMP%\electron.zip"
)

if not "%1"=="--no-build" (
	pushd "%ROOT%"
	haxe hide.hxml || exit /b 1
	popd
)
echo OK

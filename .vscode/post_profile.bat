@echo off
IF NOT "%1"== "" (
	hl %HASHLINK_SRC%/other/haxelib/profiler.hl /u %1
) ELSE (
	hl %HASHLINK_SRC%/other/haxelib/profiler.hl
)
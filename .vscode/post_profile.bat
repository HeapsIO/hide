@echo off
IF NOT "%1"== "" (
	hl hide_hl/tools/profiler.hl /u %1 --collapse-recursion
) ELSE (
	hl hide_hl/tools/profiler.hl --collapse-recursion
)

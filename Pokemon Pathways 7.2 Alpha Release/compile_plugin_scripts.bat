@echo off
setlocal EnableDelayedExpansion
title Multiplayer Plugin - PluginScripts.rxdata Compiler

:: ============================================================
::  compile_plugin_scripts.bat
::  Rebuilds PluginScripts.rxdata with your updated .rb files.
::
::  SETUP:
::   1. Place this .bat in your game root (same folder as Game.exe)
::   2. Place compile_plugin_scripts.py next to this file
::   3. Run this .bat any time you edit a Multiplayer .rb file
::
::  REQUIREMENTS:
::   - Python 3.6+ installed and on PATH  (python.exe accessible)
::   - compile_plugin_scripts.py (included alongside this .bat)
::
::  WHAT IT DOES:
::   - Reads every .rb file from Plugins\Multiplayer\
::   - Recompresses them into PluginScripts.rxdata (in-place)
::   - All other plugins in PluginScripts.rxdata are left untouched
:: ============================================================

echo.
echo  ============================================
echo   Multiplayer Plugin - rxdata Recompiler
echo  ============================================
echo.

:: -- Locate Python --
python --version >nul 2>&1
if errorlevel 1 (
    echo  ERROR: Python not found on PATH.
    echo  Install Python 3 from https://python.org and re-run.
    echo.
    pause
    exit /b 1
)

:: -- Check for the Python script --
if not exist "%~dp0compile_plugin_scripts.py" (
    echo  ERROR: compile_plugin_scripts.py not found next to this .bat
    echo  Make sure both files are in the same folder.
    echo.
    pause
    exit /b 1
)

:: -- Check for PluginScripts.rxdata --
if not exist "E:\Dev-Build-main\Dev-Build-main\Pokemon Pathways 7.2 Alpha Release\Data\PluginScripts.rxdata" (
    echo  ERROR: Data\PluginScripts.rxdata not found.
    echo  Make sure this .bat is in your game root folder.
    echo.
    pause
    exit /b 1
)

:: -- Run the compiler --
echo  Compiling...
echo.
python "%~dp0compile_plugin_scripts.py" "%~dp0"
if errorlevel 1 (
    echo.
    echo  FAILED. See error above.
    pause
    exit /b 1
)

echo.
echo  Done! PluginScripts.rxdata has been updated.
echo  Launch your game to test.
echo.
pause

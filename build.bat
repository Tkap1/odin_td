@echo off
cls

set GAME_RUNNING=false
set EXE=platform.exe

FOR /F %%x IN ('tasklist /NH /FI "IMAGENAME eq %EXE%"') DO IF %%x == %EXE% set GAME_RUNNING=true

if %GAME_RUNNING% == false (
	del /q game_*.dll 2> nul

	if exist "pdbs" (
		del /q pdbs\*.pdb 2> NUL
		del /q pdbs\*.rdi 2> NUL
	) else (
		mkdir pdbs
	)

	echo 0 > pdbs\pdb_number
)

set /p PDB_NUMBER=<pdbs\pdb_number
set /a PDB_NUMBER=%PDB_NUMBER%+1
echo %PDB_NUMBER% > pdbs\pdb_number

set vet=-vet-cast -vet-shadowing -vet-style -vet-tabs -vet-unused -vet-unused-imports -vet-unused-variables

if not exist build mkdir build

pushd build
	echo Building dll...
	odin.exe build ..\game -build-mode:dll -debug -define:RAYLIB_SHARED=true -pdb-name:..\pdbs\game_%PDB_NUMBER%.pdb %vet%
	echo %ERRORLEVEL%
	IF %ERRORLEVEL% NEQ 0 goto end

	if %GAME_RUNNING% == true (
		goto end
	)

	echo Building platform...
	odin.exe build ..\platform -debug
	IF %ERRORLEVEL% NEQ 0 goto end

:end
popd

copy build\platform.exe platform.exe > NUL
copy build\game.dll game.dll > NUL


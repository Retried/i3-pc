@echo off
rem Release build with link-time optimisation, at low priority. Usage: build-lto.bat
setlocal
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set "PATH=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\Llvm\x64\bin;%PATH%"
set "I3_PYTHON_ARG="
if defined PYTHON3_EXECUTABLE (
  "%PYTHON3_EXECUTABLE%" -c "import sys; sys.exit(0 if sys.version_info.major == 3 else 1)" >nul 2>&1
  if errorlevel 1 (
    echo ERROR: PYTHON3_EXECUTABLE must point to a working Python 3 interpreter. 1>&2
    exit /b 1
  )
  set I3_PYTHON_ARG="-DPython3_EXECUTABLE=%PYTHON3_EXECUTABLE%"
)
cd /d "%~dp0runtime"
cmake --fresh --preset x64-Clang-Release -DHAVE_ENDIAN_H=0 -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON -DCMAKE_LINKER=lld-link %I3_PYTHON_ARG% || exit /b 1
cmake --build Build\x64-Clang-Release -j 4 %*

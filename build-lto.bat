@echo off
rem Release build with link-time optimisation, at low priority. Usage: build-lto.bat
setlocal
call "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set "PATH=D:\sotc-pc\toolchain\clang+llvm-23.1.3-x86_64-pc-windows-msvc\bin;%PATH%"
cd /d "%~dp0runtime"
cmake --preset x64-Clang-Release -DHAVE_ENDIAN_H=0 -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON -DCMAKE_LINKER=lld-link || exit /b 1
cmake --build Build\x64-Clang-Release -j 4 %*

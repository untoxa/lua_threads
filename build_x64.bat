@echo off
IF NOT DEFINED PROJECT_ROOT (set PROJECT_ROOT=%~dp0.\)

@del /Q /F %PROJECT_ROOT%\units\*.* >nul
@mkdir %PROJECT_ROOT%\exe >nul
@mkdir %PROJECT_ROOT%\exe\x64 >nul
@mkdir %PROJECT_ROOT%\units >nul
@ppcrossx64.exe -B -Mdelphi -Ur -Xs -Fi%PROJECT_ROOT% -Fu%PROJECT_ROOT%\common\ -FE%PROJECT_ROOT%\exe\x64\ -FU%PROJECT_ROOT%\units\ lua_threads.dpr
@ppcrossx64.exe -B -Mdelphi -Ur -Xs -Fi%PROJECT_ROOT% -Fu%PROJECT_ROOT%\common\ -FE%PROJECT_ROOT%\exe\x64\ -FU%PROJECT_ROOT%\units\ lua_threads_runner.dpr
@del /Q /F %PROJECT_ROOT%\units\*.* >nul

@copy /b /y lua\*.lua %PROJECT_ROOT%\exe\x64\
@copy /b /y readme.md %PROJECT_ROOT%\exe\x64\

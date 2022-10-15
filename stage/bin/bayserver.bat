@ECHO OFF
set "RBCMD=C:\Ruby30-x64\bin\ruby.exe"

REM 
REM  Bootstrap script
REM 

set daemon=0
for %%f in (%*) do (
  if "%%f"=="-daemon" (
     set daemon=1
  )
)

if "%daemon%" == "1" (
  start %RBCMD%  %~p0\bootstrap.rb %*
) else (
  %RBCMD%  %~p0\bootstrap.rb %*
)
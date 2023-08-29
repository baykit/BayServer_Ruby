@ECHO OFF
set "RBCMD=C:\Ruby30-x64\bin\ruby.exe"
set GEM_HOME=%~p0\..\gems
set SCRIPT=%GEM_HOME%\bin\bayserver

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
  start %RBCMD% %SCRIPT% %*
) else (
  %RBCMD% %SCRIPT% %*
)
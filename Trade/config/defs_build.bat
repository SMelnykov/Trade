:build


        @set DBPath=%~dp0..\DB
	@set logsroot=%~dp0..\logs
	@set buildroot=%~dp0..\..\..\..
	@set tempfolder=%~dp0..\temp
        @set mssqlcmd=sqlcmd.exe


	@set _is_%~n0_set=true
@goto :EOF

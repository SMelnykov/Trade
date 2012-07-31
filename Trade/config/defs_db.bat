:build

	@set SQL_Server_Name=K8SPDDB\CDEV_CDB
	@set Database_Name=Trade
        @set DBScriptsPath=%DBPath%\Scripts
        @set DBSProceduresPath=%DBPath%\Procedures

	@set DB_Scripts_msk=*.sql
	@set DB_Procedures_msk=*.prc

	@set _is_%~n0_set=true
@goto :EOF

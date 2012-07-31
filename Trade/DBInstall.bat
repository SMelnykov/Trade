:main
	@call :_i_init_build

@:: Working from root of %buildroot%
	@pushd "%buildroot%" || exit /b 1
		@for %%i in (%deploy_target_list%) do @(
			echo %date% %time% 	Executing target '%%~i'
			call :%%~i 1>>"%logsroot%\%~n0.log" 2>&1
		)
	@popd
@exit /b 0


:sd
:scripts_deploy
	@for %%i in (%DBScriptsPath%\%DB_Scripts_msk%) do @(
		call :sqlcmd "%SQL_Server_Name%" "%Database_Name%" "%%~dpnxi" "%logsroot%\%~n0.scripts_out%%~1.log"
	)
@exit /b 0

:pd
:procedures_deploy
	@for %%i in (%DBProceduresPath%\%DB_Procedures_msk%) do @(
		call :sqlcmd "%SQL_Server_Name%" "%Database_Name%" "%%~dpnxi" "%logsroot%\%~n0.procedures_out%%~1.log"
	)
@exit /b 0


@::### Necessary private methods ###
:_i_set_var
	@set _tmp_var=%~1
	@set _tmp_var=%_tmp_var:date: =%
@goto :EOF

:sqlcmd
	@echo %date% %time% -- running script "%~3"
	@echo "%date% %time% -- running script %~3" >> "%~4"
		@%mssqlcmd% -S%~1 -E -dmaster -i%~3 >> "%~4"
	@echo "%date% %time% -- Errorlevel %errorlevel% -- finished script %~3" >> "%~4"
@exit /b


:_i_init_build
	@if not defined _is_defs_build_set    call "%~dp0config\defs_build.bat"
	@if not defined _is_defs_db_set       call "%~dp0config\defs_db.bat"

	@call :_i_clean_dirs
	@call :_i_create_dirs

	@if not defined deploy_target_list set deploy_target_list=scripts_deploy procedures_deploy
@goto :EOF


:_i_clean_dirs
	@if exist "%logsroot%" rd /s /q "%logsroot%" 1>nul 2>&1
@goto :EOF


:_i_create_dirs
	@if not exist "%logsroot%" md "%logsroot%"
	@if not exist "%buildroot%" md "%buildroot%"

	@if not exist "%tempfolder%\" md "%tempfolder%\"
@goto :EOF



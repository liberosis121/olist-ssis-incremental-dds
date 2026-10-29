@echo off
rem Dua moi truong ve trang thai "san sang quay video":
rem   Olist_Source co du lieu dot 1, Olist_DDS trong (LSET = 1900-01-01), chua chay package nao.
rem Chay tu bat ky thu muc nao:  sql\reset_and_prepare.cmd
setlocal
set SRV=localhost
set OPT=-S %SRV% -E -C -I -f 65001 -b
cd /d "%~dp0"
sqlcmd %OPT% -i 99_reset_all.sql          || goto :err
sqlcmd %OPT% -i 01_create_source_db.sql   || goto :err
sqlcmd %OPT% -i 02_seed_source_batch1.sql || goto :err
sqlcmd %OPT% -i 03_create_dds.sql         || goto :err
echo.
echo === XONG: moi truong da san sang (chua chay package) ===
exit /b 0
:err
echo !!! Co loi khi chay script. Xem thong bao o tren.
exit /b 1

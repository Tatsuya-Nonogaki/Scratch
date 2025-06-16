@Echo Off
setlocal enabledelayedexpansion
set DT=%date:~0,4%%date:~5,2%%date:~8,2%
set URI=%1
@rem set URI=https://172.16.135.239/redfish/v1/AccountService/Accounts
@rem set Out=.\iLo_Accountslist_%DT%.json
set Out=.\tempresult.json

set USER=Administrator
set PASS=DonKno

curl -k %URI% -X GET -i --insecure -u %USER%:%PASS% -L -o %Out% >> .\cmd_result.txt
type .\tempresult.json
del /Q .\tempresult.json

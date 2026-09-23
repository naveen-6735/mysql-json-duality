# Quick local run without Docker (requires local MySQL 8/9)
param(
  [string]$MySQLHost = "localhost",
  [string]$MySQLPass = "shop_password"
)
Write-Host "=== ShopDB Local Runner ===" -ForegroundColor Cyan
Write-Host "1. Ensure MySQL is running on $MySQLHost and you can login as root"
Write-Host "2. This will recreate shopdb DB"

$env:MYSQL_HOST="localhost"
$env:MYSQL_PASSWORD=$MySQLPass

Write-Host "`n-- Running SQL files..."
Get-Content "..\sql\01_schema.sql" | mysql -u root -p$MySQLPass
Get-Content "..\sql\02_seed.sql" | mysql -u root -p$MySQLPass
try { Get-Content "..\sql\03_duality_views.sql" | mysql -u root -p$MySQLPass; Write-Host "Duality views created" -ForegroundColor Green } catch { Write-Host "Duality failed (MySQL 8?) -> using fallback. API will auto-fallback." -ForegroundColor Yellow }

Write-Host "`n-- Starting API..."
Set-Location ..\api
python -m pip install -r requirements.txt
uvicorn main:app --reload --port 8000

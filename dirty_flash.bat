@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title CMF Phone 1 tetris - ROM Dirty Flash

echo.
echo ================================================================
echo   CMF Phone 1 "tetris" - ROM dirty flash
echo   No data wipe. Current slot only. Firmware only if you say so.
echo ================================================================
echo.

rem ============================ CONFIG ============================
rem Accepted values of "fastboot getvar product". On tetris the
rem bootloader reports the MediaTek platform name, not the codename.
set "TARGET=tetris"
set "TARGET2=k6878v1_64"
rem Folder with the images. "." = the folder this script is in.
rem If there is no .img here, ".\images" is used automatically.
set "IMG=."
rem Extra flags for vbmeta*.img - normally leave EMPTY.
rem Example: set "VBMETA_FLAGS=--disable-verity --disable-verification"
set "VBMETA_FLAGS="
rem Official stock lk.img SHA-256 (NOS Tetris_B4.1-260928-1140,
rem from the nothing_archive release hash file - NOT invented).
set "STOCK_LK_SHA256=06fe7a8ec097ec05c13c416ffef3989b8c85190bf6621ab0be7d509fa1543dbd"
rem ===============================================================

if not exist "%IMG%\*.img" if exist "images\*.img" set "IMG=images"
if not exist "%IMG%\*.img" (
  echo [ERROR] No .img files found in %CD%.
  echo Put this script into the folder with the extracted images,
  echo or edit the IMG variable at the top of the script.
  pause
  exit /b 1
)

rem Name sets, space padded, used for substring membership tests.
rem NEVER = identity / wipe / device state. Flashing these can destroy
rem IMEI, DRM keys, lock state or user data. They are NEVER written.
set "NEVER= userdata metadata cache frp sdcard nvram nvdata nvcfg protect1 protect2 persist proinfo seccfg super_empty "
rem LKSUB = sub-images inside the lk package (lk, bl2_ext, aee, dtb...).
rem Flashing one of these alone to lk_a would break the bootloader.
set "LKSUB= bl2_ext aee lk_main_dtb lk_dtbo "
rem Boot chain images, flashed in bootloader fastboot mode.
set "PHYS= boot init_boot vendor_boot dtbo vbmeta vbmeta_system vbmeta_vendor "
rem Logical images inside super, flashed in fastbootd.
set "LOGIC= system system_ext product vendor odm vendor_dlkm odm_dlkm system_dlkm "
rem Device firmware, flashed only on request (see the warning).
set "FIRM= apusys ccu connsys_bt connsys_gnss connsys_wifi dpm gpueb gz logo mcf_ota mcupm modem pi_img scp spmfw sspm tee vcp "

set "N_AP="
set "N_AL="
set "N_FIRM="
set "N_UNK="
set "N_BLOCK="
set "DO_LK=0"
set "LKFILE="
set "SUPERFILE="
set "PREFILE="
set "PREIMG="
set "CNT=0"
set "TRIES=0"

rem ======================== find fastboot ========================
set "FASTBOOT=platform-tools\fastboot.exe"
if exist "%FASTBOOT%" goto :fb_ok
set "FASTBOOT=bin\windows\fastboot.exe"
if exist "%FASTBOOT%" goto :fb_ok
echo platform-tools\fastboot.exe not found, downloading platform-tools ...
curl --fail --ssl-no-revoke -L https://dl.google.com/android/repository/platform-tools-latest-windows.zip -o platform-tools-latest-windows.zip
if exist platform-tools-latest-windows.zip powershell -NoProfile -Command "Expand-Archive -Path 'platform-tools-latest-windows.zip' -DestinationPath '.' -Force"
if exist platform-tools-latest-windows.zip del /f /q platform-tools-latest-windows.zip >nul 2>&1
set "FASTBOOT=platform-tools\fastboot.exe"
if exist "%FASTBOOT%" goto :fb_ok
where fastboot >nul 2>&1
if errorlevel 1 (
  echo [ERROR] fastboot not found and the platform-tools download failed.
  pause
  exit /b 1
)
echo [WARN] Using fastboot from PATH. Make sure it is a recent build.
set "FASTBOOT=fastboot"
:fb_ok

rem ======================== device checks ========================
echo Waiting for the device in fastboot mode...
set "DEVID="
for /f "tokens=1" %%A in ('%FASTBOOT% devices 2^>nul') do set "DEVID=%%A"
if not defined DEVID (
  echo [ERROR] No fastboot device detected.
  echo Boot the phone into bootloader mode:  adb reboot bootloader
  pause
  exit /b 1
)

set "PROD="
for /f "tokens=2" %%A in ('%FASTBOOT% getvar product 2^>^&1 ^| findstr /b /c:"product:"') do set "PROD=%%A"
if /i "%PROD%"=="%TARGET%" goto :prod_ok
if /i "%PROD%"=="%TARGET2%" goto :prod_ok
echo [ERROR] Detected product "%PROD%", expected "%TARGET%" or "%TARGET2%".
echo If this really is your phone, fix TARGET at the top of the script.
pause
exit /b 1
:prod_ok

set "SLOT="
for /f "tokens=2" %%A in ('%FASTBOOT% getvar current-slot 2^>^&1 ^| findstr /b /c:"current-slot:"') do set "SLOT=%%A"
if /i not "%SLOT%"=="a" if /i not "%SLOT%"=="b" (
  echo [ERROR] Could not read the current slot.
  pause
  exit /b 1
)

set "UNL="
for /f "tokens=2" %%A in ('%FASTBOOT% getvar unlocked 2^>^&1 ^| findstr /b /c:"unlocked:"') do set "UNL=%%A"
if /i "%UNL%"=="no" (
  echo [ERROR] The bootloader is LOCKED. This script is for a dirty flash
  echo on an already unlocked device running a custom ROM.
  pause
  exit /b 1
)
if not defined UNL (
  echo [WARN] Could not read the unlock state.
  choice /c YN /m "Continue anyway"
  if errorlevel 2 exit /b 0
)

echo.
echo Device   : %PROD%
echo Slot     : %SLOT%
echo Unlocked : %UNL%
echo Mode     : dirty flash - userdata and metadata are NOT touched
echo            only slot %SLOT% is written, the other slot is left alone
echo.

rem ========================= image plan ==========================
echo === Image plan ============================================================
echo.
echo   [AUTO]  flashed without asking   ROM images for this update
echo   [ASK]   asked separately         lk, firmware, unknown names
echo   [BLOCK] never flashed            identity, wipe or device state
echo.
for %%F in ("%IMG%\*.img") do call :plan_line "%%~nF"
if %CNT%==0 (
  echo [ERROR] No .img files found in %IMG%.
  pause
  exit /b 1
)
echo ==========================================================================
echo.

rem ========================== questions ==========================
if defined N_FIRM call :ask_firm
if not defined N_FIRM if defined PREFILE call :ask_firm
if "%DO_LK%"=="1" call :ask_lk
if defined N_UNK call :ask_unk

echo.
echo === Final confirmation ===
echo slot %SLOT% only, no data wipe, lk flashed: %DO_LK%
choice /c YN /m "Start flashing now"
if errorlevel 2 (
  echo Cancelled, nothing was flashed.
  exit /b 0
)

rem ===================== phase 1: physical =======================
echo.
echo === Phase 1: physical partitions, bootloader fastboot ===
if defined N_FIRM for %%P in (%N_FIRM%) do call :flash %%P %%P.img || goto :fail
if defined PREIMG call :flash preloader %PREIMG% || goto :fail
if "%DO_LK%"=="1" call :flash lk %LKFILE% || goto :fail
if defined N_AP for %%P in (%N_AP%) do call :flash %%P %%P.img || goto :fail
if defined N_UNK for %%P in (%N_UNK%) do call :flash %%P %%P.img || goto :fail

rem =================== phase 2: fastbootd ========================
echo.
echo === Phase 2: logical partitions, fastbootd ===
echo Rebooting to fastbootd...
%FASTBOOT% reboot fastboot
if errorlevel 1 goto :fail

:wait_us
timeout /t 2 /nobreak >nul
set /a TRIES+=1
if %TRIES% gtr 30 (
  echo [ERROR] fastbootd did not come up.
  echo On Windows this is usually a USB driver problem: the phone
  echo re-enumerates in fastbootd mode and needs its driver again.
  goto :fail
)
set "US="
for /f "tokens=2" %%A in ('%FASTBOOT% getvar is-userspace 2^>^&1 ^| findstr /b /c:"is-userspace:"') do set "US=%%A"
if /i not "%US%"=="yes" goto :wait_us
echo fastbootd is up.

set "SNAP="
for /f "tokens=2" %%A in ('%FASTBOOT% getvar snapshot-update-status 2^>^&1 ^| findstr /b /c:"snapshot-update-status:"') do set "SNAP=%%A"
if /i "%SNAP%"=="merging" (
  echo [ERROR] A Virtual A/B snapshot merge is still in progress.
  echo Boot Android, wait until the merge finishes, then run this again.
  goto :fail
)
if not defined SNAP goto :no_snap
if /i "%SNAP%"=="none" goto :no_snap
echo Pending update state: %SNAP%. Cancelling it before flashing...
%FASTBOOT% snapshot-update cancel
if errorlevel 1 (
  echo [WARN] Could not cancel the pending snapshot update.
  choice /c YN /m "Continue anyway"
  if errorlevel 2 goto :fail
)
:no_snap

if defined SUPERFILE (
  call :flash_super
  if errorlevel 1 goto :fail
) else (
  if defined N_AL for %%P in (%N_AL%) do call :flash %%P %%P.img || goto :fail
)

rem ========================= finishing ===========================
echo.
echo === Finishing ===
%FASTBOOT% --set-active=%SLOT%
if errorlevel 1 echo [WARN] set-active failed, continuing anyway.
%FASTBOOT% reboot
echo.
echo Done. First boot after an update can take a few minutes.
echo If the phone bootloops: bootloader mode is still available and
echo nothing is wiped - re-run the script or flash the previous images.
pause
exit /b 0

rem ========================== subroutines ========================

:plan_line
set /a CNT+=1
set "N=%~1"
if not "!NEVER: %N% =!"=="!NEVER!" goto :pl_block
if not "!LKSUB: %N% =!"=="!LKSUB!" goto :pl_lksub
if /i "%N%"=="lk" goto :pl_lk
if /i "%N%"=="preloader" goto :pl_pre
if /i "%N%"=="preloader_raw" goto :pl_pre
if /i "%N%"=="super" goto :pl_super
if not "!LOGIC: %N% =!"=="!LOGIC!" goto :pl_logic
if not "!PHYS: %N% =!"=="!PHYS!" goto :pl_phys
if not "!FIRM: %N% =!"=="!FIRM!" goto :pl_firm
goto :pl_unk

:pl_block
echo   [BLOCK]  %N%.img  -^>  never flashed: identity/wipe/state partition
set "N_BLOCK=%N_BLOCK% %N%"
exit /b 0

:pl_lksub
echo   [BLOCK]  %N%.img  -^>  lk package sub-image, not a partition by itself
echo             only a complete lk.img can go to lk_%SLOT%
set "N_BLOCK=%N_BLOCK% %N%"
exit /b 0

:pl_lk
echo   [ASK]    %N%.img  -^>  lk_%SLOT%  -^>  bootloader package, hash checked
set "DO_LK=1"
set "LKFILE=%N%.img"
exit /b 0

:pl_pre
echo   [ASK]    %N%.img  -^>  preloader_%SLOT%  -^>  firmware, read the warning
set "PREFILE=%N%.img"
exit /b 0

:pl_super
echo   [AUTO]   %N%.img  -^>  super  -^>  full super image, logical images skipped
set "SUPERFILE=%N%.img"
exit /b 0

:pl_logic
echo   [AUTO]   %N%.img  -^>  %N%_%SLOT%  -^>  fastbootd
set "N_AL=%N_AL% %N%"
exit /b 0

:pl_phys
echo   [AUTO]   %N%.img  -^>  %N%_%SLOT%
set "N_AP=%N_AP% %N%"
exit /b 0

:pl_firm
echo   [ASK]    %N%.img  -^>  %N%_%SLOT%  -^>  firmware, read the warning
set "N_FIRM=%N_FIRM% %N%"
exit /b 0

:pl_unk
echo   [ASK]    %N%.img  -^>  %N%_%SLOT%  -^>  unknown partition name
set "N_UNK=%N_UNK% %N%"
exit /b 0

:ask_firm
echo.
echo === Device firmware / bootloader images ===
if defined N_FIRM echo   %N_FIRM%
if defined PREFILE echo   %PREFILE%  -^>  preloader_%SLOT%
echo.
echo These are early boot firmware images, NOT ROM images.
echo They are not required for a ROM update.
echo A wrong preloader image can HARD-BRICK the phone and it can then
echo only be recovered with MediaTek SP Flash tools.
echo Flash them only for a full firmware update with matching images.
echo.
choice /c YN /m "Flash these firmware images"
if errorlevel 2 (
  echo Firmware will NOT be flashed.
  set "N_FIRM="
  set "PREFILE="
  exit /b 0
)
call :pick_pre
exit /b 0

:ask_lk
echo.
echo === lk.img verification ===
set "LKH="
for /f "tokens=1" %%X in ('certutil -hashfile "%IMG%\%LKFILE%" SHA256 ^| find /i /v "SHA256" ^| find /i /v "CertUtil"') do set "LKH=%%X"
echo file   : %LKFILE%
echo sha256 : %LKH%
findstr /m /i /c:"fenrir" "%IMG%\%LKFILE%" >nul 2>&1 && echo [WARN] The file contains the string "fenrir", it is most likely PATCHED.
if /i "%LKH%"=="%STOCK_LK_SHA256%" goto :lk_stock
echo.
echo Verdict: UNKNOWN - this is NOT the known stock lk of NOS B4.1-260928-1140.
echo It may be the fenrir-patched lk that ships inside some OTAs.
echo Flashing a patched lk can factory-reset the device and is NOT needed
echo on a stock unlocked bootloader.
echo Say Y only if you know exactly what this file is.
choice /c YN /m "Flash this lk image"
if errorlevel 2 set "DO_LK=0"
exit /b 0
:lk_stock
echo.
echo Verdict: KNOWN STOCK lk, official NOS Tetris_B4.1-260928-1140 image.
choice /c YN /m "Flash this lk image"
if errorlevel 2 set "DO_LK=0"
exit /b 0

:ask_unk
echo.
echo === Unknown image names ===
echo   %N_UNK%
echo.
echo These file names do not match known %TARGET% partitions.
echo The file name must be the partition name, lowercase, no slot suffix.
echo If you say Y they are flashed like every other image to name_%SLOT%.
echo Say N if you are not sure.
echo.
choice /c YN /m "Flash these unknown images"
if errorlevel 2 set "N_UNK="
exit /b 0

:pick_pre
set "PREIMG="
if exist "%IMG%\preloader_raw.img" set "PREIMG=preloader_raw.img"
if not defined PREIMG if exist "%IMG%\preloader.img" set "PREIMG=preloader.img"
if defined PREIMG echo preloader image selected: %PREIMG%  -^>  preloader_%SLOT%
exit /b 0

:flash
rem %1 = partition name without slot suffix, %2 = image file name in IMG
if not exist "%IMG%\%~2" (
  echo [SKIP] %~2 not found
  exit /b 0
)
set "FL="
echo %~1| findstr /b /c:"vbmeta" >nul && set "FL=%VBMETA_FLAGS%"
echo [flash] %~1_%SLOT%  from  %~2
%FASTBOOT% flash %FL% %~1_%SLOT% "%IMG%\%~2"
if errorlevel 1 (
  echo [FAIL] %~1_%SLOT%
  exit /b 1
)
exit /b 0

:flash_super
echo [flash] super  from  %SUPERFILE%
%FASTBOOT% flash super "%IMG%\%SUPERFILE%"
if errorlevel 1 (
  echo [FAIL] super
  exit /b 1
)
exit /b 0

:fail
echo.
echo ====================  FLASH FAILED  ====================
echo The phone was NOT rebooted and NOTHING was wiped.
echo Fix the error above and run the script again. If it
echo stopped halfway, just re-run it, already written
echo partitions are simply written again.
echo =======================================================
pause
exit /b 1

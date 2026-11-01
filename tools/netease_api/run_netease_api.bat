@echo off
chcp 65001 >nul
cd /d %~dp0
echo.
echo ==============================================
echo   网易云音乐 API 启动器（NeteaseCloudMusicApi）
echo ==============================================
echo.
if not exist node_modules (
  echo 首次运行，正在安装依赖，请稍候...
  call npm install NeteaseCloudMusicApi
  if errorlevel 1 (
    echo 安装失败，请检查网络或代理设置后重试
    pause
    exit /b 1
  )
)
echo API 地址：http://localhost:3000
echo 正在打开二维码登录页（用网易云音乐 App 扫码登录）...
start "" http://localhost:3000/qrlogin.html
echo.
echo 登录后免费歌曲可获取完整播放地址（VIP 歌曲需要 VIP 账号）。
echo 保持本窗口运行，按 Ctrl+C 停止服务。
echo.
node -e "require('NeteaseCloudMusicApi').serveNcmApi({port:3000})"
pause

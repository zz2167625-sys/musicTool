Set ws = CreateObject("WScript.Shell")
ws.CurrentDirectory = "D:\development\Mytools\my_tools\tools\netease_api"
ws.Run "cmd /c node -e ""require('NeteaseCloudMusicApi').serveNcmApi({port:3000})""", 0, False

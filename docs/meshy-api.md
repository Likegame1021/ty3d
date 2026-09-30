# Meshy API 本地接入

本项目使用 Meshy 官方 REST API。API 地址固定为 `https://api.meshy.ai`，请求使用 `Authorization: Bearer <API key>`。

最近验证：2026-09-28，使用本机 Windows 用户账户读取已保存凭据，余额接口返回成功。已实际完成主角生成、绑定、原四动画，以及 M2 棚屋/板车/树木和新增五动画任务。M0消耗47积分，M2本批消耗105积分，最近余额1153；详见 `art/environment/meshy/production-ledger.md` 和各资产原始任务响应。

## 凭据存放

- 密钥位于项目内 `.local/meshy/api-key.clixml`，由 Windows PowerShell `Export-Clixml` 加密保存。
- 该文件绑定当前 Windows 用户与本机，不能直接复制到另一台电脑使用。
- 保存账户为本机用户 `21078`。若自动化执行环境使用另一个隔离账户，需在该本机用户环境执行；跨账户解密失败不代表 API key 无效。
- `.local/` 已加入 `.gitignore`；`.local/.gdignore` 用于阻止未来 Godot 项目导入此目录。
- 不要将解密后的密钥写入代码、日志、游戏客户端或导出包。

## 查询余额 / 验证鉴权

在当前 Windows 用户的 PowerShell 中执行下列命令。可以从任意目录执行，项目路径如下：

```powershell
$ErrorActionPreference = 'Stop'
$keyFile = 'G:\Game\vallage\.local\meshy\api-key.clixml'
$meshySecureKey = Import-Clixml -LiteralPath $keyFile
$meshyCredential = [System.Net.NetworkCredential]::new('', $meshySecureKey)
$meshyHeaders = @{ Authorization = 'Bearer ' + $meshyCredential.Password }
try {
    $meshyResponse = Invoke-RestMethod `
        -Uri 'https://api.meshy.ai/openapi/v1/balance' `
        -Method Get `
        -Headers $meshyHeaders `
        -MaximumRedirection 0 `
        -TimeoutSec 30 `
        -Verbose:$false `
        -Debug:$false
    [pscustomobject]@{ balance = $meshyResponse.balance } | ConvertTo-Json
}
catch {
    # 不输出请求头、凭据或原始异常正文。
    $meshyHttpStatus = if ($_.Exception.Response) {
        [int]$_.Exception.Response.StatusCode
    } else { $null }
    [pscustomobject]@{
        connected = $false
        http_status = $meshyHttpStatus
        error = 'Meshy request failed. Check credentials, network, or account permissions.'
    } | ConvertTo-Json
}
finally {
    $meshyHeaders.Clear()
    $meshyCredential = $null
    $meshySecureKey.Dispose()
}
```

已实现制作期工具：`tools/meshy/create-boy.ps1`、`create-static-asset.ps1`、`request.ps1` 与 `watch-task.ps1`。创建任务保留请求/返回ID，避免重复提交扣费；完成后按版本目录下载原始GLB。密钥只用于本机制作，不集成进Godot运行游戏。新资产只在用户授权的具体制作范围内提交。

## 更换密钥

在当前 Windows 用户的 PowerShell 中交互输入新密钥，不将其写进命令文本：

```powershell
$meshyNewKey = Read-Host 'Meshy API key' -AsSecureString
try {
    $meshyNewKey | Export-Clixml `
        -LiteralPath 'G:\Game\vallage\.local\meshy\api-key.clixml'
}
finally {
    $meshyNewKey.Dispose()
}
```

## 官方参考

- [鉴权](https://docs.meshy.ai/zh/api/authentication)
- [余额接口](https://docs.meshy.ai/zh/api/balance)
- [单图生成 3D](https://docs.meshy.ai/zh/api/image-to-3d)
- [多图生成 3D](https://docs.meshy.ai/zh/api/multi-image-to-3d)

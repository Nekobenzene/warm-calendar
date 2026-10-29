# Windows 发布签名

2026-10-29 检查结果：当前日程表主程序 `NotSigned`，不是已有发布证书损坏；附带 Node.js 的 OpenJS 官方签名有效。本机未找到带私钥的代码签名证书，尚不能生成受信任的 Windows 发布签名。Android 的项目本地 APK 签名已完成，与 Windows Authenticode 是不同机制。

## 从哪里申请

- [DigiCert 代码签名](https://www.digicert.com/signing/code-signing-certificates)
- [Sectigo 代码签名](https://www.sectigo.com/ssl-certificates-tls/code-signing)
- [GlobalSign 代码签名](https://www.globalsign.com/en/code-signing-certificate)
- [Microsoft Artifact Signing](https://learn.microsoft.com/en-us/azure/artifact-signing/overview)，签名服务的申请主体、地区和身份核验要求以微软当前规定为准。

一般需要付费、核验发布者身份并保护硬件令牌或云端私钥。购买前确认支持所在地区、个人 / 企业主体和 Windows Authenticode 发布。商店分发是另一条路线，需要另行打包与审核，本版没有提交商店。

主要自己使用时，可以先不购买。有效签名用于证明发布者和文件完整性；SmartScreen 信誉、Smart App Control 以及组织策略仍可能影响是否允许运行，不能承诺“签一次就一定不拦截”。不要用自签名根证书冒充公信发布者，也不需要为构建修改系统安全策略。

## 已准备的签名流程

`scripts/sign-desktop.ps1` 扫描完整包里的 EXE / DLL：保留有效的官方签名，使用指定证书为未签名文件添加 SHA-256 Authenticode 和 RFC3161 时间戳，再逐项验签。已有无效签名会停止处理，避免覆盖掩盖问题。输出 `windows-signatures.json`，含文件哈希、发布者和签名状态。

证书及私钥由用户 / 证书机构导入 Windows“个人”证书存储或硬件提供程序，不将证书密码写进命令行、源码或交接文档。脚本接受证书指纹：

```powershell
# 普通本地构建：允许未签名，输出真实签名清单
.\scripts\build-desktop.ps1
# 有证书后构建并签名，替换为实际证书指纹
.\scripts\build-desktop.ps1 -CertificateThumbprint <40位指纹> -RequireTrustedSignature
# 只检查完整包；发现任何未签名 / 无效签名时失败
.\scripts\sign-desktop.ps1 -PackageDirectory 'dist/日程表Windows' -RequireTrustedSignature
```

证书在 LocalMachine 存储时添加 `-MachineCertificateStore`；硬件令牌可能要求用户输入 PIN。云签名服务需要对应供应商的适配，本脚本尚未接入任何云签名账号。未取得证书前，只验证了清单和拒绝未签名发布的检查路径，未实测真实证书签名。

安装EXE使用同一证书参数：`scripts/build-installer.ps1 -CertificateThumbprint <40位指纹> -RequireTrustedSignature`，先签应用，再由Inno SignTool签安装器及内嵌卸载器。无证书时允许本地构建，产物旁的`.exe.json`明确记录`NotSigned`，`.exe.sha256`记录完整性校验值。编译器自身的官方签名不代表我们的应用或安装包已有受信任签名。

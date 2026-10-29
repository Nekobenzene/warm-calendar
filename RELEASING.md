# 发布安装包

仓库为 https://github.com/Nekobenzene/warm-calendar，默认分支main，版本来自pubspec.yaml。Android必须保留原发布密钥；不要将密钥、key.properties或个人数据库提交到仓库。

## 生成与整理

使用README、DESKTOP.md、ANDROID.md中的步骤构建并验证Windows安装向导和Android APK，然后运行：

```powershell
.\scripts\prepare-release.ps1
```

输出位于`dist/releases/版本/`，只含两个安装包和校验文件；不改变既有构建、运行目录或快捷方式。文件使用统一名称：

- `warm-calendar-版本-windows-x64-setup.exe`
- `warm-calendar-版本-android.apk`
- `SHA256SUMS.txt`

`dist/archive/`是本机历史构建归档，不提交、不发布。本机安装后的程序独立于dist，位置以桌面快捷方式为准。

## 推送与发布

先提交已验证源码并推送main。安装官方GitHub CLI，使用自己的账号登录。为版本编写`releases/版本.md`，然后创建Release草稿并上传上述三个文件：

```powershell
$version = '0.5.0'
git push origin main
git tag -a "v$version" -m "Release $version"
git push origin "v$version"
gh release create "v$version" --verify-tag --draft --title "日程表 $version" --notes-file "releases/$version.md" "dist/releases/$version/*"
gh release view "v$version"
gh release edit "v$version" --draft=false --latest
```

发布前确认Tag对应构建源码、APK证书保持一致、附件和SHA256一致。已发布版本不要覆盖同名附件；修改程序后增加版本重新发布。

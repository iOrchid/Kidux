# 启椟 · Kidux Website

面向用户的 **GitHub Pages 官网**（仅静态页，不含 App 源码）。

- 产品：**启椟**（工程名 Kidux）— macOS 一键开箱装机助手  
- 本仓库用途：宣传页 + Pages 配置说明  
- 安装包：请放到 **GitHub Releases**，不要提交进本仓库  

---

## 仓库结构

```text
Kidux-Website/
├── index.html       # 官网首页（CSS 内联，可直接双击预览）
├── assets/
│   └── icon.png     # 站点图标 / OG 图
├── .nojekyll        # 让 GitHub Pages 跳过 Jekyll，原样发布静态文件
├── .gitignore
└── README.md
```

---

## 一、推到 GitHub（首次）

在 GitHub 新建**空仓库**（不要勾选自动添加 README），例如：`Kidux-Website` 或 `kidux-site`。

```bash
cd Kidux-Website          # 进入本目录
git init
git add .
git commit -m "Add 启椟 GitHub Pages site"
git branch -M main
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

若仓库已存在，只需改 `origin` 后 `git push`。

---

## 二、开启 GitHub Pages（必做）

1. 打开仓库 → **Settings** → 左侧 **Pages**
2. **Build and deployment**
   - **Source**：`Deploy from a branch`
   - **Branch**：`main`
   - **Folder**：`/ (root)` ← 根目录，不要选 `/docs`
3. 点 **Save**
4. 等待 1～2 分钟，页面顶部会出现访问地址，例如：

   `https://<你的用户名>.github.io/<仓库名>/`

5. 以后改了 `index.html` / `assets/`，`git push` 到 `main` 即可自动更新站点。

### 可选：自定义域名

1. Pages 设置里填写 Domain（如 `kidux.app`）
2. 在域名 DNS 添加 GitHub 要求的 `A` / `CNAME` 记录  
3. 本仓库根目录可增加 `CNAME` 文件（内容只有一行域名）

---

## 三、上传 DMG（Releases，不要进 git）

公证签名包示例：`启椟-2.2.0.dmg`

1. 仓库页 → **Releases** → **Create a new release**
2. Tag：如 `v2.2.0`；Title：`启椟 2.2.0`
3. 把 DMG 拖到 **Attach binaries**
4. Publish

官网下载按钮默认指向：

`https://github.com/langem/Kidux/releases/latest`

若你的下载仓/用户名不同，请编辑 `index.html`，全文替换该 URL（页面里有两处「下载 / Releases」链接）。

> **注意**：`*.dmg` 已写入 `.gitignore`，避免把近 10MB 安装包提交进 Pages 仓库。

---

## 四、本地预览

```bash
cd Kidux-Website
open index.html
# 或
python3 -m http.server 8080
# 浏览器打开 http://127.0.0.1:8080/
```

---

## 五、常见问题

| 现象 | 处理 |
|------|------|
| Pages 404 | 确认 Branch=`main`、Folder=`/`，且根目录有 `index.html` |
| 样式异常 / 空白 | 确认已推送 `.nojekyll`；刷新或清 CDN 缓存后再试 |
| 下载 404 | Releases 里是否已上传 DMG；`index.html` 链接是否指向正确仓库 |
| 想只当官网、源码另仓 | 正确做法：本仓只放静态页；源码仓可私有，互不影响 |

---

## 六、与 App 工程的关系

| 目录 / 仓库 | 内容 |
|-------------|------|
| 本仓库 `Kidux-Website` | GitHub Pages 官网 |
| 启椟 Xcode 工程（可私有） | App 源码、`./bin/release-dmg.sh --dist` 打签名公证包 |

重新打 DMG 后：更新 GitHub Release 附件即可，一般不必改官网 HTML（使用 `/releases/latest` 时）。

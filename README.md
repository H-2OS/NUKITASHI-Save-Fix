<p align="center">
  <b>简体中文</b> &nbsp;|&nbsp;
  <a href="#聲明">繁體中文</a> &nbsp;|&nbsp;
  <a href="#Disclaimer">English</a>
</p>

---
### 声明

本补丁为非官方第三方补丁，仅供学习交流使用，禁止商用。原游戏的全部代码、剧情、美术、音频等内容，版权归原作者 / 开发团队所有。若版权所有者提出异议，本项目将立即下架。

### 简介

这是一个个人制作的 NUKITASHI / NUKITASHI 2（Steam 版）**存档修复补丁**，旨在无损、便捷地恢复原存档的可读性。如果它对你有帮助，欢迎点亮⭐️支持本项目！

### 要求

- Windows 8+（使用自带 PowerShell 3.0）
- NUKITASHI / NUKITASHI 2（Steam 版，Artemis Engine）(非steam版暂未测试兼容性)

### 使用方法

**安装补丁：**

1. 双击 install.bat
2. 按屏幕提示完成操作
 （NUKITASHI Save Fix 文件夹中的文件是补丁辅助安装程序，补丁成功后即可删除此文件夹）
3. 启动游戏，进入 Load 页面，此时将会看到拥有正确日期但章节和角色语句空白的存档出现。
4. 对上述存档进行读档操作(无需存档)，完成读档后返回 Load 页面，空白部分将会显示章节以及角色语句。

**卸载补丁：**

删除游戏文件夹下的 `system/adv/fileio.lua` 和 `system/adv/fsave.lua` 即可。PFS 封包内的原始游戏文件从未被修改，无须担心。

### 文件

| 文件 | 作用 |
|------|------|
| `install.bat` | 双击运行，绕过 PowerShell 执行策略 |
| `install.ps1` | 扫描 `saveXXXX.png` 修改时间 → 生成 `_save_dates` 表 → 组装 `fileio.lua` |
| `fileio_template.lua` | 补丁模板，`-- DATE_TABLE_PLACEHOLDER --` 由脚本替换 |
| `fsave.lua` | 预修补版（一行改动：嵌入日期到 BOWS） |

### 补丁工作原理

游戏使用 Artemis Engine。存档系统依赖 `savedata/saveg.dat` 中的一个 Lua 表 `sys.saveslot` 来索引所有槽位。当该文件因 Steam 云同步等原因被覆写，`sys.saveslot` 丢失——Load 界面变为空白，但其实 `savedata/` 下的 `saveNNNN.dat` 完整无损。

故本补丁通过**修改游戏的两个 Lua 脚本**（引擎优先读取文件系统中的 `.lua` 文件，覆盖 PFS 封包内的原脚本），在 `sys.saveslot` 缺失时直接检查磁盘文件重建索引，加载存档后从 BOWS 数据中自动恢复章节标题和对话文本。

补丁修改了两个文件，部署后游戏目录结构：

```
NUKITASHI/
├── NUKITASHI.exe
├── NUKITASHI.pfs                ← 原始 fileio.lua / fsave.lua 在此档案内
├── system/
│   └── adv/
│       ├── fileio.lua           ← ★ 补丁版（引擎优先读取）
│       └── fsave.lua            ← ★ 补丁版
└── savedata/
    ├── saveg.dat                ← 槽位索引（可能被破坏）
    ├── save0001.dat ~ ...
    └── save0001.png ~ ...
```

以下是 `saveg.dat` 被破坏后的完整恢复链路。

---

#### 第一阶段：打开 Load 菜单 — `isSaveFile()` 磁盘回退

`save.lua` 遍历槽位 1~99，对每个槽位调用 `isSaveFile(no)`。原版函数在 `sys.saveslot[no]` 为 nil 时直接放弃。补丁增加了 else 分支：

```lua
function isSaveFile(num, name)
    ...
    if s then
        file = s.file; ret = s; mask = s.evmask
    else
        -- FALLBACK: 磁盘回退
        local fname = (init.save_prefix or "save") .. string.format("%04d", no)
        if isFile(e:var("s.savepath") .. '/' .. fname .. ".dat") then
            file = fname
            ret = {
                text  = "",
                title = {},
                date  = (_save_dates[no] or get_unixtime()),
                file  = fname,
                evmask= nil,
            }
            sys.saveslot[no] = ret    -- 索引修复
        end
    end
    ...
end
```

`isFile()` 确认 `save0001.dat` 在磁盘上真实存在后，用 `_save_dates` 表（`install.ps1` 从该机器的 `saveXXXX.png` 缩略图时间一次性生成）获取接近原始的存档日期，创建最小条目。

**此时**：所有存档在 Load 界面可见，日期就位。标题和对话文本为空白。

---

#### 第二阶段：加载存档 — `restore()` 元数据恢复

用户加载存档后，Artemis Engine 将 `save0001.dat` 解压反序列化，`scr` 表完整恢复到内存中。引擎随后调用 `restore()`，补丁在此处注入元数据恢复逻辑：

```lua
function restore(e, p)
    loadconv(true)
    -- metadata auto-recovery
    local function __recover_metadata()
        local no = tonumber(tostring(p.file):match("save(%d+)"))
        if no and no < init.save_suspend then
            local t = sys.saveslot[no]
            if t then
                local need_save = false
                -- 章节标题: scr.adv.title
                local ti = sv.getsavetitle()
                if ti and next(ti) ~= nil then t.title = ti; need_save = true end
                -- 对话文本: scr.ip.save.text
                -- 存档日期: scr.ip.save.date
                if scr.ip and scr.ip.save then
                    local tx = scr.ip.save.text
                    local dt = scr.ip.save.date
                    if tx and tx ~= "" then
                        if type(tx) ~= "string" or tx ~= "autosave" then
                            t.text = tx; need_save = true
                        end
                    end
                    if dt and type(dt) == "table" and #dt >= 6 then
                        t.date = dt; need_save = true
                    end
                end
                if need_save then asyssave() end  -- 持久化到 saveg.dat
            end
        end
    end
    pcall(__recover_metadata)
    ...
end
```

数据来源追踪：

| 恢复项 | 内存来源 | 写入来源 | 说明 |
|--------|----------|----------|------|
| 章节标题 | `scr.adv.title` | 游戏脚本 `sv.savetitle()` | 每次进新章节时设定 |
| 对话文本 | `scr.ip.save.text` | `sv.save()` → `getTextBlockText()` | 存档时捕获的当前文本 |
| 存档日期 | `scr.ip.save.date` | `sv.save()` → `get_unixtime()` | 存档时的精确时间 |

**此时**：标题、对话文本、日期三项全部恢复，`asyssave()` 将完整条目持久化到 `saveg.dat`。再次打开 Load 界面时，`sys.saveslot[1]` 已完整——不需要再走回退。

---

#### 第三阶段（无感知）：存档时嵌入日期 — `fsave.lua`

为使补丁后新创建的存档自带精确日期，`fsave.lua` 做了一行改动：

```lua
-- 原版:
scr.ip.save = { text=(tx), txno=(ax.lang), crc=(ax.crc) }

-- 补丁版:
scr.ip.save = { text=(tx), txno=(ax.lang), crc=(ax.crc), date=get_unixtime() }
```

存档时将当前时间嵌入 BOWS 文件内部。第二阶段 `restore()` 读取的 `scr.ip.save.date` 即来源于此。补丁前的旧存档无此字段，日期由 `_save_dates` 表兜底。

---


### 聲明

本修補程式為非官方第三方修補程式，僅供學習交流使用，禁止商用。原遊戲的全部程式碼、劇情、美術、音訊等內容，版權歸原作者 / 開發團隊所有。若著作權所有者提出異議，本專案將立即下架。

### 簡介

這是一個個人製作的 NUKITASHI / NUKITASHI 2（Steam 版）**存檔修復補丁**，旨在無損、便捷地復原原存檔的可讀性。如果它對你有幫助，歡迎點亮⭐️支持本專案！

### 要求

- Windows 8+（使用內建 PowerShell 3.0）
- NUKITASHI / NUKITASHI 2（Steam 版，Artemis Engine）（非Steam版暫未測試相容性）

### 使用方法

**安裝補丁：**

1. 雙擊 install.bat
2. 按螢幕提示完成操作
 （NUKITASHI Save Fix 資料夾中的檔案是補丁輔助安裝程式，補丁成功後即可刪除此資料夾）
3. 啟動遊戲，進入 Load 頁面，此時將會看到擁有正確日期但章節和角色語句空白的存檔出現。
4. 對上述存檔進行讀檔操作（無需存檔），完成讀檔後返回 Load 頁面，空白部分將會顯示章節以及角色語句。

**卸載補丁：**

刪除遊戲資料夾下的 `system/adv/fileio.lua` 和 `system/adv/fsave.lua` 即可。PFS 封包內的原始遊戲檔案從未被修改，無須擔心。

### 文件

| 文件 | 作用 |
|------|------|
| `install.bat` | 雙擊執行，繞過 PowerShell 執行策略 |
| `install.ps1` | 掃描 `saveXXXX.png` 修改時間 → 生成 `_save_dates` 表 → 組裝 `fileio.lua` |
| `fileio_template.lua` | 修補範本，`-- DATE_TABLE_PLACEHOLDER --` 由指令碼替換 |
| `fsave.lua` | 預修補版（一行改動：嵌入日期到 BOWS） |

### 補丁工作原理

遊戲使用 Artemis Engine。存檔系統依賴 `savedata/saveg.dat` 中的一個 Lua 表 `sys.saveslot` 來索引所有欄位。當該檔案因 Steam 雲端同步等原因被覆寫，`sys.saveslot` 遺失——Load 介面變為空白，但其實 `savedata/` 下的 `saveNNNN.dat` 完整無損。

故本修補程式透過**修改遊戲的兩個 Lua 腳本**（引擎優先讀取檔案系統中的 `.lua` 檔案，覆蓋 PFS 封包內的原腳本），在 `sys.saveslot` 缺失時直接檢查磁碟檔案重建索引，載入存檔後從 BOWS 資料中自動恢復章節標題和對話文字。

修補程式修改了兩個檔案，部署後遊戲目錄結構：

```
NUKITASHI/
├── NUKITASHI.exe
├── NUKITASHI.pfs                ← 原始 fileio.lua / fsave.lua 在此封包內
├── system/
│   └── adv/
│       ├── fileio.lua           ← ★ 修補版（引擎優先讀取）
│       └── fsave.lua            ← ★ 修補版
└── savedata/
    ├── saveg.dat                ← 欄位索引（可能被破壞）
    ├── save0001.dat ~ ...
    └── save0001.png ~ ...
```

以下是 `saveg.dat` 被破壞後的完整恢復鏈路。

---

#### 第一階段：開啟 Load 介面 — `isSaveFile()` 磁碟回退

`save.lua` 走訪欄位 1~99，對每個欄位呼叫 `isSaveFile(no)`。原版函式在 `sys.saveslot[no]` 為 nil 時直接放棄。修補程式增加了 else 分支：

```lua
function isSaveFile(num, name)
    ...
    if s then
        file = s.file; ret = s; mask = s.evmask
    else
        -- FALLBACK: 磁碟回退
        local fname = (init.save_prefix or "save") .. string.format("%04d", no)
        if isFile(e:var("s.savepath") .. '/' .. fname .. ".dat") then
            file = fname
            ret = {
                text  = "",
                title = {},
                date  = (_save_dates[no] or get_unixtime()),
                file  = fname,
                evmask= nil,
            }
            sys.saveslot[no] = ret    -- 索引修復
        end
    end
    ...
end
```

`isFile()` 確認 `save0001.dat` 在磁碟上真實存在後，用 `_save_dates` 表（`install.ps1` 從該機器的 `saveXXXX.png` 縮圖時間一次性生成）獲取接近原始的存檔日期，建立最小條目。

**此時**：所有存檔在 Load 介面可見，日期就位。標題和對話文字為空白。

---

#### 第二階段：載入存檔 — `restore()` 元資料恢復

使用者載入存檔後，Artemis Engine 將 `save0001.dat` 解壓反序列化，`scr` 表完整恢復到記憶體中。引擎隨後呼叫 `restore()`，修補程式在此處注入元資料恢復邏輯：

```lua
function restore(e, p)
    loadconv(true)
    -- metadata auto-recovery
    local function __recover_metadata()
        local no = tonumber(tostring(p.file):match("save(%d+)"))
        if no and no < init.save_suspend then
            local t = sys.saveslot[no]
            if t then
                local need_save = false
                -- 章節標題: scr.adv.title
                local ti = sv.getsavetitle()
                if ti and next(ti) ~= nil then t.title = ti; need_save = true end
                -- 對話文字: scr.ip.save.text
                -- 存檔日期: scr.ip.save.date
                if scr.ip and scr.ip.save then
                    local tx = scr.ip.save.text
                    local dt = scr.ip.save.date
                    if tx and tx ~= "" then
                        if type(tx) ~= "string" or tx ~= "autosave" then
                            t.text = tx; need_save = true
                        end
                    end
                    if dt and type(dt) == "table" and #dt >= 6 then
                        t.date = dt; need_save = true
                    end
                end
                if need_save then asyssave() end  -- 持久化到 saveg.dat
            end
        end
    end
    pcall(__recover_metadata)
    ...
end
```

資料來源追蹤：

| 恢復項 | 記憶體來源 | 寫入來源 | 說明 |
|--------|----------|----------|------|
| 章節標題 | `scr.adv.title` | 遊戲腳本 `sv.savetitle()` | 每次進入新章節時設定 |
| 對話文字 | `scr.ip.save.text` | `sv.save()` → `getTextBlockText()` | 存檔時捕獲的目前文字 |
| 存檔日期 | `scr.ip.save.date` | `sv.save()` → `get_unixtime()` | 存檔時的精確時間 |

**此時**：標題、對話文字、日期三項全部恢復，`asyssave()` 將完整條目持久化到 `saveg.dat`。再次開啟 Load 介面時，`sys.saveslot[1]` 已完整——不需要再走回退。

---

#### 第三階段（無感知）：存檔時嵌入日期 — `fsave.lua`

為使修補後新建立的存檔自帶精確日期，`fsave.lua` 做了一行改動：

```lua
-- 原版:
scr.ip.save = { text=(tx), txno=(ax.lang), crc=(ax.crc) }

-- 修補版:
scr.ip.save = { text=(tx), txno=(ax.lang), crc=(ax.crc), date=get_unixtime() }
```

存檔時將目前時間嵌入 BOWS 檔案內部。第二階段 `restore()` 讀取的 `scr.ip.save.date` 即來源於此。修補前的舊存檔無此欄位，日期由 `_save_dates` 表兜底。

---


### Disclaimer

This patch is an unofficial third-party patch, for educational and personal use only; commercial use is prohibited. All original game code, story, art, audio, and other content are the property of their respective copyright holders / development team. Should the copyright holders object, this project will be taken down immediately.

### About

A personal **save recovery patch** for NUKITASHI / NUKITASHI 2 (Steam edition), designed to restore save readability losslessly and conveniently. If it helps you, a ⭐️ would be appreciated!

### Requirements

- Windows 8+ (uses built-in PowerShell 3.0)
- NUKITASHI / NUKITASHI 2 (Steam edition, Artemis Engine) (non-Steam versions untested)

### Usage

**Install the patch:**

1. Double-click install.bat
2. Follow the on-screen prompts to complete the setup
 (The files in the NUKITASHI Save Fix folder are helper installers; you may delete this folder after the patch is successfully applied)
3. Launch the game and open the Load page — saves will appear with correct dates but blank chapter titles and dialogue text.
4. Load any of the above saves (no need to re-save); upon returning to the Load page, the previously blank fields will now display the chapter title and dialogue text.

**Uninstall the patch:**

Delete `system/adv/fileio.lua` and `system/adv/fsave.lua` from your game folder. The original game files inside the PFS archive are never modified — no need to worry.

### Files

| File | Purpose |
|------|---------|
| `install.bat` | Double-click launcher (bypasses PowerShell execution policy) |
| `install.ps1` | Scans `saveXXXX.png` timestamps → generates `_save_dates` table → assembles `fileio.lua` |
| `fileio_template.lua` | Patch template; `-- DATE_TABLE_PLACEHOLDER --` replaced by the script |
| `fsave.lua` | Pre-patched (one-line change: embed date into BOWS) |

### How the Patch Works

The game uses the Artemis Engine. Its save system relies on a Lua table `sys.saveslot` inside `savedata/saveg.dat` to index all slots. When this file is overwritten (e.g. by Steam Cloud sync), `sys.saveslot` is lost — the Load menu becomes empty, yet the `saveNNNN.dat` files under `savedata/` remain fully intact.

This patch works by **modifying two of the game's Lua scripts** (the engine loads loose `.lua` files from the filesystem in preference to those packed inside the PFS archive). When `sys.saveslot` is missing, it directly checks disk files to rebuild the index, and automatically recovers chapter titles and dialogue text from the BOWS data after loading a save.

Two files are patched. After deployment, the game directory looks like:

```
NUKITASHI/
├── NUKITASHI.exe
├── NUKITASHI.pfs                ← original fileio.lua / fsave.lua inside
├── system/
│   └── adv/
│       ├── fileio.lua           ← ★ patched (loaded by engine in preference)
│       └── fsave.lua            ← ★ patched
└── savedata/
    ├── saveg.dat                ← slot index (may be corrupted)
    ├── save0001.dat ~ ...
    └── save0001.png ~ ...
```

The following is the complete recovery chain after `saveg.dat` is corrupted.

---

#### Phase 1: Opening the Load Menu — `isSaveFile()` Disk Fallback

`save.lua` iterates slots 1~99, calling `isSaveFile(no)` for each. The original function gives up when `sys.saveslot[no]` is nil. The patch adds an else branch:

```lua
function isSaveFile(num, name)
    ...
    if s then
        file = s.file; ret = s; mask = s.evmask
    else
        -- FALLBACK: disk fallback
        local fname = (init.save_prefix or "save") .. string.format("%04d", no)
        if isFile(e:var("s.savepath") .. '/' .. fname .. ".dat") then
            file = fname
            ret = {
                text  = "",
                title = {},
                date  = (_save_dates[no] or get_unixtime()),
                file  = fname,
                evmask= nil,
            }
            sys.saveslot[no] = ret    -- index repaired
        end
    end
    ...
end
```

After `isFile()` confirms that `save0001.dat` physically exists on disk, the `_save_dates` table — generated once by `install.ps1` from the `saveXXXX.png` thumbnail timestamps on the player's own machine — provides a date close to the original save time, and a minimal entry is created.

**Result**: All saves visible in the Load menu. Dates are correct. Chapter titles and dialogue text are blank.

---

#### Phase 2: Loading a Save — `restore()` Metadata Recovery

When the player loads a save, the Artemis Engine decompresses and deserializes `save0001.dat`, restoring the entire `scr` table into memory. The engine then calls `restore()`, where the patch injects metadata recovery logic:

```lua
function restore(e, p)
    loadconv(true)
    -- metadata auto-recovery
    local function __recover_metadata()
        local no = tonumber(tostring(p.file):match("save(%d+)"))
        if no and no < init.save_suspend then
            local t = sys.saveslot[no]
            if t then
                local need_save = false
                -- Chapter title: scr.adv.title
                local ti = sv.getsavetitle()
                if ti and next(ti) ~= nil then t.title = ti; need_save = true end
                -- Dialogue text: scr.ip.save.text
                -- Save date:     scr.ip.save.date
                if scr.ip and scr.ip.save then
                    local tx = scr.ip.save.text
                    local dt = scr.ip.save.date
                    if tx and tx ~= "" then
                        if type(tx) ~= "string" or tx ~= "autosave" then
                            t.text = tx; need_save = true
                        end
                    end
                    if dt and type(dt) == "table" and #dt >= 6 then
                        t.date = dt; need_save = true
                    end
                end
                if need_save then asyssave() end  -- persist to saveg.dat
            end
        end
    end
    pcall(__recover_metadata)
    ...
end
```

Where each piece of data comes from:

| Recovered Item | Memory Source | Written By | Notes |
|---------------|--------------|------------|-------|
| Chapter title | `scr.adv.title` | Game script `sv.savetitle()` | Set each time a new chapter begins |
| Dialogue text | `scr.ip.save.text` | `sv.save()` → `getTextBlockText()` | The text captured at save time |
| Save date | `scr.ip.save.date` | `sv.save()` → `get_unixtime()` | The exact timestamp when saved |

**Result**: Title, dialogue text, and date are all recovered. `asyssave()` persists the complete entry to `saveg.dat`. The next time the Load menu opens, `sys.saveslot[1]` is fully populated — the fallback is no longer needed.

---

#### Phase 3 (Transparent): Embedding Dates at Save Time — `fsave.lua`

To ensure saves created after the patch carry their own exact date, a single line in `fsave.lua` is changed:

```lua
-- Original:
scr.ip.save = { text=(tx), txno=(ax.lang), crc=(ax.crc) }

-- Patched:
scr.ip.save = { text=(tx), txno=(ax.lang), crc=(ax.crc), date=get_unixtime() }
```

The current time is embedded into the BOWS file at save time. Phase 2 reads `scr.ip.save.date` from here. Old saves created before the patch lack this field — the `_save_dates` table serves as the fallback.

---

<br>
<p align="center">By 自宅警備員 &nbsp;|&nbsp; 2026.7</p>

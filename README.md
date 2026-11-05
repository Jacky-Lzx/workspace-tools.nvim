# workspace-tools.nvim

保存和恢复 Neovim workspace，并模糊搜索历史记录。无需第三方依赖，要求 Neovim 0.11+。

一个 workspace 对应一个工作目录，也可以在同一个目录下保存多个命名 workspace。使用原生 `:mksession` 保存文件列表、窗口与标签页布局、光标、视图、折叠和局部选项。历史按最近保存或恢复的时间排序。

## 安装

例如使用 lazy.nvim 加载本地插件：

```lua
{
  dir = "/Users/zexili/Documents/Github/nvim_plugins/workspace-tools.nvim",
  event = "VeryLazy",
  opts = {},
  config = function(_, opts)
    require("workspace_tools").setup(opts)
  end,
  keys = {
    { "<leader>pw", "<cmd>WorkspaceSave<cr>", desc = "Save workspace" },
    { "<leader>ps", "<cmd>WorkspaceRestore<cr>", desc = "Restore workspace" },
    { "<leader>pS", "<cmd>WorkspaceSearch<cr>", desc = "Search workspaces" },
    { "<leader>pD", "<cmd>WorkspaceDelete<cr>", desc = "Delete workspace" },
  },
}
```

默认不创建快捷键。上面的配置仅为示例，本仓库不会修改你的 Neovim 配置。

## 使用

| 命令 | 行为 |
| --- | --- |
| `:WorkspaceSave [name]` | 保存当前目录的 workspace，可指定包含空格的名称 |
| `:WorkspaceRestore [name-or-id]` | 恢复当前 workspace、当前目录的命名 workspace 或历史 ID |
| `:WorkspaceSearch [query]` | 搜索全部历史，回车恢复选中的 workspace |
| `:WorkspaceLast` | 恢复最近保存或使用的 workspace |
| `:WorkspaceDelete[!] [name-or-id]` | 删除记录，默认确认；`!` 跳过确认 |
| `:WorkspaceStop` | 暂停退出自动保存 |
| `:WorkspaceStart` | 恢复退出自动保存 |
| `:checkhealth workspace_tools` | 查看存储目录、无效记录和丢失的项目目录 |

无名称的保存/恢复优先使用当前目录内已激活的 workspace；否则使用当前目录的默认 workspace。`save({ name = "" })` 可明确保存默认 workspace。删除当前 workspace 会暂停自动保存，防止退出时重建记录；使用 `WorkspaceStart` 恢复。

workspace 的目录取自当前窗口生效的 cwd，不自动向上查找 Git 根目录。可以先 `:cd` 到项目根目录再保存。原生会话会记录窗口/标签页的局部目录。已有的 `selection_tools.projects()` 仍负责发现项目和打开文件，本插件负责持久化的编辑现场。

搜索优先使用可加载的 `selection-tools.nvim`。没有安装时使用内置浮窗：输入实时模糊搜索，`<C-n>`/`<Down>`、`<C-p>`/`<Up>` 选择，`<CR>` 恢复，`<Esc>`/`<C-c>` 取消。搜索和取消不会切换 workspace。丢失的项目目录仍显示在历史中，但不能恢复。

恢复前必须保存或丢弃所有已修改的缓冲区；插件不会替你写入文件。切换前可用 `WorkspaceSave` 保存当前布局。恢复成功后清理上一 workspace 的隐藏普通文件缓冲区。恢复失败会停止自动保存，保护磁盘上已有的记录；手动保存或成功恢复后解除阻止。原生会话恢复不是事务，错误前已打开的窗口和缓冲区可能保留。

## 默认选项

默认策略参考现有的 `auto-session` 配置：退出保存、启动不恢复、排除以下目录，并在保存前关闭临时任务/健康检查缓冲区。插件只在调用 `setup()` 后注册自动保存；仅加载命令不会注册自动保存。

```lua
require("workspace_tools").setup({
  directory = vim.fn.stdpath("state") .. "/workspace-tools",
  auto_save = true,
  auto_restore = false,
  suppressed_dirs = { "~/", "~/Projects", "~/Downloads", "/" },
  close_filetypes_on_save = { "checkhealth", "tasktools", "tasktoolsoutput" },
  sessionoptions = "buffers,curdir,folds,tabpages,winsize,winpos,localoptions",
  picker = "auto", -- "auto", "builtin", "selection" 或 vim.ui.select 兼容函数
  hooks = {
    pre_save = {},
    post_save = {},
    pre_restore = {},
    post_restore = {},
    post_delete = {},
  },
})
```

`suppressed_dirs` 精确匹配规范化后的目录，不会排除它们的子目录。`{}` 可清空排除列表。排除仅针对自动操作，手动命令仍可使用。自动保存也会跳过 headless、标准输入和带文件参数的启动；手动保存/恢复后允许后续自动保存。单个目录参数允许自动操作。没有任何普通文件缓冲区时不会自动创建空记录。

`auto_restore = true` 在启动时恢复当前目录的默认 workspace；支持 `VimEnter` 后的懒加载。不自动恢复历史中的其他目录，也不监视 `DirChanged`。有明确文件参数时不会自动恢复。

保存的是编辑器状态与磁盘文件路径，**不保存未写入的文本**。默认不保存终端、进程、任务输出或插件浮窗，也不重新启动任务。恢复后的局部选项（如 `foldexpr`）依赖相应插件或配置仍然存在。

## Lua API 与任务钩子

```lua
local workspace = require("workspace_tools")
local entry, err = workspace.save({ name = "Review" })
if not entry then
  vim.notify(err, vim.log.levels.ERROR)
end
workspace.restore(entry) -- 元数据表、完整 ID、当前目录内的名称或 nil
local items, errors = workspace.list({ query = "nvim", limit = 20 })
workspace.search({ query = "nvim", picker = "builtin" })
workspace.last()
workspace.delete(entry) -- API 直接删除，确认由调用方负责
workspace.stop()
workspace.start()
local status = workspace.status()
```

`save`、`restore`、`last`、`delete` 返回 `entry, nil` 或 `nil, error`。`list` 返回元数据列表及无效文件的错误列表，不会因一个损坏记录隐藏其他历史。`entry` 包含 `id`、`name`、`cwd`、`files`、`created_at`、`updated_at`、`accessed_at` 和 `missing`。时间戳以秒为单位，包含小数。不要把显示名称当作文件路径。

钩子接收一份 workspace 元数据副本。返回 `false` 或抛出错误会中止操作；`post_*` 发生在对应操作已完成之后。可直接接入你现有的任务集成：

```lua
hooks = {
  pre_save = { function(entry)
    require("features.tasks").save_session(entry.id)
  end },
  post_restore = { function(entry)
    require("features.tasks").restore_session(entry.id)
  end },
  post_delete = { function(entry)
    require("features.tasks").delete_session(entry.id)
  end },
}
```

任务定义的保存与恢复仍由 `task-tools.nvim` 负责；workspace-tools 不依赖个人配置中的 `features.tasks`。示例使用稳定 ID 区分同一目录的不同命名 workspace，不会自动导入旧 auto-session 的任务记录。

每条记录保存为一个 SHA-256 命名的 JSON 文件，含元数据和 Base64 编码的原生会话。私有临时文件写完后通过 rename 原子替换，已有记录不会暴露为半写入状态。只恢复本插件存储目录中的记录；会话内容具有原生 Vimscript 的执行能力。旧 auto-session 数据不做自动迁移，启用本插件时应移除旧插件的自动保存注册，避免两套生命周期同时运行。

## 验证

```sh
sh tests/run.sh
stylua --check lua plugin tests
```

测试使用隔离的临时目录。包含真实原生会话往返、布局/视图、脏缓冲区保护、钩子、损坏记录隔离，以及真实 PTY 下的输入、搜索、缩放、恢复、取消和跨进程启动/退出。存在相邻 `selection-tools.nvim` 时额外验证其真实 picker。

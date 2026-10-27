-- =============================================================================
-- WezTerm 现代化终端配置
-- 主题：Tokyo Night | 字体：JetBrainsMono Nerd Font + 中文自动回退
-- =============================================================================
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- -----------------------------------------------------------------------------
-- 1. 字体排版与回退链 (Typography & Font Fallbacks)
-- -----------------------------------------------------------------------------
-- 主字体优先使用 JetBrainsMono Nerd Font (代码连字 + 全套开发/终端图标)；
-- 中文平滑回退至现代黑体 Noto Sans CJK SC / 文泉驿微米黑，彻底告别字符缺失或竖向错位
config.font = wezterm.font_with_fallback {
  { family = 'JetBrainsMono Nerd Font', weight = 'Regular' },
  { family = 'PingFang SC' },
  { family = 'Noto Sans CJK SC', weight = 'Regular' },
  { family = 'WenQuanYi Micro Hei Mono' },
  { family = 'Noto Color Emoji' },
  { family = 'Symbols Nerd Font Mono' },
}

-- 字体基础字号
config.font_size = 12.0

-- 字符行高微调 (1.0 为标准行距，1.05 略微透气)
config.line_height = 1.05

-- -----------------------------------------------------------------------------
-- 2. 配色主题与视觉质感 (Aesthetics & Window)
-- -----------------------------------------------------------------------------
-- 官方 Tokyo Night 深色方案，与 Tmux、Neovim、Zsh 保持无缝一体视觉
config.color_scheme = 'Tokyo Night'

-- 背景微透明与毛玻璃效果 (0.95 既有通透质感，又保障代码对比度与可读性)
config.window_background_opacity = 0.95
config.macos_window_background_blur = 20

-- 窗口内边距（像素）：为代码提供优雅呼吸边距
config.window_padding = {
  left = 12,
  right = 12,
  top = 10,
  bottom = 10,
}

-- 窗口装饰与标题栏（Linux / macOS）
config.window_decorations = "RESIZE"

-- 当仅有单个标签页时自动隐藏 WezTerm 原生顶栏，避免与 Tmux 底部状态栏产生“双状态栏”视觉杂乱
config.hide_tab_bar_if_only_one_tab = true

-- -----------------------------------------------------------------------------
-- 3. 光标行为与输入体验 (Cursor & Input)
-- -----------------------------------------------------------------------------
-- 光标样式：BlinkingBar (呼吸细竖线) / BlinkingBlock (方块) / Underline (下划线)
config.default_cursor_style = 'BlinkingBar'
config.cursor_blink_rate = 650
config.cursor_blink_ease_in = 'Constant'
config.cursor_blink_ease_out = 'Constant'

-- -----------------------------------------------------------------------------
-- 4. 渲染性能与硬件加速 (Performance & GPU)
-- -----------------------------------------------------------------------------
-- 优先使用 WebGPU 硬件渲染引擎，最大化高刷新率屏幕流畅度
config.front_end = "WebGpu"
config.max_fps = 120
config.animation_fps = 1

-- -----------------------------------------------------------------------------
-- 5. 交互与功能开关 (Interaction & Functionality)
-- -----------------------------------------------------------------------------
-- 禁用系统尖锐蜂鸣音
config.audible_bell = "Disabled"

-- 历史回滚行数
config.scrollback_lines = 10000

-- 禁用自动检查更新弹窗（通过系统包管理器统一维护）
config.check_for_updates = false

return config

include_guard(GLOBAL)

option(PRETTY_PRINT_USE_ASCII_FALLBACK "Use simple ASCII characters instead of Unicode symbols" OFF)

if(NOT PRETTY_PRINT_USE_ASCII_FALLBACK)
    # --- Unicode 符号 (默认) ---
    # 状态 (Status)
    set(SYM_CHECK        "✓")   # Checkmark
    set(SYM_CROSS        "✗")   # Cross
    set(SYM_INFO         "ℹ")   # Information
    set(SYM_WARN         "⚠")   # Warning
    set(SYM_GEAR         "⚙")   # Gear
    set(SYM_FLAG         "⚑")   # Flag
    set(SYM_LINK         "🔗")  # Link
    set(SYM_LOCK         "🔒")  # Lock
    set(SYM_UNLOCK       "🔓")  # Unlock
    set(SYM_BELL         "🔔")  # Bell
    set(SYM_BUG          "🐞")  # Bug

    # 箭头 (Arrows)
    set(SYM_ARROW_R      "→")   # Right
    set(SYM_ARROW_L      "←")   # Left
    set(SYM_ARROW_U      "↑")   # Up
    set(SYM_ARROW_D      "↓")   # Down
    set(SYM_ARROW_RL     "↔")   # Left-Right
    set(SYM_ARROW_CURVED_R "↪") # Curved Right
    set(SYM_ARROW_CURVED_L "↩") # Curved Left

    # 圆点和星星 (Dots & Stars)
    set(SYM_CIRCLE       "○")   # Circle
    set(SYM_CIRCLE_F     "●")   # Filled Circle
    set(SYM_POINT_R      "▶")   # Pointer Right
    set(SYM_POINT_L      "◀")   # Pointer Left
    set(SYM_STAR_F       "★")   # Filled Star
    set(SYM_STAR_E       "☆")   # Empty Star

    # 块元素 (Block Elements)
    set(SYM_BLOCK_FULL   "█")
    set(SYM_BLOCK_7_8    "▉")
    set(SYM_BLOCK_3_4    "▊")
    set(SYM_BLOCK_5_8    "▋")
    set(SYM_BLOCK_HALF   "▌")
    set(SYM_BLOCK_3_8    "▍")
    set(SYM_BLOCK_1_4    "▎")
    set(SYM_BLOCK_1_8    "▏")

    # 框线绘制 (Box Drawing) - 单线
    set(SYM_BOX_V          "│") # Vertical
    set(SYM_BOX_H          "─") # Horizontal
    set(SYM_BOX_CORNER_TL  "┌") # Top-Left
    set(SYM_BOX_CORNER_TR  "┐") # Top-Right
    set(SYM_BOX_CORNER_BL  "└") # Bottom-Left
    set(SYM_BOX_CORNER_BR  "┘") # Bottom-Right
    set(SYM_BOX_T_DOWN     "┬")
    set(SYM_BOX_T_UP       "┴")
    set(SYM_BOX_T_RIGHT    "├")
    set(SYM_BOX_T_LEFT     "┤")
    set(SYM_BOX_CROSS      "┼")

    # 框线绘制 (Box Drawing) - 双线
    set(SYM_BOX2_V         "║")
    set(SYM_BOX2_H         "═")
    set(SYM_BOX2_CORNER_TL "╔")
    set(SYM_BOX2_CORNER_TR "╗")
    set(SYM_BOX2_CORNER_BL "╚")
    set(SYM_BOX2_CORNER_BR "╝")

    # 技术符号 (Technical)
    set(SYM_BRANCH       "") # Git Branch (Nerd Fonts)
    set(SYM_CPU          "") # CPU (Nerd Fonts)
    set(SYM_MEM          "MEM")
    set(SYM_FOLDER       "") # Folder (Nerd Fonts)
    set(SYM_FILE         "") # File (Nerd Fonts)

    # 其他 (Misc)
    set(SYM_HEART        "❤")
    set(SYM_LIGHTNING    "⚡")
    set(SYM_SMILE        "☺")
    set(SYM_PI           "π")
    set(SYM_INFINITY     "∞")

else()
    # --- ASCII 降级替代方案 ---

    # 状态 (Status)
    set(SYM_CHECK        "[OK]")
    set(SYM_CROSS        "[X]")
    set(SYM_INFO         "[i]")
    set(SYM_WARN         "[!]")
    set(SYM_GEAR         "{S}")
    set(SYM_FLAG         "{F}")
    set(SYM_LINK         "LNK")
    set(SYM_LOCK         "LCK")
    set(SYM_UNLOCK       "UNL")
    set(SYM_BELL         "ALM")
    set(SYM_BUG          "BUG")

    # 箭头 (Arrows)
    set(SYM_ARROW_R      "->")
    set(SYM_ARROW_L      "<-")
    set(SYM_ARROW_U      "^")
    set(SYM_ARROW_D      "v")
    set(SYM_ARROW_RL     "<->")
    set(SYM_ARROW_CURVED_R "->")
    set(SYM_ARROW_CURVED_L "<-")

    # 圆点和星星 (Dots & Stars)
    set(SYM_CIRCLE       "(o)")
    set(SYM_CIRCLE_F     "(*)")
    set(SYM_POINT_R      ">")
    set(SYM_POINT_L      "<")
    set(SYM_STAR_F       "*")
    set(SYM_STAR_E       ".")

    # 块元素 (Block Elements)
    set(SYM_BLOCK_FULL   "#")
    set(SYM_BLOCK_7_8    "#")
    set(SYM_BLOCK_3_4    "#")
    set(SYM_BLOCK_5_8    "#")
    set(SYM_BLOCK_HALF   "#")
    set(SYM_BLOCK_3_8    "#")
    set(SYM_BLOCK_1_4    "#")
    set(SYM_BLOCK_1_8    "#")

    # 框线绘制 (Box Drawing) - 单线
    set(SYM_BOX_V          "|")
    set(SYM_BOX_H          "-")
    set(SYM_BOX_CORNER_TL  "/")
    set(SYM_BOX_CORNER_TR  "\\")
    set(SYM_BOX_CORNER_BL  "\\")
    set(SYM_BOX_CORNER_BR  "/")
    set(SYM_BOX_T_DOWN     "-T-")
    set(SYM_BOX_T_UP       "_T_")
    set(SYM_BOX_T_RIGHT    "|-")
    set(SYM_BOX_T_LEFT     "-|")
    set(SYM_BOX_CROSS      "+")

    # 框线绘制 (Box Drawing) - 双线
    set(SYM_BOX2_V         "||")
    set(SYM_BOX2_H         "=")
    set(SYM_BOX2_CORNER_TL  "//")
    set(SYM_BOX2_CORNER_TR  "\\\\")
    set(SYM_BOX2_CORNER_BL  "\\\\")
    set(SYM_BOX2_CORNER_BR  "//")

    # 技术符号 (Technical)
    set(SYM_BRANCH       "BR:")
    set(SYM_CPU          "CPU:")
    set(SYM_MEM          "MEM:")
    set(SYM_FOLDER       "DIR:")
    set(SYM_FILE         "FILE:")

    # 其他 (Misc)
    set(SYM_HEART        "<3")
    set(SYM_LIGHTNING    "~")
    set(SYM_SMILE        ":)")
    set(SYM_PI           "PI")
    set(SYM_INFINITY     "inf")

endif()
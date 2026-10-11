"""One-off source patch: the port's menus drawn like the game's own Options screen."""
p = 'D:/i3-pc/runtime/src/core/i3/menu.cpp'
s = open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')
block = open('D:/i3-pc/tools/restyle_block.txt', encoding='utf-8').read()
helpers = open('D:/i3-pc/tools/restyle_helpers.txt', encoding='utf-8').read()

a = s.index("    // Laid out like the game's Options screen")
b = s.index("    if (activate_row >= 0) {\n        if (page == Page::Main || page == Page::Start")
s = s[:a] + block + s[b:]

a = s.index('/// One "[key] LABEL" hint, right aligned')
b = s.index('} // namespace\n\nvoid SetFont(')
s = s[:a] + helpers + s[b:]
open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('patched')

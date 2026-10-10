"""One-off source patch: skip re-adding buffer ranges the barrier tracker already holds."""
p = 'D:/i3-pc/runtime/src/video_core/renderer_vulkan/vk_runtime.cpp'
s = open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')
a = '''    if (src_access & WRITE_MASK) {
        resource->write_ranges.Add(range);
    }
    if (src_access & READ_MASK) {
        resource->read_ranges.Add(range);
    }
'''
b = '''    // Draws bind the same vertex and index ranges over and over between two barrier flushes.
    // A range the list already covers changes nothing; looking it up is a binary search, while
    // adding it again rewrites the middle of the list.
    if ((src_access & WRITE_MASK) && !resource->write_ranges.Contains(range.start, range.end)) {
        resource->write_ranges.Add(range);
    }
    if ((src_access & READ_MASK) && !resource->read_ranges.Contains(range.start, range.end)) {
        resource->read_ranges.Add(range);
    }
'''
assert s.count(a) == 1
open(p, 'w', encoding='utf-8', newline='').write(s.replace(a, b).replace('\n', nl))
print('patched')

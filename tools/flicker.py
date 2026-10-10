"""Frame-to-frame jitter of a recording: mean |F(n+1) - 2F(n) + F(n-1)| over grey frames."""
import os, sys
import numpy as np
p = 'D:/i3-pc/testrun/user/capture/frames.rgb'
n = os.path.getsize(p) // (960 * 540 * 3)
a = np.fromfile(p, dtype=np.uint8).reshape(n, 540, 960, 3).mean(axis=3)
d2 = np.abs(a[2:] - 2 * a[1:-1] + a[:-2]).mean(axis=(1, 2))
d1 = np.abs(a[1:] - a[:-1]).mean(axis=(1, 2))
print('%s: frames %d, step %.2f, jitter %.2f, ratio %.2f' % (sys.argv[1], n, d1.mean(), d2.mean(), d2.mean() / d1.mean()))

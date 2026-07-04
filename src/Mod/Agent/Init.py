import os

import _agent_init

_chromium_flags = [
    _flag
    for _flag in os.environ.get("QTWEBENGINE_CHROMIUM_FLAGS", "").split()
    if _flag not in ("--disable-gpu", "--disable-gpu-compositing")
]
os.environ["QTWEBENGINE_CHROMIUM_FLAGS"] = " ".join(_chromium_flags).strip()

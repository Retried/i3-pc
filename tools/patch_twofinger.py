"""One-off source patch: two-finger touchpad hold (binding touchpad_two_fingers)."""
R = 'D:/i3-pc/runtime/src/input/'


def rw(path, pairs):
    p = R + path
    s = open(p, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in s else '\n'
    s = s.replace('\r\n', '\n')
    for a, b in pairs:
        assert s.count(a) == 1, (path, a[:60], s.count(a))
        s = s.replace(a, b, 1)
    open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))


rw('input_handler.h', [
    ('#define TOUCH_SWIPE_RIGHT 0x04000003\n', '#define TOUCH_SWIPE_RIGHT 0x04000003\n#define TOUCH_TWO_FINGERS 0x04000004\n'),
    ('    {"touchpad_swipe_right", TOUCH_SWIPE_RIGHT},\n',
     '    {"touchpad_swipe_right", TOUCH_SWIPE_RIGHT},\n    {"touchpad_two_fingers", TOUCH_TWO_FINGERS},\n'),
    ('        ControllerOutput(TOUCH_SWIPE_RIGHT),\n',
     '        ControllerOutput(TOUCH_SWIPE_RIGHT),\n        ControllerOutput(TOUCH_TWO_FINGERS),\n'),
])
rw('input_handler.cpp', [
    ('''        default: // is a normal key (hopefully)
            controller->Button(SDLGamepadToOrbisButton(button), new_button_state);''',
     '''        case TOUCH_TWO_FINGERS:
            controller->SetTwoFingerTouch(new_button_state);
            break;
        default: // is a normal key (hopefully)
            controller->Button(SDLGamepadToOrbisButton(button), new_button_state);'''),
])
rw('controller.h', [
    ('    /// Plays a quick one-finger swipe across the touchpad; (dx, dy) is its direction.',
     '''    /// Two fingers resting on the touchpad, left and right of the middle, while held. A swipe
    /// started meanwhile moves both of them.
    void SetTwoFingerTouch(bool down);
    /// Plays a quick one-finger swipe across the touchpad; (dx, dy) is its direction.'''),
    ('    u64 m_swipe_start{};', '    u64 m_swipe_start{};\n    bool m_two_fingers{};'),
])
rw('controller.cpp', [
    ('''void GameController::StartTouchSwipe(float dx, float dy) {''',
     '''void GameController::SetTwoFingerTouch(bool down) {
    std::lock_guard lock{m_state_mutex};
    const u64 timestamp = Libraries::Kernel::sceKernelGetProcessTime();
    m_two_fingers = down;
    SetTouchLocked(0, down, 0.3f, 0.5f, timestamp);
    SetTouchLocked(1, down, 0.7f, 0.5f, timestamp);
    PushStateLocked(timestamp);
}

void GameController::StartTouchSwipe(float dx, float dy) {'''),
    ('''        SetTouchLocked(0, t < 1.0f, x, y, timestamp);
        if (t >= 1.0f) {''',
     '''        if (m_two_fingers) {
            // Both resting fingers travel together and stay down at the end.
            SetTouchLocked(0, true, x - 0.2f, y, timestamp);
            SetTouchLocked(1, true, x + 0.2f, y, timestamp);
        } else {
            SetTouchLocked(0, t < 1.0f, x, y, timestamp);
        }
        if (t >= 1.0f) {'''),
])
print('patched')
